#if canImport(Network) && !os(Linux)
import Foundation
import Network

public enum SSDPError: Error, Sendable {
    /// Sending to the multicast group was refused. On watchOS/iOS this means
    /// the app lacks the `com.apple.developer.networking.multicast` entitlement.
    case multicastNotPermitted(String)
    case listenerFailed(String)
}

/// Finds Roku, Samsung and LG TVs with an SSDP `M-SEARCH`.
///
/// Replies arrive from each device's unicast address, so a plain "connected"
/// UDP socket would drop them. Instead a UDP listener owns the local port and
/// the search is sent from a connection bound to that same port.
public final class SSDPBrowser: @unchecked Sendable {
    public static func search(timeout: Duration = .seconds(3)) async throws -> [SSDPResponse] {
        let collector = Collector()
        let queue = DispatchQueue(label: "TVRemoteCore.SSDP")

        let listenerParameters = NWParameters.udp
        listenerParameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: listenerParameters)
        listener.newConnectionHandler = { connection in
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.receiveMessage { data, _, _, _ in
                        if let data, let response = SSDPResponse(datagram: data) {
                            collector.add(response)
                        }
                        connection.cancel()
                    }
                }
            }
            connection.start(queue: queue)
        }

        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        once.run { continuation.resume(returning: port) }
                    } else {
                        once.run { continuation.resume(throwing: SSDPError.listenerFailed("no port")) }
                    }
                case .failed(let error):
                    once.run { continuation.resume(throwing: SSDPError.listenerFailed(error.localizedDescription)) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        defer { listener.cancel() }

        let sendParameters = NWParameters.udp
        sendParameters.allowLocalEndpointReuse = true
        sendParameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: port)
        let sender = NWConnection(host: "239.255.255.250", port: 1900, using: sendParameters)
        defer { sender.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OnceFlag()
            sender.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error):
                    once.run { continuation.resume(throwing: SSDPError.multicastNotPermitted(error.localizedDescription)) }
                case .waiting(let error):
                    once.run { continuation.resume(throwing: SSDPError.multicastNotPermitted(error.localizedDescription)) }
                default:
                    break
                }
            }
            sender.start(queue: queue)
        }

        // Send twice; SSDP is lossy and TVs are slow to wake their stacks.
        for _ in 0 ..< 2 {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sender.send(content: SSDPResponse.searchRequest(), completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: SSDPError.multicastNotPermitted(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                })
            }
            try? await Task.sleep(for: .milliseconds(300))
        }

        try? await Task.sleep(for: timeout)
        return collector.responses
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: Set<String> = []
        private(set) var responses: [SSDPResponse] = []

        func add(_ response: SSDPResponse) {
            lock.lock(); defer { lock.unlock() }
            let key = (response.host ?? "") + "|" + response.searchTarget
            guard !seen.contains(key) else { return }
            seen.insert(key)
            responses.append(response)
        }
    }
}

#endif
