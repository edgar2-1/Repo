import Foundation
import Combine
import TVRemoteCore
import GoogleTVRemote

/// Finds TVs of every supported brand.
///
/// Google TVs advertise over Bonjour, which watchOS allows freely. Roku,
/// Samsung and LG use SSDP multicast, which needs an entitlement most
/// developer builds don't have, so a TCP subnet scan is offered as a fallback.
@MainActor
final class DiscoveryModel: ObservableObject {
    @Published private(set) var devices: [DiscoveredDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: Double = 0
    @Published private(set) var hint: String?

    private var bonjour: TVBrowser?
    private var ssdpTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var resolving: Set<String> = []

    func start() {
        guard bonjour == nil else { return }
        let browser = TVBrowser { [weak self] tvs in
            Task { @MainActor in self?.handleBonjour(tvs) }
        }
        bonjour = browser
        browser.start()
        runSSDP()
    }

    func stop() {
        bonjour?.stop()
        bonjour = nil
        ssdpTask?.cancel()
        scanTask?.cancel()
        isScanning = false
    }

    /// Probes every address on the local /24 for Roku, Samsung and LG ports.
    func scanSubnet() {
        guard !isScanning else { return }
        isScanning = true
        scanProgress = 0
        hint = nil
        scanTask = Task { [weak self] in
            let open = await SubnetScanner.scan { progress in
                Task { @MainActor in self?.scanProgress = progress }
            }
            guard let self else { return }
            var found = 0
            for port in open {
                let device = await ControllerFactory.identify(brand: port.brand, host: port.host)
                    ?? DiscoveredDevice(brand: port.brand, name: "\(port.brand.shortName) TV", host: port.host)
                self.add(device)
                found += 1
            }
            self.isScanning = false
            if found == 0 && self.devices.isEmpty {
                self.hint = "Nothing found. Make sure the watch is on the same Wi‑Fi as the TV, or enter the IP below."
            }
        }
    }

    // MARK: Internals

    private func runSSDP() {
        ssdpTask?.cancel()
        ssdpTask = Task { [weak self] in
            do {
                let responses = try await SSDPBrowser.search(timeout: .seconds(3))
                for response in responses {
                    guard let brand = response.brand, let host = response.host else { continue }
                    let device = await ControllerFactory.identify(brand: brand, host: host)
                        ?? DiscoveredDevice(brand: brand, name: "\(brand.shortName) TV", host: host)
                    self?.add(device)
                }
            } catch {
                // Multicast refused (no entitlement) or no network; the scan button covers this.
            }
        }
    }

    private func handleBonjour(_ tvs: [DiscoveredTV]) {
        for tv in tvs where !resolving.contains(tv.name) {
            resolving.insert(tv.name)
            Task { [weak self] in
                if let host = try? await TVBrowser.resolveHost(of: tv.endpoint) {
                    self?.add(DiscoveredDevice(brand: .googleTV, name: tv.name, host: host))
                }
                self?.resolving.remove(tv.name)
            }
        }
    }

    private func add(_ device: DiscoveredDevice) {
        if let index = devices.firstIndex(of: device) {
            devices[index] = device
        } else {
            devices.append(device)
            devices.sort { ($0.brand.rawValue, $0.name) < ($1.brand.rawValue, $1.name) }
        }
    }
}
