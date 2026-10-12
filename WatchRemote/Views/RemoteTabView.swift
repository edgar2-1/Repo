import SwiftUI

/// The main remote: swipe between the D-pad, media controls and extras.
struct RemoteTabView: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            DPadView().tag(0)
            MediaView().tag(1)
            NavigationStack { MoreView() }.tag(2)
        }
        .tabViewStyle(.page)
        .overlay(alignment: .top) {
            if selection != 2 { ConnectionBadge() }
        }
    }
}

/// Small status pill: connecting / waiting for TV / error, tap to retry.
struct ConnectionBadge: View {
    @EnvironmentObject private var store: RemoteStore

    var body: some View {
        switch store.phase {
        case .connected, .noTVs:
            EmptyView()
        case .connecting:
            // Taps still work while this shows; they're queued and sent on reconnect.
            pill("Reconnecting…", color: .yellow)
        case .pairingPrompt:
            pill("Allow on your TV", color: .orange)
        case .disconnected(let reason):
            Button { store.connect() } label: {
                pill(reason ?? "Disconnected · tap to retry", color: .red)
            }
            .buttonStyle(.plain)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.85)))
            .foregroundStyle(.black)
            .padding(.top, 2)
    }
}
