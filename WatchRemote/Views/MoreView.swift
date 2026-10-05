import SwiftUI
import GoogleTVRemoteKit

/// Power, inputs, app shortcuts and settings.
struct MoreView: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var confirmForget = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    RemoteButton(.power, systemImage: "power", size: 40, tint: .red.opacity(0.75), allowsHold: false)
                    RemoteButton(.tvInput, systemImage: "rectangle.on.rectangle", size: 40, allowsHold: false)
                    RemoteButton(.assist, systemImage: "mic.fill", size: 40, allowsHold: false)
                    RemoteButton(.settings, systemImage: "gearshape.fill", size: 40, allowsHold: false)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } header: {
                Text(powerText)
            }

            Section("Apps") {
                ForEach(AppShortcut.all) { app in
                    Button {
                        store.launch(app.link)
                    } label: {
                        Label(app.name, systemImage: app.symbol)
                    }
                }
            }

            Section("TV") {
                if let tv = store.pairedTV {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tv.name).font(.footnote)
                        Text(tv.host).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Button("Reconnect") { store.disconnect(); store.connect() }
                Button("Forget TV", role: .destructive) { confirmForget = true }
            }
        }
        .confirmationDialog("Forget this TV?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget TV", role: .destructive) { store.forgetTV() }
            Button("Forget & reset remote identity", role: .destructive) { store.resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to pair again. Resetting the identity also makes the TV treat this watch as a new remote.")
        }
    }

    private var powerText: String {
        switch store.isOn {
        case .some(true): return "TV is on"
        case .some(false): return "TV is off"
        case .none: return "Power"
        }
    }
}

/// Deep links the TV's remote service can open directly.
struct AppShortcut: Identifiable {
    let name: String
    let symbol: String
    let link: String
    let packageHint: String?

    var id: String { link }

    static let all: [AppShortcut] = [
        AppShortcut(name: "YouTube", symbol: "play.rectangle.fill", link: "https://www.youtube.com", packageHint: "youtube.tv"),
        AppShortcut(name: "Netflix", symbol: "n.square.fill", link: "https://www.netflix.com/title", packageHint: "netflix"),
        AppShortcut(name: "Prime Video", symbol: "p.square.fill", link: "https://app.primevideo.com", packageHint: "amazon"),
        AppShortcut(name: "Disney+", symbol: "sparkles.tv.fill", link: "https://www.disneyplus.com", packageHint: "disney"),
        AppShortcut(name: "YouTube TV", symbol: "tv.fill", link: "https://tv.youtube.com", packageHint: "youtube.tvunplugged"),
        AppShortcut(name: "Spotify", symbol: "music.note", link: "https://open.spotify.com", packageHint: "spotify"),
        AppShortcut(name: "Plex", symbol: "play.square.stack.fill", link: "https://app.plex.tv", packageHint: "plex"),
    ]
}
