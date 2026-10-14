import Foundation

/// Every change to the user's data goes through these functions, so the app and the tests share one implementation.
public extension AppData {
    func prediction(_ item: Item, today: Day) -> Prediction { Predictor.predict(item, today: today, soonDays: settings.soonDays) }

    func isNow(_ item: Item, today: Day) -> Bool { !item.inCart && (item.onList || prediction(item, today: today).status == .overdue) }
    func isSoon(_ item: Item, today: Day) -> Bool { !item.inCart && !item.onList && prediction(item, today: today).status == .soon }

    struct ListSections { public var now: [Item]; public var soon: [Item]; public var cart: [Item] }
    func listSections(today: Day) -> ListSections {
        let byDue: (Item, Item) -> Bool = { (prediction($0, today: today).daysLeft ?? 99) < (prediction($1, today: today).daysLeft ?? 99) }
        return ListSections(now: items.filter { isNow($0, today: today) }.sorted(by: byDue),
                            soon: items.filter { isSoon($0, today: today) }.sorted(by: byDue),
                            cart: items.filter(\.inCart))
    }

    // MARK: stores and prices

    func knownStores() -> [String] {
        var c: [String: Int] = [:]
        for it in items { for p in it.purchases where !p.store.isEmpty { c[p.store, default: 0] += 1 }; if let s = it.store, !s.isEmpty { c[s, default: 0] += 1 } }
        for t in trips where !t.store.isEmpty { c[t.store, default: 0] += 1 }
        return c.keys.sorted { c[$0]! != c[$1]! ? c[$0]! > c[$1]! : $0 < $1 }
    }

    static func autoStore(_ item: Item) -> String? {
        let recent = item.purchases.filter { !$0.store.isEmpty }.sorted { $0.date > $1.date }.prefix(8)
        guard !recent.isEmpty else { return nil }
        var c: [String: Int] = [:]; for p in recent { c[p.store, default: 0] += 1 }
        return c.keys.sorted { c[$0]! != c[$1]! ? c[$0]! > c[$1]! : $0 < $1 }.first
    }
    static func usualStore(_ item: Item) -> String? { (item.store?.isEmpty == false ? item.store : nil) ?? autoStore(item) }

    /// Latest unit price, at `store` when known there.
    static func lastPrice(_ item: Item, store: String?) -> Double? {
        let ps = item.purchases.filter { ($0.price ?? 0) > 0 }.sorted { $0.date > $1.date }
        if let store, let p = ps.first(where: { $0.store == store }) { return p.price }
        return ps.first?.price
    }
    static func estimatedLine(_ item: Item) -> Double? { lastPrice(item, store: usualStore(item)).map { $0 * Double(item.quantityOnList) } }

    struct StorePrice: Hashable { public var store: String; public var price: Double; public var date: Day }
    static func pricesByStore(_ item: Item) -> [StorePrice] {
        var m: [String: StorePrice] = [:]
        for p in item.purchases.filter({ ($0.price ?? 0) > 0 && !$0.store.isEmpty }).sorted(by: { $0.date < $1.date }) { m[p.store] = StorePrice(store: p.store, price: p.price!, date: p.date) }
        return m.values.sorted { $0.price < $1.price }
    }

    // MARK: list changes

    mutating func setLevel(_ id: String, _ level: StockLevel, today: Day) {
        guard let i = index(of: id) else { return }
        items[i].level = level
        items[i].snoozeUntil = nil
        if level == .stocked { items[i].stockedOn = today; items[i].onList = false }
    }

    mutating func toggleCart(_ id: String) {
        guard let i = index(of: id) else { return }
        items[i].inCart.toggle()
        if items[i].inCart { items[i].onList = true }
    }

    @discardableResult mutating func toggleList(_ id: String) -> Bool {
        guard let i = index(of: id) else { return false }
        items[i].onList.toggle(); items[i].inCart = false
        if items[i].onList { items[i].snoozeUntil = nil; items[i].level = .out } else if items[i].level == .out { items[i].level = nil }
        return items[i].onList
    }

    /// Pushes an item back by about a third of its interval. Returns the number of days.
    @discardableResult mutating func snooze(_ id: String, today: Day) -> Int {
        guard let i = index(of: id) else { return 0 }
        let days = max(2, Int(((prediction(items[i], today: today).interval ?? 7) * 0.3).rounded()))
        items[i].snoozeUntil = today.adding(days: days); items[i].onList = false; items[i].inCart = false; items[i].level = .used
        return days
    }

    mutating func delete(_ id: String) { items.removeAll { $0.id == id } }

