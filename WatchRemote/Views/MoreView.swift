import SwiftUI
import TVRemoteCore

/// Power, inputs, app shortcuts, TV switching and settings.
struct MoreView: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var tvToForget: SavedTV?
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    RemoteButton(.power, systemImage: "power", size: 40, tint: .red.opacity(0.75), allowsHold: false)
                    RemoteButton(.input, systemImage: "rectangle.on.rectangle", size: 40, allowsHold: false)
                    RemoteButton(.assistant, systemImage: "mic.fill", size: 40, allowsHold: false)
                    RemoteButton(.settings, systemImage: "gearshape.fill", size: 40, allowsHold: false)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } header: {
                Text(powerText)
            }

            Section("Apps") {
                if store.apps.isEmpty {
                    Text(store.phase == .connected ? "No apps reported" : "Connect to see apps")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.apps.prefix(24)) { app in
                        Button {
                            store.launch(app)
                        } label: {
                            Label(app.name, systemImage: app.symbol)
                        }
                    }
                }
            }

            Section("TVs") {
                ForEach(store.tvs) { tv in
                    Button {
                        store.select(tv)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tv.name).font(.footnote).lineLimit(1)
                                Text("\(tv.brand.shortName) · \(tv.host)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if tv.id == store.selected?.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { tvToForget = tv } label: {
                            Label("Forget", systemImage: "trash")
                        }
                    }
                }
                NavigationLink {
                    AddTVView()
                } label: {
                    Label("Add TV", systemImage: "plus.circle")
                }
            }

            Section {
                Button("Reconnect") { store.disconnect(); store.connect() }
                Button("Reset everything", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Swipe a TV left to forget it. Reset also makes a new Google TV pairing identity.")
            }
        }
        .navigationTitle(store.selected?.name ?? "Remote")
        .confirmationDialog("Forget \(tvToForget?.name ?? "this TV")?", isPresented: hasTVToForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                if let tv = tvToForget { store.remove(tv) }
                tvToForget = nil
            }
            Button("Cancel", role: .cancel) { tvToForget = nil }
        }
        .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetEverything() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every TV and its saved pairing.")
        }
    }

    private var hasTVToForget: Binding<Bool> {
        Binding(get: { tvToForget != nil }, set: { if !$0 { tvToForget = nil } })
    }

    private var powerText: String {
        switch store.isOn {
        case .some(true): return "TV is on"
        case .some(false): return "TV is off"
        case .none: return "Power"
        }
    }
}
