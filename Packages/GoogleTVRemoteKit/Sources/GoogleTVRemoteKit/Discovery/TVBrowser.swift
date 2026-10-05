#if canImport(Network) && !os(Linux)
import Foundation
import Network

/// A Google TV / Android TV found on the local network.
public struct DiscoveredTV: Identifiable, Hashable, @unchecked Sendable {
    public var id: String { name }
    public let name: String
    public let endpoint: NWEndpoint

    public static func == (lhs: DiscoveredTV, rhs: DiscoveredTV) -> Bool { lhs.name == rhs.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

public enum DiscoveryError: Error, Sendable {
    case unresolvable
}

/// Browses Bonjour for the Android TV Remote v2 service and resolves a
/// chosen TV to an IP address.
public final class TVBrowser: @unchecked Sendable {
    public static let serviceType = "_androidtvremote2._tcp"

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "GoogleTVRemoteKit.TVBrowser")
    private let onUpdate: @Sendable ([DiscoveredTV]) -> Void

    public init(onUpdate: @escaping @Sendable ([DiscoveredTV]) -> Void) {
        self.onUpdate = onUpdate
    }

    public func start() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [onUpdate] results, _ in
            let tvs = results.compactMap { result -> DiscoveredTV? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredTV(name: name, endpoint: result.endpoint)
            }
            onUpdate(tvs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                // Restart on transient failure.
                self?.queue.asyncAfter(deadline: .now() + 1) { self?.start() }
            }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Resolves a Bonjour service endpoint to a host string by opening a
    /// throw-away TCP connection and reading the remote address.
    ///
    /// The remote service advertises port 6466, but pairing uses 6467, which
    /// is why we need the bare host.
    public static func resolveHost(of endpoint: NWEndpoint) async throws -> String {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let once = Once()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint {
                        once.run { continuation.resume(returning: hostString(host)) }
                    } else {
                        once.run { continuation.resume(throwing: DiscoveryError.unresolvable) }
                    }
                    connection.cancel()
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                    connection.cancel()
                case .waiting(let error):
                    once.run { continuation.resume(throwing: error) }
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "GoogleTVRemoteKit.resolve"))
        }
    }

    static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            return "\(address)"
        case .ipv6(let address):
            let base = "\(address)"
            if let interface = address.interface, !base.contains("%") {
                return "\(base)%\(interface.name)"
            }
            return base
        case .name(let name, _):
            return name
        @unknown default:
            return "\(host)"
        }
    }
}
#endif
