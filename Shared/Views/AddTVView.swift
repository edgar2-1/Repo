import SwiftUI
import TVRemoteCore

/// Find a TV on the network (or type its address) and add it.
struct AddTVView: View {
    @EnvironmentObject private var store: RemoteStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = DiscoveryModel()
    @State private var manualHost = ""
    @State private var manualBrand: TVBrand = .roku
    @State private var target: DiscoveredDevice?

    var body: some View {
        List {
            Section {
                if discovery.devices.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for TVs…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(discovery.devices) { device in
                        Button {
                            target = device
                        } label: {
                            HStack {
                                Image(systemName: symbol(for: device.brand))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(device.name).lineLimit(2)
                                    Text(device.brand.shortName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Nearby")
            } footer: {
                if let hint = discovery.hint {
                    Text(hint)
                } else {
                    Text("Google TVs appear automatically. Tap Scan for Roku, Samsung and LG.")
                }
            }

            Section {
                if discovery.isScanning {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scanning network…").font(.footnote)
                        ProgressView(value: discovery.scanProgress)
                    }
                } else {
                    Button {
                        discovery.scanSubnet()
                    } label: {
                        Label("Scan for Roku, Samsung, LG", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }

            Section("Or enter the TV's IP") {
                Picker("Brand", selection: $manualBrand) {
                    ForEach(TVBrand.allCases) { brand in
                        Text(brand.shortName).tag(brand)
                    }
                }
                TextField("192.168.1.20", text: $manualHost)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    let host = manualHost.trimmingCharacters(in: .whitespaces)
                    target = DiscoveredDevice(brand: manualBrand, name: "\(manualBrand.shortName) TV", host: host)
                }
                .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let identityError = store.identityError {
                Section("Problem") {
                    Text(identityError).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add TV")
        .navigationDestination(isPresented: hasTarget) {
            if let target {
                switch target.brand {
                case .googleTV:
                    #if os(watchOS)
                    PairingView(session: PairingSession(host: target.host, suggestedName: target.name))
                    #else
                    PhonePairingView(session: PairingSession(host: target.host, suggestedName: target.name))
                    #endif
                case .roku, .samsung, .lg:
                    ConnectTVView(device: target)
                }
            }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .onChange(of: store.tvs.count) { _ in
            // A TV was added from a child screen; return to the remote.
            target = nil
            dismiss()
        }
    }

    private var hasTarget: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    private func symbol(for brand: TVBrand) -> String {
        switch brand {
        case .googleTV: return "tv"
        case .roku: return "tv.and.mediabox"
        case .samsung: return "tv.inset.filled"
        case .lg: return "tv.fill"
        }
    }
}
