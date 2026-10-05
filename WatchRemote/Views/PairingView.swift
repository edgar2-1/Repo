import SwiftUI

/// Shows pairing progress and collects the 6-character code the TV displays.
struct PairingView: View {
    @EnvironmentObject private var store: RemoteStore
    @StateObject var session: PairingSession

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch session.state {
                case .idle, .connecting:
                    ProgressView()
                    Text("Contacting \(session.suggestedName)…")
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                case .awaitingCode(let tvName):
                    Text("Enter the code shown on \(tvName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    CodeDisplay(code: session.code)
                    HexKeypad(code: $session.code) {
                        Task { await session.submit() }
                    }

                case .verifying:
                    ProgressView()
                    Text("Verifying…").font(.footnote)

                case .paired:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("Paired with \(session.pairedTV.name)")
                        .font(.footnote)
                        .multilineTextAlignment(.center)

                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        Task { await session.start(identity: store.identity) }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Pair")
        .navigationBarBackButtonHidden(session.state == .verifying)
        .task {
            await session.start(identity: store.identity)
        }
        .onDisappear {
            if session.state != .paired { session.cancel() }
        }
        .onChange(of: session.state) { newState in
            if newState == .paired {
                store.haptic(.success)
                // Give the checkmark a beat, then hand over to the remote UI.
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    store.didPair(with: session.pairedTV)
                }
            }
        }
    }
}

private struct CodeDisplay: View {
    let code: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 6, id: \.self) { index in
                let characters = Array(code)
                Text(index < characters.count ? String(characters[index]) : "·")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .frame(width: 22, height: 28)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
            }
        }
    }
}

/// A 0–9 / A–F keypad sized for the watch. Calls `onComplete` once six
/// characters are entered.
struct HexKeypad: View {
    @Binding var code: String
    var onComplete: () -> Void

    private let rows: [[String]] = [
        ["1", "2", "3", "A"],
        ["4", "5", "6", "B"],
        ["7", "8", "9", "C"],
        ["0", "D", "E", "F"],
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Button(key) { tap(key) }
                            .buttonStyle(KeypadButtonStyle())
                            .disabled(code.count >= 6)
                    }
                }
            }
            HStack(spacing: 4) {
                Button {
                    if !code.isEmpty { code.removeLast() }
                } label: {
                    Image(systemName: "delete.left")
                }
                .buttonStyle(KeypadButtonStyle(tint: .red.opacity(0.8)))
                .disabled(code.isEmpty)

                Button {
                    onComplete()
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(KeypadButtonStyle(tint: .accentColor))
                .disabled(code.count != 6)
            }
        }
    }

    private func tap(_ key: String) {
        guard code.count < 6 else { return }
        code.append(key)
        if code.count == 6 { onComplete() }
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    var tint: Color = .gray.opacity(0.35)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(tint))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
