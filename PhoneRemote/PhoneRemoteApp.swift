import SwiftUI

@main
struct PhoneRemoteApp: App {
    @StateObject private var store = RemoteStore()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(store)
        }
    }
}
