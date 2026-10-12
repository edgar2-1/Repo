import SwiftUI
import TVRemoteCore

/// Accent colors a TV can be tagged with so the picker is scannable.
enum TVColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }

    var title: String { rawValue.capitalized }

    static func color(for tv: SavedTV?) -> Color {
        tv?.colorName.flatMap(TVColor.init(rawValue:))?.color ?? .accentColor
    }
}
