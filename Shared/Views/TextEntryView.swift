import SwiftUI
import TVRemoteCore

/// Type into whatever text field is focused on the TV (search boxes, logins).
///
/// On iPhone the keyboard appears; on the watch the field offers dictation and
/// scribble. Text is sent when you tap Send or press Return.
struct TextEntryView: View {
    @EnvironmentObject private var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var status: String?
    @FocusState private var focused: Bool

    private var features: TextEntryFeatures { store.textEntry }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Type on TV", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit { Task { await send(andSubmit: true) } }
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                #endif

            HStack(spacing: 10) {
                if features.contains(.delete) {
                    Button { Task { await delete() } } label: {
                        Image(systemName: "delete.left")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete one character on the TV")
                }
                Button { Task { await send(andSubmit: false) } } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.isEmpty || !features.contains(.insert))
                if features.contains(.submit) {
                    Button { Task { await send(andSubmit: true) } } label: {
                        Image(systemName: "return")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Send and press Return")
                }
            }

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Select a text field on the TV first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .navigationTitle("Keyboard")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { focused = true }
        #endif
    }

    private func send(andSubmit submit: Bool) async {
        do {
            if !text.isEmpty {
                try await store.sendText(text)
            }
            if submit, features.contains(.submit) {
                try await store.submitText()
            }
            Haptics.play(.click)
            status = text.isEmpty ? "Sent Return." : "Sent \"\(text)\"."
            text = ""
        } catch {
            Haptics.play(.failure)
            status = RemoteStore.describe(error)
        }
    }

    private func delete() async {
        do {
            try await store.deleteText(count: 1)
            Haptics.play(.click)
            status = "Deleted one character."
        } catch {
            Haptics.play(.failure)
            status = RemoteStore.describe(error)
        }
    }
}
