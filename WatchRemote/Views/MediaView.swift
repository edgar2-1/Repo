import SwiftUI
import TVRemoteCore

/// Playback controls.
struct MediaView: View {
    @EnvironmentObject private var store: RemoteStore

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                RemoteButton(.rewind, systemImage: "gobackward.10", size: 40)
                // A real Button, so the Double Tap gesture (Series 9 and later) can trigger it.
                Button { store.press(.playPause) } label: {
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.accentColor.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .doubleTapPrimaryAction()
                RemoteButton(.fastForward, systemImage: "goforward.10", size: 40)
            }
            HStack(spacing: 10) {
                RemoteButton(.previous, systemImage: "backward.end.fill", size: 36)
                RemoteButton(.stop, systemImage: "stop.fill", size: 36, allowsHold: false)
                RemoteButton(.next, systemImage: "forward.end.fill", size: 36)
            }
            HStack(spacing: 10) {
                RemoteButton(.volumeDown, systemImage: "speaker.minus.fill", size: 36, repeatsOnHold: true)
                RemoteButton(.mute, systemImage: "speaker.slash.fill", size: 36, allowsHold: false)
                RemoteButton(.volumeUp, systemImage: "speaker.plus.fill", size: 36, repeatsOnHold: true)
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

    /// Google TV reports Android package names; turn `com.netflix.ninja` into "Netflix".
    private func friendlyName(for identifier: String) -> String {
        guard identifier.contains(".") else { return identifier }
        let known: [(String, String)] = [
            ("netflix", "Netflix"), ("youtube.tvunplugged", "YouTube TV"), ("youtube", "YouTube"),
            ("amazon", "Prime Video"), ("disney", "Disney+"), ("spotify", "Spotify"), ("plex", "Plex"),
            ("hulu", "Hulu"), ("hbo", "Max"), ("apple", "Apple TV"),
        ]
        let lower = identifier.lowercased()
        if let match = known.first(where: { lower.contains($0.0) }) { return match.1 }
        return identifier.split(separator: ".").last.map { String($0).capitalized } ?? identifier
    }
}
