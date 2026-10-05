import Foundation
import Combine
import GoogleTVRemoteKit
import WatchKit

/// App-wide state: the paired TV, the live connection and what the TV tells us.
@MainActor
final class RemoteStore: ObservableObject {
    enum Phase: Equatable {
        case unpaired
        case connecting
        case connected
        case disconnected(String?)
    }

    static let deviceInfo = RemoteDeviceInfo(
        model: "Apple Watch",
        vendor: "Apple",
        packageName: "com.googletvwatchremote",
        appVersion: "1.0"
    )

    @Published private(set) var pairedTV: PairedTV?
    @Published private(set) var phase: Phase = .unpaired
    @Published private(set) var volume: VolumeState?
    @Published private(set) var isOn: Bool?
    @Published private(set) var currentApp: String?
    @Published var identityError: String?

    private var client: RemoteClient?
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var shouldStayConnected = false

    private let defaults = UserDefaults.standard
    private static let pairedTVKey = "pairedTV"

    init() {
        if let data = defaults.data(forKey: Self.pairedTVKey),
           let tv = try? JSONDecoder().decode(PairedTV.self, from: data) {
            pairedTV = tv
            phase = .disconnected(nil)
        }
    }

    // MARK: Identity

    /// The persistent client certificate. Created on first use.
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

    // MARK: Pairing bookkeeping

    func didPair(with tv: PairedTV) {
        pairedTV = tv
        if let data = try? JSONEncoder().encode(tv) {
            defaults.set(data, forKey: Self.pairedTVKey)
        }
        connect()
    }

    func forgetTV() {
        disconnect()
        pairedTV = nil
        defaults.removeObject(forKey: Self.pairedTVKey)
        phase = .unpaired
        volume = nil
        isOn = nil
        currentApp = nil
    }

    /// Forgets the TV *and* generates a fresh client certificate next time.
    func resetEverything() {
        forgetTV()
        ClientIdentity.reset()
    }

    // MARK: Connection lifecycle

    func connect() {
        guard let tv = pairedTV else { return }
        shouldStayConnected = true
        guard connectTask == nil, phase != .connected else { return }
        phase = .connecting

        connectTask = Task { [weak self] in
            guard let self else { return }
            defer { self.connectTask = nil }
            do {
                let identity = try self.identity()
                let client = RemoteClient(host: tv.host, identity: identity, deviceInfo: Self.deviceInfo)
                self.client = client
                self.eventTask?.cancel()
                self.eventTask = Task { [weak self] in
                    for await event in client.events {
                        await self?.handle(event)
                    }
                }
                try await client.connect()
                self.reconnectAttempts = 0
            } catch {
                self.client?.disconnect()
                self.client = nil
                self.phase = .disconnected(Self.describe(error))
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
        client?.disconnect()
        client = nil
        if pairedTV != nil, phase == .connected || phase == .connecting {
            phase = .disconnected(nil)
        }
    }

    private func handle(_ event: RemoteEvent) {
        switch event {
        case .connected:
            phase = .connected
        case let .powerChanged(isOn):
            self.isOn = isOn
        case let .volumeChanged(volume):
            self.volume = volume
        case let .currentApp(package):
            currentApp = package
        case let .disconnected(reason):
            client = nil
            if pairedTV != nil {
                phase = .disconnected(reason)
            }
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard shouldStayConnected, pairedTV != nil, reconnectAttempts < 5 else { return }
        reconnectAttempts += 1
        let delay = min(2.0 * Double(reconnectAttempts), 8.0)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.shouldStayConnected, self.client == nil else { return }
            self.connect()
        }
    }

    // MARK: Commands

    func press(_ key: KeyCode) {
        haptic(.click)
        send(key, .short)
    }

    func hold(_ key: KeyCode, _ direction: KeyDirection) {
        if direction == .startLong { haptic(.start) }
        send(key, direction)
    }

    func launch(_ appLink: String) {
        haptic(.click)
        guard let client else { return }
        Task {
            do { try await client.launch(appLink: appLink) } catch { reportSendFailure(error) }
        }
    }

    private func send(_ key: KeyCode, _ direction: KeyDirection) {
        guard let client else {
            connect()
            return
        }
        Task {
            do { try await client.send(key, direction) } catch { reportSendFailure(error) }
        }
    }

    private func reportSendFailure(_ error: Error) {
        if case RemoteClientError.notConnected = error {
            connect()
        } else {
            phase = .disconnected(Self.describe(error))
        }
    }

    func haptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case RemoteClientError.handshakeTimeout:
            return "TV didn't answer. Is it paired?"
        case RemoteClientError.remoteError:
            return "TV rejected the remote. Pair again."
        case TLSConnectionError.waiting(let detail):
            return "No route to TV (\(detail))"
        default:
            return error.localizedDescription
        }
    }
}
