import SwiftUI
import RestockKit

/// Identifies a sheet or navigation destination by an item or trip id.
struct IDBox: Identifiable, Hashable { let id: String }

enum LookupState: Equatable { case pending, noMatch, offline, busy }

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let undo: AppData?
    static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

/// Owns the user's data. Every change goes through `change`, which saves to disk,
/// refreshes reminders and the app icon badge, and can offer Undo.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data: AppData
    @Published var lookups: [String: LookupState] = [:]
    @Published var toast: Toast?
    /// Bumped on user actions to play a light haptic.
    @Published var hapticTick = 0

    private let fileURL: URL
    private var toastTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var reminderTask: Task<Void, Never>?

    var today: Day { Day.today() }
    var settings: AppSettings { data.settings }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("restock.json")
        if let saved = try? Data(contentsOf: fileURL), let decoded = try? AppData.decode(saved) {
            data = decoded
        } else {
            data = AppData()
        }
    }

    // MARK: change pipeline

    func change(_ message: String? = nil, undoable: Bool = true, haptic: Bool = true, _ body: (inout AppData) -> Void) {
        let before = data
        body(&data)
        scheduleSave()
        scheduleReminders()
        if haptic { hapticTick += 1 }
        if let message { show(message, undo: undoable ? before : nil) }
    }

    func show(_ message: String, undo: AppData? = nil) {
        toast = Toast(message: message, undo: undo)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    func undoLast() {
        guard let snapshot = toast?.undo else { return }
        data = snapshot
        toast = nil
        scheduleSave(); scheduleReminders()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = data, url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            try? snapshot.encoded().write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    private func scheduleReminders() {
        reminderTask?.cancel()
        reminderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.syncReminders()
        }
    }

    func syncReminders() async {
        let plan = ReminderPlanner.plan(data, today: today)
        await Notifications.sync(plan, enabled: settings.notifications)
        await Notifications.setBadge(settings.badge ? nowCount : 0)
    }

    /// Called when the app comes back to the foreground: the date may have changed.
    func refresh() {
        objectWillChange.send()
        Task { await syncReminders() }
    }

    var nowCount: Int { data.listSections(today: today).now.count }

    // MARK: list actions

    func setLevel(_ id: String, _ level: StockLevel) { change { $0.setLevel(id, level, today: today) } }
    func toggleCart(_ id: String) { change { $0.toggleCart(id) } }
    func toggleList(_ id: String) {
        let name = data.item(id)?.name ?? "Item"
        var nowOn = false
        change(nil) { nowOn = $0.toggleList(id) }
        show(nowOn ? "\(name) added to list" : "\(name) removed from list")
    }
    func snooze(_ id: String) {
        let name = data.item(id)?.name ?? "Item"
        var days = 0
        let before = data
        change { days = $0.snooze(id, today: today) }
        show("\(name) snoozed for \(days) days", undo: before)
    }
    func delete(_ id: String) {
        let name = data.item(id)?.name ?? "Item"
        change("\(name) deleted") { $0.delete(id) }
    }
    func addFromText(_ text: String) {
        let entries = QuickAdd.parse(text)
        guard !entries.isEmpty else { return }
        var added: [String] = []
        let before = data
        change { added = $0.addToList(entries) }
        show(added.count == 1 ? "\(added[0]) added" : "\(added.count) items added", undo: before)
    }
    func updateItem(_ id: String, haptic: Bool = false, _ body: (inout Item) -> Void) {
        change(undoable: false, haptic: haptic) { d in if let i = d.index(of: id) { body(&d.items[i]) } }
    }
    func updateSettings(_ body: (inout AppSettings) -> Void) { change(undoable: false, haptic: false) { body(&$0.settings) } }

    // MARK: trips and receipts

    func finishTrip(store: String, date: Day, lineTotals: [String: Double]) {
        let cartIDs = data.items.filter(\.inCart).map(\.id)
        var trip: Trip?
        let before = data
        change { trip = $0.finishTrip(store: store, date: date, lineTotals: lineTotals) }
        let total = trip?.displayTotal
        show("Trip saved · \(trip?.items.count ?? 0) items\(total.map { " · " + money($0) } ?? "")", undo: before)
        if settings.autoProducts { autoMatch(cartIDs, store: store, quiet: true) }
    }

    /// Saves a reviewed receipt and starts looking up its products. Returns the new trip's id.
    @discardableResult
    func saveReceipt(store: String, date: Day, total: Double?, lines: [AppData.ReceiptLine]) -> String {
        var trip: Trip!
        let before = data
        change { trip = $0.saveReceipt(store: store, date: date, total: total, lines: lines) }
        show("Saved \(trip.items.count) purchases\(store.isEmpty ? "" : " from \(store)")", undo: before)
        if settings.autoProducts { autoMatch(trip.items.compactMap(\.itemId), store: store) }
        return trip.id
    }

    func makeDraft(from text: String) -> ReceiptDraft {
        let parsed = ReceiptParser.parse(text, today: today)
        var lines = parsed.items.map { p -> ReceiptDraft.Line in
            let match = Matching.best(p.name, in: data.items).first?.item
            return ReceiptDraft.Line(name: p.name, qty: p.qty, price: String(format: "%.2f", p.price), category: match?.category ?? Categories.guess(p.name), match: match?.id)
        }
        if lines.isEmpty { lines = [ReceiptDraft.Line(name: "", qty: 1, price: "", category: "Other", match: nil)] }
        return ReceiptDraft(store: parsed.store ?? "", date: (parsed.date ?? today).date(hour: 12) ?? Date(), total: parsed.total.map { String(format: "%.2f", $0) } ?? "", lines: lines, rawText: text)
    }

    // MARK: products

    func setProduct(_ id: String, _ product: Product?, confirmed: Bool = true) {
        updateItem(id, haptic: true) { item in
            var p = product
            p?.confirmed = confirmed
            item.product = p
        }
        lookups[id] = nil
    }
    func confirmProduct(_ id: String) { updateItem(id, haptic: true) { $0.product?.confirmed = true } }

    /// Looks up products one by one (the client paces requests to Open Food Facts' limit).
    func autoMatch(_ ids: [String], store: String?, quiet: Bool = false) {
        let todo = ids.filter { data.item($0)?.product == nil && lookups[$0] != .pending }
        guard !todo.isEmpty else { return }
        for id in todo { lookups[id] = .pending }
        Task {
            var found = 0, offline = false
            for id in todo {
                guard let item = data.item(id) else { lookups[id] = nil; continue }
                do {
                    if let p = try await OpenFoodFacts.shared.suggestion(for: item.name, store: store ?? AppData.usualStore(item)) {
                        if data.item(id)?.product == nil { updateItem(id) { $0.product = p }; found += 1 }
                        lookups[id] = nil
                    } else {
                        lookups[id] = .noMatch
                    }
                } catch ProductLookupError.offline {
                    offline = true
                    for rest in todo where lookups[rest] == .pending { lookups[rest] = .offline }
                    break
                } catch {
                    lookups[id] = .busy
                }
            }
            if offline { show("Couldn't reach the product database. Check your connection.") }
            else if !quiet || found > 0 { show(found > 0 ? "Found products for \(found) of \(todo.count) items" : "No confident product matches. Pick them in each item.") }
        }
    }

    // MARK: purchases, backup, data

    func addPurchase(_ id: String, _ purchase: Purchase) { updateItem(id, haptic: true) { $0.purchases.append(purchase) }; show("Purchase added") }
    func removePurchase(_ id: String, at index: Int) {
        let before = data
        updateItem(id) { if $0.purchases.indices.contains(index) { $0.purchases.remove(at: index) } }
        show("Purchase removed", undo: before)
    }

    func backupJSON() -> String { (try? data.encoded(pretty: true)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }

    func restore(from text: String) throws {
        let decoded = try AppData.decode(Data(text.utf8))
        change("Backup restored") { $0 = decoded }
    }

    func loadSample() { change("Example pantry loaded") { $0 = AppData.sample(today: today, settings: $0.settings) } }
    func deleteEverything() { change("Everything deleted") { $0 = AppData(settings: $0.settings) } }
}

/// A receipt being reviewed before it's saved.
struct ReceiptDraft: Hashable {
    var store: String
    var date: Date
    var total: String
    var lines: [Line]
    var rawText: String

    struct Line: Hashable, Identifiable {
        var id = UUID()
        var include = true
        var name: String
        var qty: Int
        var price: String
        var category: String
        /// Pantry item id, or nil for a new item.
        var match: String?
    }
}
