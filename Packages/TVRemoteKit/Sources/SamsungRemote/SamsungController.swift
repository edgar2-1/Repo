import Foundation
import TVRemoteCore

/// Controls a Samsung Tizen TV (2016 and newer) over its remote WebSocket.
///
/// First connection: the TV shows "Allow Apple Watch to connect?". When the
/// user accepts, the TV returns a token that we hand back on later connections.
public final class SamsungController: TVController, @unchecked Sendable {
    public let brand: TVBrand = .samsung
    public let events: AsyncStream<TVEvent>
    public let supportsHold = true
    public let supportedKeys: Set<TVKey> = Set(SamsungProtocol.keyMap.keys)
    public var credential: String? {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    private let host: String
    private let clientName: String
    private let macAddress: String?
    private let http: HTTPClient
    private let eventContinuation: AsyncStream<TVEvent>.Continuation
    private let lock = NSLock()
    private var token: String?
    private var socket: WebSocketClient?
    private var readTask: Task<Void, Never>?
    private var connected = false
    private var connectContinuation: CheckedContinuation<Void, Error>?

    public init(host: String, token: String?, clientName: String = "Apple Watch", macAddress: String? = nil, http: HTTPClient = .insecure) {
        var continuation: AsyncStream<TVEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        eventContinuation = continuation
        self.host = host
        self.token = (token ?? "").isEmpty ? nil : token
        self.clientName = clientName
        self.macAddress = macAddress
        self.http = http
    }

    deinit {
        readTask?.cancel()
        socket?.close()
    }

    // MARK: Discovery helper

    public static func identify(host: String, http: HTTPClient = .standard) async -> DiscoveredDevice? {
        guard let info = await fetchInfo(host: host, http: http) else { return nil }
        return DiscoveredDevice(brand: .samsung, name: info.name, host: host, detail: info.model)
    }

    public static func fetchInfo(host: String, http: HTTPClient = .standard) async -> SamsungProtocol.DeviceInfo? {
        guard let (data, _) = try? await http.get(SamsungProtocol.restURL(host: host)) else { return nil }
        return SamsungProtocol.DeviceInfo(json: data)
    }

    // MARK: TVController

    public func connect() async throws {
        // Newer TVs: TLS + token on 8002. Older (2016–2017): plain 8001, no token.
        do {
            try await open(secure: true)
        } catch TVControllerError.notAuthorized {
            throw TVControllerError.notAuthorized
        } catch TVControllerError.timeout {
            throw TVControllerError.timeout
        } catch {
            try await open(secure: false)
        }
    }

    private func open(secure: Bool) async throws {
        let url = SamsungProtocol.socketURL(host: host, name: clientName, token: credential, secure: secure)
        let socket = WebSocketClient(url: url, trustAnyCertificate: true)
        self.socket = socket
        do {
            try await socket.connect()
        } catch {
            throw TVControllerError.unreachable(error.localizedDescription)
        }

        if secure && credential == nil {
            eventContinuation.yield(.pairingPrompt)
        }

        startReading(socket)

        // The TV's allow/deny prompt times out after ~30 s; give the user a minute.
        try await withTimeout(seconds: 60, onTimeout: { [weak self] in self?.finishConnect(.failure(TVControllerError.timeout)) }) { [self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.lock.lock()
                self.connectContinuation = continuation
                self.lock.unlock()
            }
        }
    }

    public func disconnect() {
        readTask?.cancel()
        readTask = nil
        socket?.close()
        socket = nil
        finishConnect(.failure(TVControllerError.notConnected))
        if connected {
            connected = false
            eventContinuation.yield(.disconnected(reason: nil))
        }
    }

    public func send(_ key: TVKey, phase: TVKeyPhase) async throws {
        if key == .powerOn {
            if let macAddress { await wake(macAddress) }
            return
        }
        guard connected, let socket else { throw TVControllerError.notConnected }
        guard let name = SamsungProtocol.keyMap[key] else { throw TVControllerError.unsupportedKey(key) }
        let command: String
        switch phase {
        case .tap: command = "Click"
        case .holdBegin: command = "Press"
        case .holdEnd: command = "Release"
        }
        try await socket.send(text: SamsungProtocol.encode(SamsungProtocol.keyMessage(name, command: command)))
    }

    public func availableApps() async throws -> [TVApp] { SamsungProtocol.apps }

    public func launch(_ app: TVApp) async throws {
        // The REST endpoint needs no token and works on every Tizen TV.
        do {
            try await http.post(SamsungProtocol.restURL(host: host, path: "applications/\(app.id)"))
        } catch {
            guard connected, let socket else { throw TVControllerError.notConnected }
            try await socket.send(text: SamsungProtocol.encode(SamsungProtocol.launchMessage(appID: app.id)))
        }
    }

    // MARK: Internals

    private func startReading(_ socket: WebSocketClient) {
        readTask?.cancel()
        readTask = Task { [weak self] in
            var reason: String?
            do {
                for try await text in socket.messages {
                    guard let self, let event = SamsungProtocol.Event(json: text) else { continue }
                    switch event.name {
                    case SamsungProtocol.Event.connected:
                        if let token = event.token, !token.isEmpty {
                            self.setToken(token)
                        }
                        self.connected = true
                        self.eventContinuation.yield(.connected)
                        self.finishConnect(.success(()))
                    case SamsungProtocol.Event.unauthorized:
                        self.finishConnect(.failure(TVControllerError.notAuthorized))
                        reason = TVControllerError.notAuthorized.localizedDescription
                        socket.close()
                    case SamsungProtocol.Event.timeout:
                        self.finishConnect(.failure(TVControllerError.timeout))
                    default:
                        break
                    }
                }
            } catch {
                reason = error.localizedDescription
            }
            guard let self else { return }
            self.finishConnect(.failure(TVControllerError.unreachable(reason ?? "TV closed the connection")))
            if self.connected {
                self.connected = false
                self.eventContinuation.yield(.disconnected(reason: reason))
            }
        }
    }

    private func setToken(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        token = value
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        lock.lock()
        let pending = connectContinuation
        connectContinuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    private func wake(_ mac: String) async {
        #if canImport(Network) && !os(Linux)
        await WakeOnLAN.wake(macAddress: mac, host: host)
        #endif
    }
}
