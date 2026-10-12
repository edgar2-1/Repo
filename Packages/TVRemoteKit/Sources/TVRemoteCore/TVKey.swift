import Foundation

/// Brand-neutral remote keys. Each platform module maps these to its own
/// key names; keys a platform cannot express are simply unsupported.
public enum TVKey: String, Codable, CaseIterable, Sendable {
    case up, down, left, right, select
    case back, home, menu, exit
    case power, powerOn, powerOff
    case volumeUp, volumeDown, mute
    case playPause, play, pause, stop, rewind, fastForward, previous, next
    case info, guide, settings, input, search, assistant
    case channelUp, channelDown
    case num0, num1, num2, num3, num4, num5, num6, num7, num8, num9

    public static let digits: [TVKey] = [.num0, .num1, .num2, .num3, .num4, .num5, .num6, .num7, .num8, .num9]

    /// The digit for a number key, or nil.
    public var digit: Int? { Self.digits.firstIndex(of: self) }

    public var isNavigation: Bool {
        switch self {
        case .up, .down, .left, .right, .select, .back, .home: return true
        default: return false
        }
    }
}

/// How a key is delivered.
public enum TVKeyPhase: Sendable, Equatable {
    /// A normal press and release.
    case tap
    /// Finger went down and is being held.
    case holdBegin
    /// Finger lifted after a hold.
    case holdEnd
}
