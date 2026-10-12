import Foundation
import Combine
import TVRemoteCore
import GoogleTVRemote
import RokuRemote
#if os(watchOS)
import WatchKit
#endif

/// App-wide state: saved TVs, the selected TV's live connection and what it reports.
@MainActor
final class RemoteStore: ObservableObject {
    enum Phase: Equatable {
        case noTVs
        case connecting
        case pairingPrompt
        case connected
        case disconnected(String?)
    }

    struct VolumeInfo: Equatable {
        var level: Int
        var max: Int
        var muted: Bool
    }

    @Published private(set) var tvs: [SavedTV] = []
    @Published private(set) var selected: SavedTV?
    @Published private(set) var phase: Phase = .noTVs
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var isOn: Bool?
    @Published private(set) var currentApp: String?
    @Published private(set) var apps: [TVApp] = []
    @Published var identityError: String?

    var supportedKeys: Set<TVKey> { controller?.supportedKeys ?? Set(TVKey.allCases) }
    var supportsHold: Bool { controller?.supportsHold ?? true }
    var textEntry: TextEntryFeatures { controller?.textEntry ?? .none }

    private var controller: TVController?
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var shouldStayConnected = false

    /// App Group defaults so the widget extension and App Intents see the same TVs.
    static let sharedDefaults: UserDefaults = ComplicationState.sharedDefaults ?? .standard
    private let saved = SavedTVStore(defaults: RemoteStore.sharedDefaults)
    private let secrets = SecretStore.shared
    private var pendingKey: (TVKey, TVKeyPhase)?
    private var volumeTask: Task<Void, Never>?
    @Published private(set) var favoriteIDs: [String] = []

    private let sync = TVSync.shared
    private var lastAppliedSync: Date?
    private static let lastSyncKey = "tvremote.lastAppliedSync"

    init() {
        KeychainConfig.accessGroup = ComplicationState.appGroupID.flatMap { $0.hasPrefix("$(") ? nil : $0 }
        Self.migrateDefaultsIfNeeded(into: saved)
        tvs = saved.tvs
        selected = tvs.first { $0.id == saved.selectedID } ?? tvs.first
        phase = tvs.isEmpty ? .noTVs : .disconnected(nil)
        lastAppliedSync = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
        favoriteIDs = Self.loadFavorites(for: selected?.id)
        sync.onReceive = { [weak self] payload in self?.apply(payload) }
        sync.activate()
    }

    /// Earlier builds kept TVs in standard defaults; move them to the shared container once.
    private static func migrateDefaultsIfNeeded(into store: SavedTVStore) {
        guard sharedDefaults !== UserDefaults.standard, store.tvs.isEmpty else { return }
        let legacy = SavedTVStore(defaults: .standard)
        guard !legacy.tvs.isEmpty else { return }
        store.tvs = legacy.tvs
        store.selectedID = legacy.selectedID
        legacy.tvs = []
    }

    /// Called when the app comes to the foreground: reconnect fast and, with
    /// several TVs, jump to the one that is actually on.
    func activate() {
        reconnectAttempts = 0
        connect()
        Task { await autoSelectPoweredTV() }
    }

    private func autoSelectPoweredTV() async {
        guard tvs.count > 1, let current = selected else { return }
        let candidates = tvs
        // nil = unknown, true = on, false = off or unreachable.
        var results: [UUID: Bool] = [:]
        await withTaskGroup(of: (UUID, Bool?).self) { group in
            for tv in candidates {
                group.addTask {
                    let checked: Bool?? = try? await withTimeout(seconds: 3) { await ControllerFactory.quickPowerCheck(tv) }
                    return (tv.id, checked.flatMap { $0 })
                }
            }
            for await (id, isOn) in group {
                if let isOn { results[id] = isOn }
            }
        }
        // Only move away from the current TV when we know it is off/unreachable
        // and we know another one is on.
        guard results[current.id] == false, phase != .connected,
              let poweredOn = candidates.first(where: { results[$0.id] == true }) else { return }
        select(poweredOn)
    }

    // MARK: Sync with the other device

    /// Publishes TVs, credentials and the Google TV identity to the paired phone/watch.
    private func pushSync() {
        var credentials: [String: String] = [:]
        for tv in tvs {
            if let credential = secrets.credential(for: tv.id) { credentials[tv.id.uuidString] = credential }
        }
        var certificate: Data?
        var key: Data?
        if tvs.contains(where: { $0.brand == .googleTV }),
           let identity = try? ClientIdentity.load(),
           let exported = try? identity.exportDER() {
            certificate = exported.certificate
            key = exported.privateKey
        }
        let now = Date()
        lastAppliedSync = now
        UserDefaults.standard.set(now, forKey: Self.lastSyncKey)
        sync.push(SyncPayload(tvs: tvs, credentials: credentials, identityCertificate: certificate,
                              identityKey: key, updatedAt: now))
    }

