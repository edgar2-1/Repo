import SwiftUI
import TVRemoteCore

/// Swipe to move, tap to select. Each swipe of `step` points sends one arrow.
struct TrackpadView: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var lastSent: CGSize = .zero
    @State private var sentDuringDrag = false

    private let step: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemGroupedBackground))
            VStack(spacing: 6) {
                Image(systemName: "hand.draw")
                    .font(.title2)
                Text("Swipe to move · Tap to select")
                    .font(.footnote)
            }
            .foregroundStyle(.tertiary)
        }
        .frame(height: 250)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width - lastSent.width
                    let dy = value.translation.height - lastSent.height
                    if abs(dx) >= step, abs(dx) >= abs(dy) {
                        store.press(dx > 0 ? .right : .left)
                        lastSent.width += dx > 0 ? step : -step
                        sentDuringDrag = true
                    } else if abs(dy) >= step {
                        store.press(dy > 0 ? .down : .up)
                        lastSent.height += dy > 0 ? step : -step
                        sentDuringDrag = true
                    }
                }
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    if !sentDuringDrag, distance < 12 {
                        store.press(.select)
                    }
                    lastSent = .zero
                    sentDuringDrag = false
                }
        )
    }
}
