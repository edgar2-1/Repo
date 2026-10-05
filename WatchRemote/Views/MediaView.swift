import SwiftUI
import GoogleTVRemoteKit

/// Playback controls.
struct MediaView: View {
    @EnvironmentObject private var store: RemoteStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                RemoteButton(.mediaRewind, systemImage: "gobackward.10", size: 40)
                RemoteButton(.mediaPlayPause, systemImage: "playpause.fill", size: 52, tint: .accentColor.opacity(0.85), allowsHold: false)
                RemoteButton(.mediaFastForward, systemImage: "goforward.10", size: 40)
            }
            HStack(spacing: 10) {
                RemoteButton(.mediaPrevious, systemImage: "backward.end.fill", size: 36)
                RemoteButton(.mediaStop, systemImage: "stop.fill", size: 36, allowsHold: false)
                RemoteButton(.mediaNext, systemImage: "forward.end.fill", size: 36)
            }
            HStack(spacing: 10) {
                RemoteButton(.volumeDown, systemImage: "speaker.minus.fill", size: 36)
                RemoteButton(.volumeMute, systemImage: "speaker.slash.fill", size: 36, allowsHold: false)
                RemoteButton(.volumeUp, systemImage: "speaker.plus.fill", size: 36)
            }
            if let app = store.currentApp {
                Text(friendlyName(for: app))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 10)
    }

    private func friendlyName(for package: String) -> String {
        if let shortcut = AppShortcut.all.first(where: { shortcut in
            shortcut.packageHint.map { package.contains($0) } ?? false
        }) {
            return shortcut.name
        }
        return package.split(separator: ".").last.map { String($0).capitalized } ?? package
    }
}
