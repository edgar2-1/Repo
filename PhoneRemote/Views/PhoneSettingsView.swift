import SwiftUI
import TVRemoteCore

/// Manage saved TVs and reset.
struct PhoneSettingsView: View {
    @EnvironmentObject private var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: SavedTV?
    @State private var newName = ""
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                ForEach(store.tvs) { tv in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tv.name)
                            Text("\(tv.brand.displayName) · \(tv.host)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if tv.id == store.selected?.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(tv) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.remove(tv) } label: {
                            Label("Forget", systemImage: "trash")
                        }
                        Button {
                            renaming = tv
                            newName = tv.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                NavigationLink {
                    AddTVView()
                } label: {
                    Label("Add TV", systemImage: "plus.circle")
                }
            } header: {
                Text("TVs")
            } footer: {
                Text("TVs and their pairings sync to your Apple Watch automatically.")
            }

            Section {
                Button("Reconnect") { store.disconnect(); store.connect() }
                Button("Reset everything", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Reset removes every TV and its saved pairing on this phone and the watch, plus this phone's Google TV pairing identity.")
            }

            Section("About") {
                LabeledContent("Supports", value: "Google TV, Roku, Samsung, LG")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Rename TV", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let tv = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                    store.rename(tv, to: newName.trimmingCharacters(in: .whitespaces))
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetEverything() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }
}
