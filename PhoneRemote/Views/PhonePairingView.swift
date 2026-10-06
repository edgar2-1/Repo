import SwiftUI

/// Google TV pairing on iPhone: type the 6-character code with the keyboard.
struct PhonePairingView: View {
    @EnvironmentObject private var store: RemoteStore
    @StateObject var session: PairingSession
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(spacing: 24) {
            switch session.state {
            case .idle, .connecting:
                ProgressView()
                Text("Contacting \(session.suggestedName)…")
                    .foregroundStyle(.secondary)

            case .awaitingCode(let tvName):
                Image(systemName: "tv").font(.system(size: 48)).foregroundStyle(Color.accentColor)
                Text("Enter the code shown on \(tvName)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                TextField("A1B2C3", text: codeBinding)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                    .padding(.horizontal, 40)
                    .onAppear { codeFocused = true }
                Button("Pair") { Task { await session.submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.code.count != 6)

            case .verifying:
                ProgressView()
                Text("Verifying…").foregroundStyle(.secondary)

            case .paired:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Paired with \(session.savedTV.name)").font(.headline)

            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
                Button("Try again") { Task { await session.start(identity: store.identity) } }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .navigationTitle("Pair Google TV")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(session.state == .verifying)
        .task { await session.start(identity: store.identity) }
        .onDisappear { if session.state != .paired { session.cancel() } }
        .onChange(of: session.state) { newState in
            if newState == .paired {
                Haptics.play(.success)
                Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    store.add(session.savedTV, credential: nil)
                }
            }
        }
    }

    /// Keeps only hex characters, upper-cased, at most six.
    private var codeBinding: Binding<String> {
        Binding(
            get: { session.code },
            set: { newValue in
                let filtered = newValue.uppercased().filter { "0123456789ABCDEF".contains($0) }
                session.code = String(filtered.prefix(6))
                if session.code.count == 6 { Task { await session.submit() } }
            }
        )
    }
}
