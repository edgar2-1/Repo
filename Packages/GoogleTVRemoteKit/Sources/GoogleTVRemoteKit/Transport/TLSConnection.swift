#if canImport(Network) && !os(Linux)
import Foundation
import Network
import Security

public enum TLSConnectionError: Error, Sendable {
    case notConnected
    case closed
    case waiting(String)
}

/// A framed TLS connection to a Google TV, authenticated with the client
/// identity. Both the pairing and remote services use this transport.
///
/// Incoming data is delivered as complete protobuf messages via `messages`.
public final class TLSConnection: @unchecked Sendable {
    public let messages: AsyncThrowingStream<[UInt8], Error>

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let peer: PeerCertificateBox
    private let lock = NSLock()
    private var frames = FrameBuffer()
    private let messageContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
    private var finished = false

    /// The TV's leaf certificate, available once the handshake completed.
    public var peerCertificate: SecCertificate? { peer.certificate }

    public init(host: String, port: UInt16, identity: SecIdentity) {
        var continuation: AsyncThrowingStream<[UInt8], Error>.Continuation!
        messages = AsyncThrowingStream { continuation = $0 }
        messageContinuation = continuation

        let queue = DispatchQueue(label: "GoogleTVRemoteKit.TLSConnection")
        let peer = PeerCertificateBox()
        self.queue = queue
        self.peer = peer
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 6466,
            using: Self.makeParameters(identity: identity, peer: peer, queue: queue)
        )
    }

    private static func makeParameters(identity: SecIdentity, peer: PeerCertificateBox, queue: DispatchQueue) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        if let secIdentity = sec_identity_create(identity) {
            sec_protocol_options_set_local_identity(security, secIdentity)
        }
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv12)

        // The TV presents a self-signed certificate. Trust is established by the
        // pairing secret, which binds both public keys, so we accept the chain
        // here and only capture the leaf for the secret computation.
        sec_protocol_options_set_verify_block(security, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
               let leaf = chain.first {
                peer.certificate = leaf
            }
            complete(true)
        }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        return NWParameters(tls: tls, tcp: tcp)
    }

    deinit {
        connection.cancel()
    }

    // MARK: Lifecycle

    /// Opens the connection and completes the TLS handshake.
    public func start() async throws {
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                    self?.receiveLoop()
                case .failed(let error):
                    if !once.run({ continuation.resume(throwing: error) }) {
                        self?.finish(error: error)
                    }
                case .waiting(let error):
                    // No route to the TV (Wi-Fi off, TV asleep, wrong network). Fail
                    // fast rather than hang.
                    once.run { continuation.resume(throwing: TLSConnectionError.waiting(error.localizedDescription)) }
                    self?.connection.cancel()
                case .cancelled:
                    if !once.run({ continuation.resume(throwing: TLSConnectionError.closed) }) {
                        self?.finish(error: nil)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func cancel() {
        connection.cancel()
    }

    // MARK: I/O

    /// Sends one protobuf message with its varint length prefix.
    public func send(_ payload: [UInt8]) async throws {
        let data = Data(FrameBuffer.frame(payload))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.frames.append(data)
                do {
                    while let message = try self.frames.next() {
                        self.messageContinuation.yield(message)
                    }
                } catch {
                    self.finish(error: error)
                    self.connection.cancel()
                    return
                }
            }
            if let error {
                self.finish(error: error)
                return
            }
            if isComplete {
                self.finish(error: nil)
                return
            }
            self.receiveLoop()
        }
    }

    private func finish(error: Error?) {
        lock.lock()
        let alreadyFinished = finished
        finished = true
        lock.unlock()
        guard !alreadyFinished else { return }
        if let error {
            messageContinuation.finish(throwing: error)
        } else {
            messageContinuation.finish()
        }
    }
}

/// Thread-safe holder for the TV's certificate captured during the TLS handshake.
final class PeerCertificateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SecCertificate?

    var certificate: SecCertificate? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// Runs a closure at most once; returns whether this call ran it.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    @discardableResult
    func run(_ body: () -> Void) -> Bool {
        lock.lock()
        if done { lock.unlock(); return false }
        done = true
        lock.unlock()
        body()
        return true
    }
}
#endif
