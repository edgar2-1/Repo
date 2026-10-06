import Foundation

/// An app the TV can launch.
public struct TVApp: Identifiable, Hashable, Codable, Sendable {
    /// Platform-specific launch target (Google TV app link, Roku channel id,
    /// Samsung app id, LG app id).
    public let id: String
    public let name: String
    /// SF Symbol used when no icon is available.
    public let symbol: String

    public init(id: String, name: String, symbol: String = "app.fill") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

/// State changes reported by a controller.
public enum TVEvent: Sendable, Equatable {
    /// The TV is asking the user to allow this remote; keep waiting.
    case pairingPrompt
    /// Handshake complete; keys can be sent.
    case connected
    case powerChanged(isOn: Bool)
    case volumeChanged(level: Int, max: Int, muted: Bool)
    /// Human-readable name or identifier of the foreground app.
    case currentApp(String)
    /// Connection ended. `reason` is nil for a clean close.
    case disconnected(reason: String?)
}

public enum TVControllerError: Error, Sendable, Equatable {
    case notConnected
    case unsupportedKey(TVKey)
    case timeout
    /// The user declined the pairing prompt on the TV, or the stored credential was revoked.
    case notAuthorized
    case badResponse(String)
    case unreachable(String)
}

extension TVControllerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the TV."
        case .unsupportedKey(let key): return "This TV doesn't support \(key.rawValue)."
        case .timeout: return "The TV didn't answer in time."
        case .notAuthorized: return "The TV didn't allow this remote. Pair again."
        case .badResponse(let detail): return "Unexpected reply from the TV: \(detail)"
        case .unreachable(let detail): return "Can't reach the TV (\(detail))."
        }
    }
}

/// One live session with a TV. Implementations exist per brand.
///
/// Lifecycle: create → `connect()` (may emit `.pairingPrompt` and block until
/// the user answers on the TV) → `send` / `launch` → `disconnect()`.
public protocol TVController: AnyObject, Sendable {
    var brand: TVBrand { get }
    /// Events, including `.connected` and `.disconnected`.
    var events: AsyncStream<TVEvent> { get }
    /// Keys this TV can act on. The UI dims the rest.
    var supportedKeys: Set<TVKey> { get }
    /// Whether `holdBegin`/`holdEnd` are meaningful on this platform.
    var supportsHold: Bool { get }
    /// Brand-specific secret the app must persist and hand back next time
    /// (Samsung token, LG client key). `nil` when nothing is needed.
    var credential: String? { get }

    func connect() async throws
    func disconnect()
    func send(_ key: TVKey, phase: TVKeyPhase) async throws
    /// Apps to show in the launcher. May query the TV; may be static.
    func availableApps() async throws -> [TVApp]
    func launch(_ app: TVApp) async throws
}

public extension TVController {
    func send(_ key: TVKey) async throws {
        try await send(key, phase: .tap)
    }
}