    /// Adds typed entries to the list, reusing pantry items. Returns the names added.
    @discardableResult mutating func addToList(_ entries: [QuickAddEntry]) -> [String] {
        var added: [String] = []
        for e in entries {
            let i: Int
            if let found = QuickAdd.existing(e.name, in: items), let idx = index(of: found.id) { i = idx }
            else { items.append(Item(name: e.name.prefix(1).uppercased() + e.name.dropFirst(), category: Categories.guess(e.name))); i = items.count - 1 }
            items[i].onList = true; items[i].inCart = false; items[i].snoozeUntil = nil; items[i].level = .out
            items[i].listQty = e.qty > 1 ? e.qty : (items[i].listQty ?? 1)
            added.append(items[i].name)
        }
        return added
    }

    private mutating func markBought(_ i: Int, on date: Day) {
        items[i].inCart = false; items[i].onList = false; items[i].listQty = nil; items[i].snoozeUntil = nil
        items[i].level = .stocked
        if items[i].stockedOn == nil || date > items[i].stockedOn! { items[i].stockedOn = date }
    }

    /// Logs everything in the cart as one trip. `lineTotals` maps item id to the amount paid for that line.
    @discardableResult mutating func finishTrip(store: String, date: Day, lineTotals: [String: Double]) -> Trip {
        var lines: [TripLine] = []
        for i in items.indices where items[i].inCart {
            let q = items[i].quantityOnList
            let line = lineTotals[items[i].id].flatMap { $0 > 0 ? $0 : nil }
            items[i].purchases.append(Purchase(date: date, qty: q, price: line.map { ($0 / Double(q) * 100).rounded() / 100 }, store: store))
            lines.append(TripLine(itemId: items[i].id, name: items[i].name, qty: q, price: line))
            markBought(i, on: date)
        }
        let total = lines.compactMap(\.price).reduce(0, +)
        let trip = Trip(date: date, store: store, total: total > 0 ? total : nil, items: lines, source: .trip)
        trips.append(trip)
        return trip
    }

    struct ReceiptLine: Hashable, Sendable {
        public var name: String; public var qty: Int; public var lineTotal: Double?; public var category: String
        /// nil creates a new item (or reuses one with the same name).
        public var itemId: String?
        public init(name: String, qty: Int, lineTotal: Double?, category: String, itemId: String?) { self.name = name; self.qty = qty; self.lineTotal = lineTotal; self.category = category; self.itemId = itemId }
    }

    /// Saves a reviewed receipt as a trip, creating items and remembering receipt names as aliases.
    @discardableResult mutating func saveReceipt(store: String, date: Day, total: Double?, lines: [ReceiptLine]) -> Trip {
        var out: [TripLine] = []
        for l in lines where !l.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let name = l.name.trimmingCharacters(in: .whitespaces)
            var i = l.itemId.flatMap { index(of: $0) } ?? items.firstIndex { Words.norm($0.name) == Words.norm(name) }
            if i == nil { items.append(Item(name: name, category: l.category)); i = items.count - 1 }
            let idx = i!
            if Words.norm(items[idx].name) != Words.norm(name) && !items[idx].aliases.contains(where: { Words.norm($0) == Words.norm(name) }) {
                items[idx].aliases.append(name); if items[idx].aliases.count > 12 { items[idx].aliases.removeFirst() }
            }
            let q = max(1, l.qty), line = l.lineTotal.flatMap { $0 > 0 ? $0 : nil }
            items[idx].purchases.append(Purchase(date: date, qty: q, price: line.map { ($0 / Double(q) * 100).rounded() / 100 }, store: store))
            out.append(TripLine(itemId: items[idx].id, name: items[idx].name, qty: q, price: line))
            markBought(idx, on: date)
        }
        let trip = Trip(date: date, store: store, total: total, items: out, source: .receipt)
        trips.append(trip)
        return trip
    }

    // MARK: sharing

    func listText(today: Day) -> String {
        let now = listSections(today: today).now
        var by: [String: [Item]] = [:]
        for it in now { by[AppData.usualStore(it) ?? "", default: []].append(it) }
        let stores = by.keys.sorted { ($0.isEmpty ? 1 : 0, $0) < ($1.isEmpty ? 1 : 0, $1) }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        var lines = ["Shopping list, \(f.string(from: today.date(hour: 12) ?? Date()))"]
        for s in stores {
            lines.append(""); lines.append(s.isEmpty ? "Any store" : s)
            for it in by[s]! { lines.append("☐ \(it.name)\(it.quantityOnList > 1 ? " ×\(it.quantityOnList)" : "")\(it.notes.map { " (\($0))" } ?? "")") }
        }
        let est = now.compactMap(AppData.estimatedLine).reduce(0, +)
        if est > 0 { lines.append(""); lines.append(String(format: "About $%.2f", est)) }
        return lines.joined(separator: "\n")
    }
}