    /// Adopts the other device's state when it is newer than ours.
    private func apply(_ payload: SyncPayload) {
        if let last = lastAppliedSync, payload.updatedAt <= last { return }
        lastAppliedSync = payload.updatedAt
        UserDefaults.standard.set(payload.updatedAt, forKey: Self.lastSyncKey)

        let currentID = selected?.id
        disconnect()
        for tv in tvs where !payload.tvs.contains(where: { $0.id == tv.id }) {
            secrets.setCredential(nil, for: tv.id)
        }
        saved.tvs = payload.tvs
        for tv in payload.tvs {
            secrets.setCredential(payload.credentials[tv.id.uuidString], for: tv.id)
        }
        if let certificate = payload.identityCertificate, let key = payload.identityKey {
            let local = try? ClientIdentity.load()?.exportDER()
            if local?.certificate != certificate {
                _ = try? ClientIdentity.install(certificateDER: certificate, privateKeyDER: key)
            }
        }
        tvs = saved.tvs
        selected = tvs.first { $0.id == currentID } ?? tvs.first { $0.id == saved.selectedID } ?? tvs.first
        saved.selectedID = selected?.id
        resetTVState()
        if selected == nil {
            phase = .noTVs
        } else {
            phase = .disconnected(nil)
            connect()
        }
    }

    // MARK: Identity (Google TV)

    func identity() throws -> ClientIdentity {
        do {
            let identity = try ClientIdentity.loadOrCreate()
            identityError = nil
            return identity
        } catch {
            identityError = String(describing: error)
            throw error
        }
    }

    // MARK: TV list

    func add(_ tv: SavedTV, credential: String?) {
        saved.upsert(tv)
        secrets.setCredential(credential, for: tv.id)
        tvs = saved.tvs
        select(tv)
        pushSync()
    }

    func rename(_ tv: SavedTV, to name: String) {
        var updated = tv
        updated.name = name
        saved.upsert(updated)
        tvs = saved.tvs
        if selected?.id == tv.id { selected = updated }
        pushSync()
    }

    func select(_ tv: SavedTV) {
        guard tv.id != selected?.id || controller == nil else { return }
        disconnect()
        selected = tv
        saved.selectedID = tv.id
        resetTVState()
        favoriteIDs = Self.loadFavorites(for: tv.id)
        connect()
        publishComplicationState()
    }

    func setColor(_ tv: SavedTV, colorName: String?) {
        var updated = tv
        updated.colorName = colorName
        saved.upsert(updated)
        tvs = saved.tvs
        if selected?.id == tv.id { selected = updated }
        pushSync()
    }

    // MARK: Favorites (pinned apps, per TV)

    var favoriteApps: [TVApp] {
        favoriteIDs.compactMap { id in apps.first { $0.id == id } }
    }

    func isFavorite(_ app: TVApp) -> Bool { favoriteIDs.contains(app.id) }

    func toggleFavorite(_ app: TVApp) {
        if let index = favoriteIDs.firstIndex(of: app.id) {
            favoriteIDs.remove(at: index)
        } else {
            favoriteIDs.append(app.id)
            if favoriteIDs.count > 4 { favoriteIDs.removeFirst() }
        }
        if let id = selected?.id {
            Self.sharedDefaults.set(favoriteIDs, forKey: Self.favoritesKey(id))
        }
        Haptics.play(.click)
    }

    private static func favoritesKey(_ id: UUID) -> String { "tvremote.favorites.\(id.uuidString)" }

    private static func loadFavorites(for id: UUID?) -> [String] {
        guard let id else { return [] }
        return sharedDefaults.stringArray(forKey: favoritesKey(id)) ?? []
    }

    func remove(_ tv: SavedTV) {
        if tv.id == selected?.id { disconnect() }
        saved.remove(id: tv.id)
        secrets.setCredential(nil, for: tv.id)
        tvs = saved.tvs
        if tvs.isEmpty {
            selected = nil
            phase = .noTVs
            resetTVState()
        } else if tv.id == selected?.id, let next = tvs.first {
            select(next)
        }
        pushSync()
        publishComplicationState()
    }

    /// Forgets every TV and the Google TV client certificate.
    func resetEverything() {
        disconnect()
        for tv in tvs { secrets.setCredential(nil, for: tv.id) }
        saved.tvs = []
        saved.selectedID = nil
        tvs = []
        selected = nil
        phase = .noTVs
        resetTVState()
        ClientIdentity.reset()
        pushSync()
    }

    private func resetTVState() {
        volume = nil
        isOn = nil
        currentApp = nil
        apps = []
    }

    // MARK: Connection lifecycle

