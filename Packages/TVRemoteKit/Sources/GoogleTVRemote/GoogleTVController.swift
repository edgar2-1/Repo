#if canImport(Network) && !os(Linux)
import Foundation
import TVRemoteCore

/// `TVController` adapter over `RemoteClient` for Google TV / Android TV.
///
/// Pairing happens beforehand through `PairingClient`; this controller only
/// drives the paired connection.
public final class GoogleTVController: TVController, @unchecked Sendable {
    public let brand: TVBrand = .googleTV
    public let events: AsyncStream<TVEvent>
    public let supportsHold = true
    public var credential: String? { nil }

    public let supportedKeys: Set<TVKey> = Set(TVKey.allCases.filter { Self.keyMap[$0] != nil })

    private let client: RemoteClient
    private let eventContinuation: AsyncStream<TVEvent>.Continuation
    private var forwardTask: Task<Void, Never>?

    public init(host: String, identity: ClientIdentity, deviceInfo: RemoteDeviceInfo) {
        var continuation: AsyncStream<TVEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation = $0 }
        eventContinuation = continuation
        client = RemoteClient(host: host, identity: identity, deviceInfo: deviceInfo)
    }

    public func connect() async throws {
        forwardTask = Task { [client, eventContinuation] in
            for await event in client.events {
                switch event {
                case .connected:
                    eventContinuation.yield(.connected)
                case let .powerChanged(isOn):
                    eventContinuation.yield(.powerChanged(isOn: isOn))
                case let .volumeChanged(volume):
                    eventContinuation.yield(.volumeChanged(level: Int(volume.level), max: Int(volume.max), muted: volume.muted))
                case let .currentApp(package):
                    eventContinuation.yield(.currentApp(package))
                case let .disconnected(reason):
                    eventContinuation.yield(.disconnected(reason: reason))
                }
            }
        }
        do {
            try await client.connect()
        } catch RemoteClientError.remoteError {
            throw TVControllerError.notAuthorized
        } catch RemoteClientError.handshakeTimeout {
            throw TVControllerError.timeout
        } catch TLSConnectionError.waiting(let detail) {
            throw TVControllerError.unreachable(detail)
        }
    }

    public func disconnect() {
        client.disconnect()
        forwardTask?.cancel()
    }

    public func send(_ key: TVKey, phase: TVKeyPhase) async throws {
        guard let code = Self.keyMap[key] else { throw TVControllerError.unsupportedKey(key) }
        let direction: KeyDirection
        switch phase {
        case .tap: direction = .short
        case .holdBegin: direction = .startLong
        case .holdEnd: direction = .endLong
        }
        do {
            try await client.send(code, direction)
        } catch RemoteClientError.notConnected {
            throw TVControllerError.notConnected
        }
    }

    public var textEntry: TextEntryFeatures { .all }

    public func sendText(_ text: String) async throws {
        do {
            try await client.sendText(text)
        } catch RemoteClientError.notConnected {
            throw TVControllerError.notConnected
        }
    }

    public func deleteText(count: Int) async throws {
        for _ in 0 ..< max(count, 0) {
            do { try await client.send(.del, .short) } catch RemoteClientError.notConnected { throw TVControllerError.notConnected }
        }
    }

    public func submitText() async throws {
        do { try await client.send(.enter, .short) } catch RemoteClientError.notConnected { throw TVControllerError.notConnected }
    }

    public func availableApps() async throws -> [TVApp] { Self.apps }

    public func launch(_ app: TVApp) async throws {
        do {
            try await client.launch(appLink: app.id)
        } catch RemoteClientError.notConnected {
            throw TVControllerError.notConnected
        }
    }

    // MARK: Mapping

    static let keyMap: [TVKey: KeyCode] = [
        .up: .dpadUp, .down: .dpadDown, .left: .dpadLeft, .right: .dpadRight, .select: .dpadCenter,
        .back: .back, .home: .home, .menu: .menu,
        .power: .power, .powerOn: .wakeup, .powerOff: .sleep,
        .volumeUp: .volumeUp, .volumeDown: .volumeDown, .mute: .volumeMute,
        .playPause: .mediaPlayPause, .play: .mediaPlay, .pause: .mediaPause, .stop: .mediaStop,
        .rewind: .mediaRewind, .fastForward: .mediaFastForward, .previous: .mediaPrevious, .next: .mediaNext,
        .info: .info, .guide: .guide, .settings: .settings, .input: .tvInput, .search: .search, .assistant: .assist,
        .channelUp: .channelUp, .channelDown: .channelDown,
    ]

    /// App links the remote service opens directly.
    public static let apps: [TVApp] = [
        TVApp(id: "https://www.youtube.com", name: "YouTube", symbol: "play.rectangle.fill"),
        TVApp(id: "https://www.netflix.com/title", name: "Netflix", symbol: "n.square.fill"),
        TVApp(id: "https://app.primevideo.com", name: "Prime Video", symbol: "p.square.fill"),
        TVApp(id: "https://www.disneyplus.com", name: "Disney+", symbol: "sparkles.tv.fill"),
        TVApp(id: "https://tv.youtube.com", name: "YouTube TV", symbol: "tv.fill"),
        TVApp(id: "https://open.spotify.com", name: "Spotify", symbol: "music.note"),
        TVApp(id: "https://app.plex.tv", name: "Plex", symbol: "play.square.stack.fill"),
    ]
}
#endif
