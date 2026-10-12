import SwiftUI
import TVRemoteCore

struct PhoneRootView: View {
    @EnvironmentObject private var store: RemoteStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showAddTV = false

    var body: some View {
        NavigationStack {
            Group {
                if store.tvs.isEmpty {
                    AddTVView()
                } else {
                    PhoneRemoteView()
                        .navigationTitle(store.selected?.name ?? "Remote")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                TVPickerMenu(showAddTV: $showAddTV)
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { showSettings = true } label: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                        .navigationDestination(isPresented: $showAddTV) { AddTVView() }
                        .sheet(isPresented: $showSettings) {
                            NavigationStack { PhoneSettingsView() }
                        }
                }
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active: store.activate()
            case .background: store.disconnect()
            default: break
            }
        }
    }
}

/// Switch between saved TVs or add another.
struct TVPickerMenu: View {
    @EnvironmentObject private var store: RemoteStore
    @Binding var showAddTV: Bool

    var body: some View {
        Menu {
            ForEach(store.tvs) { tv in
                Button {
                    store.select(tv)
                } label: {
                    if tv.id == store.selected?.id {
                        Label("\(tv.name) · \(tv.brand.shortName)", systemImage: "checkmark")
                    } else {
                        Text("\(tv.name) · \(tv.brand.shortName)")
                    }
                }
            }
            Divider()
            Button { showAddTV = true } label: {
                Label("Add TV…", systemImage: "plus")
            }
        } label: {
            Image(systemName: "tv")
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(TVColor.color(for: store.selected))
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: 2)
                }
        }
    }
}
