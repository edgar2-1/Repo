import SwiftUI
import TVRemoteCore

/// First connection to a Roku, Samsung or LG TV. Samsung and LG show an
/// allow/deny prompt on screen; Roku connects immediately.
struct ConnectTVView: View {
    @EnvironmentObject private var store: RemoteStore
    let device: DiscoveredDevice

    private enum Step: Equatable {
        case connecting
        case waitingForTV
        case done
        case failed(String)
    }

    @State private var state: Step = .connecting
    @State private var controller: TVController?
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 10) {
            switch state {
            case .connecting:
                ProgressView()
                Text("Connecting to \(device.name)…")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            case .waitingForTV:
                Image(systemName: "tv.and.hifispeaker.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text("Look at your TV")
                    .font(.headline)
                Text("Choose **Allow** on the TV screen to let this watch control it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ProgressView()
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("Added \(device.name)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Try again") { attempt += 1 }
            }
        }
        .padding(.horizontal, 6)
        .navigationTitle(device.brand.shortName)
        .task(id: attempt) { await run() }
        .onDisappear {
            if state != .done { controller?.disconnect() }
        }
    }

    private func run() async {
        state = .connecting
        let draft = SavedTV(brand: device.brand, name: device.name, host: device.host)
        let controller: TVController
        do {
            controller = try ControllerFactory.make(for: draft, credential: nil, identity: store.identity)
        } catch {
            state = .failed(RemoteStore.describe(error))
            return
        }
        self.controller = controller

        let watcher = Task { @MainActor in
            for await event in controller.events {
                if event == .pairingPrompt { state = .waitingForTV }
            }
        }
        defer { watcher.cancel() }

        do {
            try await controller.connect()
        } catch {
            controller.disconnect()
            state = .failed(RemoteStore.describe(error))
            return
        }

        var tv = draft
        if let identified = await ControllerFactory.identify(brand: device.brand, host: device.host),
           tv.name.hasSuffix(" TV") || tv.name == device.brand.shortName {
            tv.name = identified.name
        }
        tv.macAddress = await ControllerFactory.macAddress(brand: device.brand, host: device.host)
        let credential = controller.credential
        controller.disconnect()

        state = .done
        store.haptic(.success)
        try? await Task.sleep(for: .milliseconds(700))
        store.add(tv, credential: credential)
    }
}
