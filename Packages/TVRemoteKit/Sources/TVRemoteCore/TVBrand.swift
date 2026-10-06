import Foundation

/// TV platforms the remote can talk to.
public enum TVBrand: String, Codable, CaseIterable, Sendable, Identifiable {
    case googleTV
    case roku
    case samsung
    case lg

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .googleTV: return "Google TV / Android TV"
        case .roku: return "Roku"
        case .samsung: return "Samsung"
        case .lg: return "LG"
        }
    }

    public var shortName: String {
        switch self {
        case .googleTV: return "Google TV"
        case .roku: return "Roku"
        case .samsung: return "Samsung"
        case .lg: return "LG"
        }
    }

    /// How the user authorises the remote on this platform.
    public var pairingStyle: PairingStyle {
        switch self {
        case .googleTV: return .code
        case .roku: return .none
        case .samsung, .lg: return .acceptOnTV
        }
    }

    public enum PairingStyle: Sendable {
        /// No pairing needed; connect and go.
        case none
        /// The TV shows a code the user types on the remote.
        case code
        /// The TV shows an allow/deny prompt; the remote waits for the answer.
        case acceptOnTV
    }
}
