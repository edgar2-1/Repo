import SwiftUI
import GoogleTVRemoteKit

/// A remote key. Tap sends a short press; press-and-hold sends the Android
/// long-press pair (START_LONG on hold, END_LONG on release), which is what
/// makes e.g. holding Home open the app switcher or holding a D-pad arrow scroll.
struct RemoteButton<Label: View>: View {
    @EnvironmentObject private var store: RemoteStore

    let key: KeyCode
    var size: CGFloat = 44
    var tint: Color = .gray.opacity(0.3)
    var allowsHold = true
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false
    @State private var holding = false

    var body: some View {
        label()
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .scaleEffect(isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .contentShape(Circle())
            .onTapGesture { store.press(key) }
            .onLongPressGesture(
                minimumDuration: 0.45,
                pressing: { pressing in
                    isPressed = pressing
                    if !pressing, holding {
                        holding = false
                        store.hold(key, .endLong)
                    }
                },
                perform: {
                    guard allowsHold else {
                        store.press(key)
                        return
                    }
                    holding = true
                    store.hold(key, .startLong)
                }
            )
            .accessibilityLabel(Text(String(describing: key)))
    }
}

extension RemoteButton where Label == Image {
    init(_ key: KeyCode, systemImage: String, size: CGFloat = 44, tint: Color = .gray.opacity(0.3), allowsHold: Bool = true) {
        self.init(key: key, size: size, tint: tint, allowsHold: allowsHold) {
            Image(systemName: systemImage)
        }
    }
}

extension RemoteButton where Label == Text {
    init(_ key: KeyCode, title: String, size: CGFloat = 44, tint: Color = .gray.opacity(0.3), allowsHold: Bool = true) {
        self.init(key: key, size: size, tint: tint, allowsHold: allowsHold) {
            Text(title)
        }
    }
}
