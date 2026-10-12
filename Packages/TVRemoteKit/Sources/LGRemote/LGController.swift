import Foundation
import TVRemoteCore

/// Controls an LG webOS TV (2014 and newer) over SSAP.
///
/// First connection: the TV shows an allow/deny prompt. When the user
/// accepts, the TV returns a client key that we hand back next time.
/// Navigation keys travel over a second "pointer input" socket whose URL the
/// TV hands out after registration.
public final class LGController: TVController, @unchecked Sendable {
    public let brand: TVBrand = .lg
    public let events: AsyncStream<TVEvent>
    public let supportsHold = false
    public let supportedKeys: Set<TVKey> = LGProtocol.supportedKeys
    public var credential: String? {
        lock.lock(); defer { lock.unlock() }
        return clientKey
    }

    private let host: String
    private let macAddress: String?
    private let eventContinuation: AsyncStream<TVEvent>.Continuation
    private let lock = NSLock()
    private var clientKey: String?
    private var main: WebSocketClient?
    private var input: WebSocketClient?
    private var readTask: Task<Void, Never>?
    private var connected = false
    private var nextID = 1
    private var pending: [String: CheckedContinuation<LGProtocol.Message, Error>] = [:]
    private var subscriptions: [String: @Sendable (LGProtocol.Message) -> Void] = [:]
    private var registerContinuation: CheckedContinuation<String, Error>?
    private var muted = false
    private var playing = true

    public init(host: String, clientKey: String?, macAddress: String? = nil) {
        var continuation: AsyncStream<TVEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        eventContinuation = continuation
        self.host = host
        self.clientKey = (clientKey ?? "").isEmpty ? nil : clientKey
        self.macAddress = macAddress
    }

    deinit {
        readTask?.cancel()
        main?.close()
        input?.close()
    }

    // MARK: Discovery helper

    /// Opens a socket just long enough to read the model name (no pairing needed).
    public static func identify(host: String) async -> DiscoveredDevice? {
        let controller = LGController(host: host, clientKey: nil)
        defer { controller.disconnect() }
        guard let socket = try? await controller.openMainSocket() else { return nil }
        controller.startReading(socket)
        _ = try? await controller.sendRaw(LGProtocol.helloMessage(), expectID: "hello")
        let info = try? await withTimeout(seconds: 3) { [controller] in
            try await controller.request(LGProtocol.Endpoint.systemInfo, id: "get_sys_info")
        }
        let model = info?.payload["modelName"] as? String
        return DiscoveredDevice(brand: .lg, name: model.map { "LG \($0)" } ?? "LG TV", host: host, detail: model)
    }

    // MARK: TVController

    public func connect() async throws {
        let socket = try await openMainSocket()
        startReading(socket)

        // Newer firmware wants hello + system info before registration.
        _ = try? await withTimeout(seconds: 3) { [self] in try await self.sendRaw(LGProtocol.helloMessage(), expectID: "hello") }
        _ = try? await withTimeout(seconds: 3) { [self] in try await self.request(LGProtocol.Endpoint.systemInfo, id: "get_sys_info") }

        let key = try await register(on: socket)
        setClientKey(key)

        try await openInputSocket()
        connected = true
        eventContinuation.yield(.connected)
        await subscribeToState()
    }

    public func disconnect() {
        readTask?.cancel()
        readTask = nil
        main?.close()
        input?.close()
        main = nil
        input = nil
        failAllPending(TVControllerError.notConnected)
        if connected {
            connected = false
            eventContinuation.yield(.disconnected(reason: nil))
        }
    }

