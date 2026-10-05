import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: RemoteStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.pairedTV == nil {
                NavigationStack {
                    SetupView()
                }
            } else {
                RemoteTabView()
            }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                store.connect()
            case .background:
                // watchOS tears sockets down in the background anyway; close cleanly.
                store.disconnect()
            default:
                break
            }
        }
    }
}
