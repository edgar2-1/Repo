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

/// What a platform's on-screen text field can be told to do.
public struct TextEntryFeatures: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Type characters into the focused field.
    public static let insert = TextEntryFeatures(rawValue: 1 << 0)
    /// Delete characters before the cursor.
    public static let delete = TextEntryFeatures(rawValue: 1 << 1)
    /// Press Return / submit the field.
    public static let submit = TextEntryFeatures(rawValue: 1 << 2)

    public static let none: TextEntryFeatures = []
    public static let all: TextEntryFeatures = [.insert, .delete, .submit]
}

public enum TVControllerError: Error, Sendable, Equatable {
    case notConnected
    case unsupportedKey(TVKey)
    case unsupportedFeature(String)
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
        case .unsupportedFeature(let name): return "This TV doesn't support \(name)."
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

    /// Text-entry abilities for the TV's focused on-screen field.
    var textEntry: TextEntryFeatures { get }

    func connect() async throws
    func disconnect()
    func send(_ key: TVKey, phase: TVKeyPhase) async throws
    /// Apps to show in the launcher. May query the TV; may be static.
    func availableApps() async throws -> [TVApp]
    func launch(_ app: TVApp) async throws

    /// Types `text` into the focused field on the TV.
    func sendText(_ text: String) async throws
    /// Deletes `count` characters before the cursor.
    func deleteText(count: Int) async throws
    /// Presses Return in the focused field.
    func submitText() async throws

    /// Sets the volume to `level`. `current` is the last level the TV reported,
    /// used by platforms that can only step the volume.
    func setVolume(_ level: Int, current: Int) async throws
}

public extension TVController {
    func send(_ key: TVKey) async throws {
        try await send(key, phase: .tap)
    }

    var textEntry: TextEntryFeatures { .none }

    func sendText(_ text: String) async throws {
        throw TVControllerError.unsupportedFeature("text entry")
    }

    func deleteText(count: Int) async throws {
        throw TVControllerError.unsupportedFeature("deleting text")
    }

    func submitText() async throws {
        throw TVControllerError.unsupportedFeature("submitting text")
    }

    /// Default: step with volume keys. Capped so a stray drag can't blast the room.
    func setVolume(_ level: Int, current: Int) async throws {
        let delta = max(-30, min(30, level - current))
        let key: TVKey = delta > 0 ? .volumeUp : .volumeDown
        for _ in 0 ..< abs(delta) {
            try await send(key, phase: .tap)
            try? await Task.sleep(for: .milliseconds(60))
        }
    }
}
