import SwiftUI
import GoogleTVRemoteKit

/// Navigation pad. The Digital Crown adjusts volume.
struct DPadView: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var crown: Double = 0
    @State private var lastCrownStep: Int = 0

    private let arrow: CGFloat = 40
    private let center: CGFloat = 46

    var body: some View {
        VStack(spacing: 6) {
            RemoteButton(.dpadUp, systemImage: "chevron.up", size: arrow)
            HStack(spacing: 10) {
                RemoteButton(.dpadLeft, systemImage: "chevron.left", size: arrow)
                RemoteButton(key: .dpadCenter, size: center, tint: .accentColor.opacity(0.85)) {
                    Text("OK")
                }
                RemoteButton(.dpadRight, systemImage: "chevron.right", size: arrow)
            }
            RemoteButton(.dpadDown, systemImage: "chevron.down", size: arrow)

            HStack(spacing: 18) {
                RemoteButton(.back, systemImage: "arrow.uturn.backward", size: 36)
                RemoteButton(.home, systemImage: "house.fill", size: 36)
            }
            .padding(.top, 2)
        }
        .padding(.top, 10)
        .focusable(true)
        .digitalCrownRotation(
            $crown,
            from: -10_000,
            through: 10_000,
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { newValue in
            let step = Int(newValue.rounded())
            guard step != lastCrownStep else { return }
            let direction: KeyCode = step > lastCrownStep ? .volumeUp : .volumeDown
            lastCrownStep = step
            store.press(direction)
        }
        .overlay(alignment: .bottom) {
            if let volume = store.volume, volume.max > 0 {
                VolumeStrip(volume: volume)
            }
        }
    }
}

private struct VolumeStrip: View {
    let volume: VolumeState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 9))
            ProgressView(value: Double(volume.level), total: Double(max(volume.max, 1)))
                .tint(volume.muted ? .gray : .accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }
}
