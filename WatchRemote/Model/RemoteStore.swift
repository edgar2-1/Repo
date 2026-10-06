import Foundation
import Combine
import TVRemoteCore
import GoogleTVRemote
import WatchKit

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

    private var controller: TVController?
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var shouldStayConnected = false

    private let saved = SavedTVStore()
    private let secrets = SecretStore.shared

    init() {
        tvs = saved.tvs
        selected = tvs.first { $0.id == saved.selectedID } ?? tvs.first
        phase = tvs.isEmpty ? .noTVs : .disconnected(nil)
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
    }

    func select(_ tv: SavedTV) {
        guard tv.id != selected?.id || controller == nil else { return }
        disconnect()
        selected = tv
        saved.selectedID = tv.id
        resetTVState()
        connect()
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
                if let credential = controller.credential {
                    self.secrets.setCredential(credential, for: tv.id)
                }
                self.reconnectAttempts = 0
                self.phase = .connected
                await self.refreshApps()
            } catch {
                self.controller?.disconnect()
                self.controller = nil
                self.phase = .disconnected(Self.describe(error))
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
        case let .powerChanged(isOn):
            self.isOn = isOn
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
        haptic(.click)
        send(key, .tap)
    }

    func hold(_ key: TVKey, began: Bool) {
        if began { haptic(.start) }
        send(key, began ? .holdBegin : .holdEnd)
    }

    func launch(_ app: TVApp) {
        haptic(.click)
        guard let controller else { return }
        Task {
            do { try await controller.launch(app) } catch { reportFailure(error) }
        }
    }

    func refreshApps() async {
        guard let controller else { return }
        if let list = try? await controller.availableApps() {
            apps = list
        }
    }

    private func send(_ key: TVKey, _ phase: TVKeyPhase) {
        guard let controller else {
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
            haptic(.failure)
        default:
            phase = .disconnected(Self.describe(error))
        }
    }

    func haptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? TVControllerError, let text = error.errorDescription {
            return text
        }
        return error.localizedDescription
    }
}
