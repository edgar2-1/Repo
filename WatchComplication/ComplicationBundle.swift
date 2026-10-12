import SwiftUI
import WidgetKit
import TVRemoteCore

@main
struct ComplicationBundle: WidgetBundle {
    var body: some Widget {
        RemoteComplication()
    }
}

/// Watch face complication: shows the selected TV and opens the remote on tap.
struct RemoteComplication: Widget {
    static let kind = "TVRemoteComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            ComplicationView(entry: entry)
                .widgetURL(URL(string: "tvremote://remote"))
        }
        .configurationDisplayName("TV Remote")
        .description("Open the remote for your TV from the watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let state: ComplicationState?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), state: ComplicationState(tvName: "Living Room", brand: .googleTV, isOn: true, updatedAt: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), state: context.isPreview ? placeholder(in: context).state : ComplicationState.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The app pushes updates with WidgetCenter when the TV or its power state changes.
        completion(Timeline(entries: [Entry(date: Date(), state: ComplicationState.load())], policy: .never))
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var name: String { entry.state?.tvName ?? "TV Remote" }
    private var symbol: String {
        switch entry.state?.isOn {
        case .some(true): return "tv.fill"
        case .some(false): return "tv"
        case .none: return "tv"
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: symbol).font(.title3)
                }
            case .accessoryCorner:
                Image(systemName: symbol)
                    .font(.title3)
                    .widgetLabel { Text(name) }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: symbol).font(.title2)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TV Remote").font(.headline)
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label(name, systemImage: symbol)
            default:
                Image(systemName: symbol)
            }
        }
        .widgetBackground()
    }

    private var subtitle: String {
        guard let state = entry.state, let tvName = state.tvName else { return "Add a TV" }
        switch state.isOn {
        case .some(true): return "\(tvName) · On"
        case .some(false): return "\(tvName) · Off"
        case .none: return tvName
        }
    }
}

private extension View {
    /// watchOS 10 wants an explicit container background; older versions don't have the API.
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(watchOS 10.0, *) {
            containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}