    func connect() {
        guard let tv = selected else { return }
        shouldStayConnected = true
        guard connectTask == nil, phase != .connected else { return }
        phase = .connecting

        connectTask = Task { [weak self] in
            guard let self else { return }
            defer { self.connectTask = nil }
            do {
                let controller = try ControllerFactory.make(for: tv, credential: self.secrets.credential(for: tv.id), identity: self.identity)
                self.controller = controller
                self.eventTask?.cancel()
                self.eventTask = Task { [weak self] in
                    for await event in controller.events {
                        await self?.handle(event)
                    }
                }
                try await controller.connect()
                // A refreshed credential (Samsung re-issues tokens) must be kept.
                if let credential = controller.credential, credential != self.secrets.credential(for: tv.id) {
                    self.secrets.setCredential(credential, for: tv.id)
                    self.pushSync()
                }
                self.reconnectAttempts = 0
                self.phase = .connected
                self.tuneForBattery(controller)
                if let (key, phase) = self.pendingKey {
                    self.pendingKey = nil
                    try? await controller.send(key, phase: phase)
                }
                await self.refreshApps()
            } catch {
                self.controller?.disconnect()
                self.controller = nil
                self.phase = .disconnected(ErrorText.describe(error))
                if case TVControllerError.notAuthorized = error { return }
                self.scheduleReconnect()
            }
        }
    }

    func disconnect() {
        shouldStayConnected = false
        connectTask?.cancel()
        connectTask = nil
        eventTask?.cancel()
        eventTask = nil
        controller?.disconnect()
        controller = nil
        if selected != nil, phase == .connected || phase == .connecting || phase == .pairingPrompt {
            phase = .disconnected(nil)
        }
    }

    private func handle(_ event: TVEvent) {
        switch event {
        case .pairingPrompt:
            phase = .pairingPrompt
        case .connected:
            phase = .connected
            publishComplicationState()
        case let .powerChanged(isOn):
            self.isOn = isOn
            publishComplicationState()
        case let .volumeChanged(level, max, muted):
            volume = VolumeInfo(level: level, max: max, muted: muted)
        case let .currentApp(name):
            currentApp = name
        case let .disconnected(reason):
            controller = nil
            if selected != nil {
                phase = .disconnected(reason)
            }
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard shouldStayConnected, selected != nil, reconnectAttempts < 5 else { return }
        reconnectAttempts += 1
        let delay = min(2.0 * Double(reconnectAttempts), 8.0)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.shouldStayConnected, self.controller == nil else { return }
            self.connect()
        }
    }

    // MARK: Commands

    func press(_ key: TVKey) {
        Haptics.play(.click)
        send(key, .tap)
    }

    func hold(_ key: TVKey, began: Bool) {
        Haptics.play(began ? .start : .release)
        send(key, began ? .holdBegin : .holdEnd)
    }

    /// Drag-to-level volume. Debounced so a slider doesn't fire per pixel.
    func setVolume(_ level: Int) {
        guard let controller, let current = volume?.level else { return }
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            do {
                try await controller.setVolume(level, current: current)
                volume?.level = level
            } catch {
                reportFailure(error)
            }
        }
    }

    func launch(_ app: TVApp) {
        Haptics.play(.click)
        guard let controller else { return }
        Task {
            do { try await controller.launch(app) } catch { reportFailure(error) }
        }
    }

    // MARK: Text entry

    func sendText(_ text: String) async throws {
        guard let controller else { throw TVControllerError.notConnected }
        try await controller.sendText(text)
    }

    func deleteText(count: Int = 1) async throws {
        guard let controller else { throw TVControllerError.notConnected }
        try await controller.deleteText(count: count)
    }

    func submitText() async throws {
        guard let controller else { throw TVControllerError.notConnected }
        try await controller.submitText()
    }

    func refreshApps() async {
        guard let controller else { return }
        if let list = try? await controller.availableApps() {
            apps = list
        }
    }

    private func send(_ key: TVKey, _ phase: TVKeyPhase) {
        guard let controller, self.phase == .connected else {
            // Keep the tap instead of dropping it; it goes out as soon as we're back.
            if phase != .holdEnd { pendingKey = (key, phase) }
            connect()
            return
        }
        Task {
            do { try await controller.send(key, phase: phase) } catch { reportFailure(error) }
        }
    }

    private func reportFailure(_ error: Error) {
        switch error {
        case TVControllerError.notConnected:
            connect()
        case TVControllerError.unsupportedKey:
            Haptics.play(.failure)
        default:
            phase = .disconnected(ErrorText.describe(error))
        }
    }

    /// Roku has no push channel and is polled; slow that down when the watch battery is low.
    private func tuneForBattery(_ controller: TVController) {
        #if os(watchOS)
        guard let roku = controller as? RokuController else { return }
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        roku.pollInterval = device.batteryLevel >= 0 && device.batteryLevel < 0.2 ? 30 : 10
        #endif
    }

    /// Hands the watch face complication what it shows: TV name, brand, power.
    private func publishComplicationState() {
        #if os(watchOS)
        ComplicationState(tvName: selected?.name, brand: selected?.brand, isOn: isOn, updatedAt: Date()).save()
        #endif
    }
}