    public func send(_ key: TVKey, phase: TVKeyPhase) async throws {
        guard phase == .tap else { return } // webOS has no press/release over the network.
        if key == .powerOn {
            if let macAddress { await wake(macAddress) }
            return
        }
        guard connected else { throw TVControllerError.notConnected }

        switch key {
        case .power, .powerOff:
            _ = try await request(LGProtocol.Endpoint.powerOff)
        case .mute:
            muted.toggle()
            _ = try await request(LGProtocol.Endpoint.setMute, payload: ["mute": muted])
        case .playPause:
            playing.toggle()
            _ = try await request(playing ? LGProtocol.Endpoint.play : LGProtocol.Endpoint.pause)
        case .input:
            _ = try await request(LGProtocol.Endpoint.showInputPicker)
        default:
            guard let button = LGProtocol.buttonMap[key] else { throw TVControllerError.unsupportedKey(key) }
            guard let input else { throw TVControllerError.notConnected }
            try await input.send(text: LGProtocol.buttonMessage(button))
        }
    }

    public var textEntry: TextEntryFeatures { .all }

    public func sendText(_ text: String) async throws {
        guard connected else { throw TVControllerError.notConnected }
        guard !text.isEmpty else { return }
        _ = try await request(LGProtocol.Endpoint.insertText, payload: ["text": text, "replace": 0])
    }

    public func deleteText(count: Int) async throws {
        guard connected else { throw TVControllerError.notConnected }
        guard count > 0 else { return }
        _ = try await request(LGProtocol.Endpoint.deleteCharacters, payload: ["count": count])
    }

    public func submitText() async throws {
        guard connected else { throw TVControllerError.notConnected }
        _ = try await request(LGProtocol.Endpoint.sendEnter)
    }

