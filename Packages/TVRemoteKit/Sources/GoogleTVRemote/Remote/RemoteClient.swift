#if canImport(Network) && !os(Linux)
import Foundation

/// Events emitted by `RemoteClient`.
public enum RemoteEvent: Sendable, Equatable {
    /// Handshake complete; keys can be sent.
    case connected
    /// The TV reported whether it is on (`remote_start.started`).
    case powerChanged(isOn: Bool)
    case volumeChanged(VolumeState)
    /// Package name of the app that currently has focus / an input field.
    case currentApp(String)
    /// Connection ended. `error` is nil for a clean close.
    case disconnected(reason: String?)
}

public enum RemoteClientError: Error, Sendable {
    case notConnected
    case handshakeTimeout
    case remoteError
}

/// Client for the Android TV Remote protocol v2 (port 6466).
///
/// The TV drives the handshake: it sends `RemoteConfigure`, we answer with our
/// device info; it sends `RemoteSetActive`, we echo it. After that, key
/// injections are accepted and the TV keeps the link alive with pings.
public final class RemoteClient: @unchecked Sendable {
    public static let defaultPort: UInt16 = 6466

    public let events: AsyncStream<RemoteEvent>

    private let connection: TLSConnection
    private let deviceInfo: RemoteDeviceInfo
    private let eventContinuation: AsyncStream<RemoteEvent>.Continuation
    private let lock = NSLock()
    private var _isReady = false
    private var readTask: Task<Void, Never>?
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var imeCounter: Int32 = 0
    private var fieldCounter: Int32 = 0

    public var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isReady
    }

    public init(
        host: String,
        port: UInt16 = RemoteClient.defaultPort,
        identity: ClientIdentity,
        deviceInfo: RemoteDeviceInfo
    ) {
        var continuation: AsyncStream<RemoteEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        eventContinuation = continuation
        self.deviceInfo = deviceInfo
        self.connection = TLSConnection(host: host, port: port, identity: identity.identity)
    }

    deinit {
        readTask?.cancel()
        connection.cancel()
    }

    // MARK: Lifecycle

    /// Opens the connection and waits (up to `timeout`) for the handshake to finish.
    public func connect(timeout: Duration = .seconds(8)) async throws {
        try await connection.start()
        readTask = Task { [weak self] in await self?.readLoop() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [self] in try await self.waitUntilReady() }
            group.addTask { [self] in
                try await Task.sleep(for: timeout)
                // Resume the waiter with an error so the group can finish, then
                // drop the half-open connection.
                self.fail(RemoteClientError.handshakeTimeout)
                self.connection.cancel()
                throw RemoteClientError.handshakeTimeout
            }
            try await group.next()
            group.cancelAll()
        }
    }

    public func disconnect() {
        readTask?.cancel()
        connection.cancel()
    }

    // MARK: Commands

    public func send(_ key: KeyCode, _ direction: KeyDirection = .short) async throws {
        guard isReady else { throw RemoteClientError.notConnected }
        try await connection.send(RemoteMessage.keyInject(key, direction).encode())
    }

    /// Types text into the focused field via the TV's input method. The TV
    /// must have reported a text field (it does so whenever one gains focus).
    public func sendText(_ text: String) async throws {
        guard isReady else { throw RemoteClientError.notConnected }
        guard !text.isEmpty else { return }
        let counters = imeCounters()
        let message = RemoteMessage.imeBatchEdit(imeCounter: counters.ime, fieldCounter: counters.field,
                                                 edits: [.typing(text)])
        try await connection.send(message.encode())
    }

    /// Opens a deep link / app link on the TV, e.g. `https://www.netflix.com`.
    public func launch(appLink: String) async throws {
        guard isReady else { throw RemoteClientError.notConnected }
        try await connection.send(RemoteMessage.appLinkLaunchRequest(appLink).encode())
    }

    // MARK: Internals

    private func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if _isReady {
                lock.unlock()
                continuation.resume()
                return
            }
            readyWaiters.append(continuation)
            lock.unlock()
        }
    }

    private func imeCounters() -> (ime: Int32, field: Int32) {
        lock.lock(); defer { lock.unlock() }
        return (imeCounter, fieldCounter)
    }

    private func setImeCounters(ime: Int32, field: Int32) {
        lock.lock(); defer { lock.unlock() }
        imeCounter = ime
        fieldCounter = field
    }

    private func markReady() {
        lock.lock()
        _isReady = true
        let waiters = readyWaiters
        readyWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume() }
        eventContinuation.yield(.connected)
    }

    private func fail(_ error: Error) {
        lock.lock()
        _isReady = false
        let waiters = readyWaiters
        readyWaiters.removeAll()
        lock.unlock()
        waiters.forEach { $0.resume(throwing: error) }
    }

    private func readLoop() async {
        var reason: String?
        do {
            for try await bytes in connection.messages {
                let message = try RemoteMessage.decode(bytes)
                try await handle(message)
            }
        } catch {
            reason = error.localizedDescription
            fail(error)
        }
        if reason == nil { fail(RemoteClientError.notConnected) }
        eventContinuation.yield(.disconnected(reason: reason))
        eventContinuation.finish()
    }

    private func handle(_ message: RemoteMessage) async throws {
        switch message {
        case .configure:
            try await connection.send(RemoteMessage.configure(code1: 622, deviceInfo: deviceInfo).encode())
        case .setActive:
            try await connection.send(RemoteMessage.setActive(622).encode())
            markReady()
        case let .pingRequest(val1, _):
            try await connection.send(RemoteMessage.pingResponse(val1: val1).encode())
        case let .start(started):
            eventContinuation.yield(.powerChanged(isOn: started))
        case let .setVolumeLevel(volume):
            eventContinuation.yield(.volumeChanged(volume))
        case let .imeKeyInject(appPackage):
            if !appPackage.isEmpty { eventContinuation.yield(.currentApp(appPackage)) }
        case let .imeBatchEdit(ime, field, _):
            setImeCounters(ime: ime, field: field)
        case .error(let value) where value:
            throw RemoteClientError.remoteError
        default:
            break
        }
    }
}
#endif
