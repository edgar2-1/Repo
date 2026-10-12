import SwiftUI
import TVRemoteCore

/// Digits for channel entry on TVs with a tuner, plus Enter.
struct NumberPadView: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var typed = ""

    private let rows: [[TVKey]] = [
        [.num1, .num2, .num3],
        [.num4, .num5, .num6],
        [.num7, .num8, .num9],
    ]

    #if os(watchOS)
    private let size: CGFloat = 40
    private let spacing: CGFloat = 6
    #else
    private let size: CGFloat = 72
    private let spacing: CGFloat = 14
    #endif

    var body: some View {
        VStack(spacing: spacing) {
            Text(typed.isEmpty ? "Channel" : typed)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(typed.isEmpty ? .secondary : .primary)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { key in
                        digitButton(key)
                    }
                }
            }
            HStack(spacing: spacing) {
                RemoteButton(.channelDown, systemImage: "chevron.down", size: size, allowsHold: false)
                digitButton(.num0)
                RemoteButton(.channelUp, systemImage: "chevron.up", size: size, allowsHold: false)
            }
            HStack(spacing: spacing) {
                Button {
                    typed = ""
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: size, height: size)
                        .background(Circle().fill(Color.gray.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(typed.isEmpty)
                RemoteButton(key: .select, size: size, tint: .accentColor.opacity(0.85), allowsHold: false) {
                    Text("Go")
                }
            }
            if !store.supportedKeys.contains(.num1) {
                Text("This TV has no number keys.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Numbers")
    }

    private func digitButton(_ key: TVKey) -> some View {
        RemoteButton(key: key, size: size, allowsHold: false) {
            Text("\(key.digit ?? 0)")
        }
        .simultaneousGesture(TapGesture().onEnded {
            if store.supportedKeys.contains(key), let digit = key.digit, typed.count < 4 {
                typed += "\(digit)"
            }
        })
    }
}
