#if canImport(Network) && !os(Linux)
import Foundation
import Network

/// A TCP port that answered during a subnet scan.
public struct OpenPort: Hashable, Sendable {
    public let host: String
    public let port: UInt16
    public let brand: TVBrand
}

/// Fallback discovery that needs no multicast: tries the well-known remote
/// ports of each brand on every address in the local /24.
public final class SubnetScanner: @unchecked Sendable {
    public static let defaultProbes: [(brand: TVBrand, port: UInt16)] = [
        (.roku, 8060),
        (.samsung, 8001),
        (.lg, 3000),
        (.lg, 3001),
    ]

    /// Scans the local subnet. `progress` is called with 0…1 on arbitrary threads.
    public static func scan(
        probes: [(brand: TVBrand, port: UInt16)] = defaultProbes,
        concurrency: Int = 48,
        timeoutSeconds: Int = 2,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> [OpenPort] {
        guard let interface = LocalNetwork.primaryInterface() else { return [] }
        let hosts = interface.scanTargets
        var jobs: [(String, TVBrand, UInt16)] = []
        for host in hosts {
            for probe in probes { jobs.append((host, probe.brand, probe.port)) }
        }
        guard !jobs.isEmpty else { return [] }

        let total = Double(jobs.count)
        let counter = Counter()
        var results: [OpenPort] = []

        await withTaskGroup(of: OpenPort?.self) { group in
            var index = 0
            func enqueue() {
                guard index < jobs.count else { return }
                let (host, brand, port) = jobs[index]
                index += 1
                group.addTask {
                    let open = await probe(host: host, port: port, timeoutSeconds: timeoutSeconds)
                    progress?(Double(counter.increment()) / total)
                    return open ? OpenPort(host: host, port: port, brand: brand) : nil
                }
            }
            for _ in 0 ..< min(concurrency, jobs.count) { enqueue() }
            for await result in group {
                if let result { results.append(result) }
                enqueue()
            }
        }

        // One entry per (host, brand); LG may answer on both ports.
        var seen: Set<String> = []
        return results.filter { seen.insert("\($0.host)|\($0.brand.rawValue)").inserted }
            .sorted { ($0.brand.rawValue, $0.host) < ($1.brand.rawValue, $1.host) }
    }

    /// Returns `true` when a TCP connection to `host:port` succeeds.
    public static func probe(host: String, port: UInt16, timeoutSeconds: Int = 2) async -> Bool {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = timeoutSeconds
        let parameters = NWParameters(tls: nil, tcp: tcp)
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let once = OnceFlag()
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume(returning: true) }
                    connection.cancel()
                case .failed, .waiting:
                    once.run { continuation.resume(returning: false) }
                    connection.cancel()
                case .cancelled:
                    once.run { continuation.resume(returning: false) }
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .utility))
        }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }
}
#endif
