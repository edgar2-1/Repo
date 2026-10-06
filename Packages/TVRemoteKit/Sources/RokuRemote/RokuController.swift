import Foundation
import TVRemoteCore

/// Controls a Roku player or Roku TV over ECP. No pairing is required.
public final class RokuController: TVController, @unchecked Sendable {
    public let brand: TVBrand = .roku
    public let events: AsyncStream<TVEvent>
    public let supportsHold = true
    public var credential: String? { nil }

    public var supportedKeys: Set<TVKey> {
        let all = Set(RokuECP.keyMap.keys)
        return (info?.isTV ?? true) ? all : all.subtracting(RokuECP.tvOnlyKeys)
    }

    public private(set) var info: RokuDeviceInfo?

    private let host: String
    private let http: HTTPClient
    private let eventContinuation: AsyncStream<TVEvent>.Continuation
    private var pollTask: Task<Void, Never>?
    private var connected = false

    public init(host: String, http: HTTPClient = .standard) {
        var continuation: AsyncStream<TVEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        eventContinuation = continuation
        self.host = host
        self.http = http
    }

    deinit { pollTask?.cancel() }

    // MARK: Discovery helper

    /// Fetches device info to confirm a host is a Roku and learn its name.
    public static func identify(host: String, http: HTTPClient = .standard) async -> DiscoveredDevice? {
        guard let info = try? await fetchInfo(host: host, http: http) else { return nil }
        return DiscoveredDevice(brand: .roku, name: info.name, host: host, detail: info.model)
    }

    static func fetchInfo(host: String, http: HTTPClient) async throws -> RokuDeviceInfo {
        let (data, _) = try await http.get(RokuECP.baseURL(host: host).appendingPathComponent("query/device-info"))
        guard let info = RokuDeviceInfo(xml: data) else {
            throw TVControllerError.badResponse("device-info")
        }
        return info
    }

    // MARK: TVController

    public func connect() async throws {
        do {
            let info = try await Self.fetchInfo(host: host, http: http)
            self.info = info
            connected = true
            eventContinuation.yield(.connected)
            eventContinuation.yield(.powerChanged(isOn: info.isOn))
            startPolling()
        } catch let error as TVControllerError {
            throw error
        } catch {
            throw TVControllerError.unreachable(error.localizedDescription)
        }
    }

    public func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        if connected {
            connected = false
            eventContinuation.yield(.disconnected(reason: nil))
        }
    }

    public func send(_ key: TVKey, phase: TVKeyPhase) async throws {
        guard connected else { throw TVControllerError.notConnected }
        guard let name = RokuECP.keyMap[key] else { throw TVControllerError.unsupportedKey(key) }
        let action: String
        switch phase {
        case .tap: action = "keypress"
        case .holdBegin: action = "keydown"
        case .holdEnd: action = "keyup"
        }
        try await post(RokuECP.keyURL(host: host, action: action, key: name))
    }

    public func availableApps() async throws -> [TVApp] {
        let (data, _) = try await http.get(RokuECP.baseURL(host: host).appendingPathComponent("query/apps"))
        return RokuAppList.parse(data)
    }

    public func launch(_ app: TVApp) async throws {
        guard connected else { throw TVControllerError.notConnected }
        try await post(RokuECP.baseURL(host: host).appendingPathComponent("launch").appendingPathComponent(app.id))
    }

    // MARK: Internals

    private func post(_ url: URL) async throws {
        do {
            try await http.post(url)
        } catch {
            throw TVControllerError.unreachable(error.localizedDescription)
        }
    }

    /// ECP has no push channel; refresh power state and the foreground app periodically.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.connected else { return }
                if let info = try? await Self.fetchInfo(host: self.host, http: self.http) {
                    if info.isOn != self.info?.isOn {
                        self.eventContinuation.yield(.powerChanged(isOn: info.isOn))
                    }
                    self.info = info
                }
                if let (data, _) = try? await self.http.get(RokuECP.baseURL(host: self.host).appendingPathComponent("query/active-app")),
                   let app = RokuAppList.parseActiveApp(data) {
                    self.eventContinuation.yield(.currentApp(app))
                }
            }
        }
    }
}
