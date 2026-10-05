#if canImport(Network) && !os(Linux)
import Foundation
import Security

public enum PairingError: Error, Sendable, Equatable {
    case unexpectedMessage(String)
    case rejected(PairingMessage.Status)
    case connectionClosed
    case serverCertificateUnavailable
    case serverKeyNotRSA
    /// The code was mistyped (check byte did not match).
    case wrongCode
    case notStarted
}

/// Pairs this remote with a Google TV over the Polo protocol (port 6467).
///
/// Usage:
/// 1. `start()` — the TV shows a 6-character code on screen.
/// 2. `finish(code:)` with the code the user typed.
///
/// After success the TV remembers our client certificate and the remote
/// service (port 6466) accepts connections without further prompts.
public final class PairingClient: @unchecked Sendable {
    public static let defaultPort: UInt16 = 6467

    private let identity: ClientIdentity
    private let clientName: String
    private let serviceName: String
    private let connection: TLSConnection
    private var iterator: AsyncThrowingStream<[UInt8], Error>.AsyncIterator
    private var started = false

    public init(
        host: String,
        port: UInt16 = PairingClient.defaultPort,
        identity: ClientIdentity,
        clientName: String,
        serviceName: String = "atvremote"
    ) {
        self.identity = identity
        self.clientName = clientName
        self.serviceName = serviceName
        self.connection = TLSConnection(host: host, port: port, identity: identity.identity)
        self.iterator = connection.messages.makeAsyncIterator()
    }

    /// Connects and negotiates until the TV displays the pairing code.
    /// Returns the TV's advertised name.
    @discardableResult
    public func start() async throws -> String {
        try await connection.start()

        try await send(.request(serviceName: serviceName, clientName: clientName))
        let ack = try await receive()
        guard case let .requestAck(serverName) = ack.body else {
            throw PairingError.unexpectedMessage("expected PairingRequestAck, got \(ack.body)")
        }

        try await send(.option(inputEncodings: [.hex6], outputEncodings: [], preferredRole: .input))
        let option = try await receive()
        guard case .option = option.body else {
            throw PairingError.unexpectedMessage("expected PairingOption, got \(option.body)")
        }

        try await send(.configuration(encoding: .hex6, clientRole: .input))
        let configurationAck = try await receive()
        guard case .configurationAck = configurationAck.body else {
            throw PairingError.unexpectedMessage("expected PairingConfigurationAck, got \(configurationAck.body)")
        }

        started = true
        return serverName
    }

    /// Sends the secret derived from the on-screen code and waits for the TV's acknowledgement.
    public func finish(code: String) async throws {
        guard started else { throw PairingError.notStarted }
        guard let serverCertificate = connection.peerCertificate else {
            throw PairingError.serverCertificateUnavailable
        }
        let serverKey: RSAPublicKey
        do {
            serverKey = try ClientIdentity.extractPublicKey(from: serverCertificate)
        } catch {
            throw PairingError.serverKeyNotRSA
        }

        let secret: [UInt8]
        do {
            secret = try PairingSecret.compute(
                clientModulus: identity.publicKey.modulus,
                clientExponent: identity.publicKey.exponent,
                serverModulus: serverKey.modulus,
                serverExponent: serverKey.exponent,
                code: code
            )
        } catch PairingSecretError.checkByteMismatch {
            throw PairingError.wrongCode
        } catch PairingSecretError.invalidCode {
            throw PairingError.wrongCode
        }

        try await send(.secret(secret))
        let ack = try await receive()
        guard case .secretAck = ack.body else {
            throw PairingError.unexpectedMessage("expected PairingSecretAck, got \(ack.body)")
        }
        connection.cancel()
    }

    public func cancel() {
        connection.cancel()
    }

    // MARK: Helpers

    private func send(_ body: PairingMessage.Body) async throws {
        try await connection.send(PairingMessage(body: body).encode())
    }

    private func receive() async throws -> PairingMessage {
        guard let bytes = try await iterator.next() else { throw PairingError.connectionClosed }
        let message = try PairingMessage.decode(bytes)
        guard message.status == .ok else { throw PairingError.rejected(message.status) }
        return message
    }
}
#endif
