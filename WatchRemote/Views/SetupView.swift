import SwiftUI
import GoogleTVRemoteKit

/// First-run screen: find a TV on the network (or type its address) and pair.
struct SetupView: View {
    @EnvironmentObject private var store: RemoteStore
    @StateObject private var discovery = DiscoveryModel()
    @State private var manualHost = ""
    @State private var resolving: String?
    @State private var resolveError: String?
    @State private var pairingTarget: PairingTarget?

    struct PairingTarget: Identifiable, Hashable {
        var id: String { host }
        let host: String
        let name: String
    }

    var body: some View {
        List {
            Section {
                if discovery.tvs.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for Google TVs…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(discovery.tvs) { tv in
                        Button {
                            resolve(tv)
                        } label: {
                            HStack {
                                Image(systemName: "tv")
                                Text(tv.name).lineLimit(2)
                                Spacer()
                                if resolving == tv.name { ProgressView() }
                            }
                        }
                        .disabled(resolving != nil)
                    }
                }
            } header: {
                Text("Nearby")
            } footer: {
                if let resolveError {
                    Text(resolveError).foregroundStyle(.red)
                } else {
                    Text("Your watch and TV must be on the same Wi‑Fi network.")
                }
            }

            Section("Or enter the TV's IP") {
                TextField("192.168.1.20", text: $manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Pair") {
                    let host = manualHost.trimmingCharacters(in: .whitespaces)
                    pairingTarget = PairingTarget(host: host, name: "Google TV")
                }
                .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let identityError = store.identityError {
                Section("Problem") {
                    Text(identityError).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("TV Remote")
        .navigationDestination(isPresented: isPairing) {
            if let target = pairingTarget {
                PairingView(session: PairingSession(host: target.host, suggestedName: target.name))
            }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    /// `navigationDestination(item:)` needs watchOS 10; this keeps watchOS 9 working.
    private var isPairing: Binding<Bool> {
        Binding(
            get: { pairingTarget != nil },
            set: { if !$0 { pairingTarget = nil } }
        )
    }

    private func resolve(_ tv: DiscoveredTV) {
        resolving = tv.name
        resolveError = nil
        Task {
            defer { resolving = nil }
            do {
                let host = try await TVBrowser.resolveHost(of: tv.endpoint)
                pairingTarget = PairingTarget(host: host, name: tv.name)
            } catch {
                resolveError = "Couldn't resolve \(tv.name): \(error.localizedDescription)"
            }
        }
    }
}

/// Bridges `TVBrowser` callbacks to SwiftUI.
@MainActor
final class DiscoveryModel: ObservableObject {
    @Published private(set) var tvs: [DiscoveredTV] = []
    private var browser: TVBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = TVBrowser { [weak self] tvs in
            Task { @MainActor in self?.tvs = tvs }
        }
        self.browser = browser
        browser.start()
    }

    func stop() {
        browser?.stop()
        browser = nil
    }
}
