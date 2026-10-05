import SwiftUI

@main
struct WatchRemoteApp: App {
    @StateObject private var store = RemoteStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
