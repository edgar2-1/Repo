import SwiftUI
import TVRemoteCore

/// A remote key. Tap sends a press; press-and-hold sends hold begin/end on
/// platforms that support it. Keys the current TV can't do are dimmed.
struct RemoteButton<Label: View>: View {
    @EnvironmentObject private var store: RemoteStore

    let key: TVKey
    var size: CGFloat = 44
    var tint: Color = .gray.opacity(0.3)
    var allowsHold = true
    @ViewBuilder var label: () -> Label

    @State private var isPressed = false
    @State private var holding = false

    private var supported: Bool { store.supportedKeys.contains(key) }
    private var canHold: Bool { allowsHold && store.supportsHold }

    var body: some View {
        label()
            .font(.system(size: size * 0.42, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(tint))
            .scaleEffect(isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .opacity(supported ? 1 : 0.3)
            .contentShape(Circle())
            .onTapGesture {
                guard supported else { Haptics.play(.failure); return }
                store.press(key)
            }
            .onLongPressGesture(
                minimumDuration: 0.45,
                pressing: { pressing in
                    isPressed = pressing
                    if !pressing, holding {
                        holding = false
                        store.hold(key, began: false)
                    }
                },
                perform: {
                    guard supported else { return }
                    guard canHold else {
                        store.press(key)
                        return
                    }
                    holding = true
                    store.hold(key, began: true)
                }
            )
            .accessibilityLabel(Text(key.rawValue))
    }
}

extension RemoteButton where Label == Image {
    init(_ key: TVKey, systemImage: String, size: CGFloat = 44, tint: Color = .gray.opacity(0.3), allowsHold: Bool = true) {
        self.init(key: key, size: size, tint: tint, allowsHold: allowsHold) {
            Image(systemName: systemImage)
        }
    }
}

extension RemoteButton where Label == Text {
    init(_ key: TVKey, title: String, size: CGFloat = 44, tint: Color = .gray.opacity(0.3), allowsHold: Bool = true) {
        self.init(key: key, size: size, tint: tint, allowsHold: allowsHold) {
            Text(title)
        }
    }
}