    public func availableApps() async throws -> [TVApp] {
        guard connected else { return LGProtocol.apps }
        let reply = try await request(LGProtocol.Endpoint.listApps)
        let apps = reply.launchPoints
        return apps.isEmpty ? LGProtocol.apps : apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func launch(_ app: TVApp) async throws {
        guard connected else { throw TVControllerError.notConnected }
        _ = try await request(LGProtocol.Endpoint.launch, payload: ["id": app.id])
    }

    // MARK: Connection steps

    private func openMainSocket() async throws -> WebSocketClient {
        // Older firmware: plain ws on 3000. Firmware from 2022 on rejects it and wants wss on 3001.
        for secure in [false, true] {
            let socket = WebSocketClient(url: LGProtocol.socketURL(host: host, secure: secure), trustAnyCertificate: true)
            do {
                try await socket.connect()
                main = socket
                return socket
            } catch {
                if secure { throw TVControllerError.unreachable(error.localizedDescription) }
            }
        }
        throw TVControllerError.unreachable("no socket")
    }

    private func register(on socket: WebSocketClient) async throws -> String {
        let message = LGProtocol.registerMessage(clientKey: credential)
        try await socket.send(text: LGProtocol.encode(message))
        return try await withTimeout(seconds: 65, onTimeout: { [weak self] in self?.finishRegister(.failure(TVControllerError.timeout)) }) { [self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                self.lock.lock()
                self.registerContinuation = continuation
                self.lock.unlock()
            }
        }
    }

    private func openInputSocket() async throws {
        let reply = try await request(LGProtocol.Endpoint.inputSocket)
        guard let path = reply.payload["socketPath"] as? String, let url = URL(string: path) else {
            throw TVControllerError.badResponse("no input socket")
        }
        let socket = WebSocketClient(url: url, trustAnyCertificate: true)
        do {
            try await socket.connect()
        } catch {
            throw TVControllerError.unreachable("input socket: \(error.localizedDescription)")
        }
        input = socket
    }

    private func subscribeToState() async {
        _ = try? await subscribe(LGProtocol.Endpoint.getVolume) { [weak self] message in
            guard let self, let volume = message.volume else { return }
            self.muted = volume.muted
            self.eventContinuation.yield(.volumeChanged(level: volume.level, max: 100, muted: volume.muted))
        }
        _ = try? await subscribe(LGProtocol.Endpoint.foregroundApp) { [weak self] message in
            guard let self, let appID = message.payload["appId"] as? String, !appID.isEmpty else { return }
            let name = LGProtocol.apps.first { $0.id == appID }?.name ?? appID
            self.eventContinuation.yield(.currentApp(name))
        }
        _ = try? await subscribe(LGProtocol.Endpoint.powerState) { [weak self] message in
            guard let self, let isOn = message.isOn else { return }
            self.eventContinuation.yield(.powerChanged(isOn: isOn))
        }
    }

    // MARK: Request plumbing

    private func setClientKey(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        clientKey = key
    }

    private func addSubscription(id: String, handler: @escaping @Sendable (LGProtocol.Message) -> Void) {
        lock.lock(); defer { lock.unlock() }
        subscriptions[id] = handler
    }

    private func allocateID() -> String {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        return "\(nextID)"
    }

    @discardableResult
    func request(_ uri: String, payload: [String: Any] = [:], id: String? = nil) async throws -> LGProtocol.Message {
        let id = id ?? allocateID()
        return try await sendRaw(LGProtocol.requestMessage(id: id, uri: uri, payload: payload), expectID: id)
    }

    private func subscribe(_ uri: String, handler: @escaping @Sendable (LGProtocol.Message) -> Void) async throws {
        let id = allocateID()
        addSubscription(id: id, handler: handler)
        let first = try await sendRaw(LGProtocol.requestMessage(id: id, uri: uri, subscribe: true), expectID: id)
        handler(first)
    }

    /// Sends a message and waits for the reply carrying `expectID`.
    func sendRaw(_ message: [String: Any], expectID: String) async throws -> LGProtocol.Message {
        guard let main else { throw TVControllerError.notConnected }
        try await main.send(text: LGProtocol.encode(message))
        return try await withTimeout(seconds: 10, onTimeout: { [weak self] in self?.fail(id: expectID, TVControllerError.timeout) }) { [self] in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LGProtocol.Message, Error>) in
                self.lock.lock()
                self.pending[expectID] = continuation
                self.lock.unlock()
            }
        }
    }

    private func startReading(_ socket: WebSocketClient) {
        readTask?.cancel()
        readTask = Task { [weak self] in
            var reason: String?
            do {
                for try await text in socket.messages {
                    guard let self, let message = LGProtocol.Message(json: text) else { continue }
                    self.dispatch(message)
                }
            } catch {
                reason = error.localizedDescription
            }
            guard let self else { return }
            self.failAllPending(TVControllerError.unreachable(reason ?? "TV closed the connection"))
            self.finishRegister(.failure(TVControllerError.unreachable(reason ?? "TV closed the connection")))
            if self.connected {
                self.connected = false
                self.eventContinuation.yield(.disconnected(reason: reason))
            }
        }
    }

    private func dispatch(_ message: LGProtocol.Message) {
        switch message.type {
        case "registered":
            if let key = message.clientKey { finishRegister(.success(key)) }
        case "response" where message.id == "register_0":
            if message.pairingType == "PROMPT" { eventContinuation.yield(.pairingPrompt) }
        case "error" where message.id == "register_0":
            let text = message.error ?? "rejected"
            let denied = text.contains("403") || text.lowercased().contains("cancel") || text.lowercased().contains("denied")
            finishRegister(.failure(denied ? TVControllerError.notAuthorized : TVControllerError.badResponse(text)))
        default:
            guard let id = message.id else { return }
            lock.lock()
            let continuation = pending.removeValue(forKey: id)
            let subscription = subscriptions[id]
            lock.unlock()
            if let continuation {
                if message.type == "error" {
                    continuation.resume(throwing: TVControllerError.badResponse(message.error ?? "error"))
                } else {
                    continuation.resume(returning: message)
                }
            } else if let subscription {
                subscription(message)
            }
        }
    }

    private func fail(id: String, _ error: Error) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        lock.lock()
        let all = pending
        pending.removeAll()
        lock.unlock()
        all.values.forEach { $0.resume(throwing: error) }
    }

    private func finishRegister(_ result: Result<String, Error>) {
        lock.lock()
        let pending = registerContinuation
        registerContinuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    private func wake(_ mac: String) async {
        #if canImport(Network) && !os(Linux)
        await WakeOnLAN.wake(macAddress: mac, host: host)
        #endif
    }
}
