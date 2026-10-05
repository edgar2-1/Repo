import Foundation
import Combine
import GoogleTVRemoteKit

/// Drives one pairing attempt with a TV.
@MainActor
final class PairingSession: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case awaitingCode(tvName: String)
        case verifying
        case paired
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var code: String = ""

    let host: String
    let suggestedName: String

    private var client: PairingClient?
    private var tvName: String

    init(host: String, suggestedName: String) {
        self.host = host
        self.suggestedName = suggestedName
        self.tvName = suggestedName
    }

    var pairedTV: PairedTV { PairedTV(name: tvName, host: host) }

    func start(identity: () throws -> ClientIdentity) async {
        guard state == .idle || isFailed else { return }
        state = .connecting
        code = ""
        do {
            let identity = try identity()
            let client = PairingClient(host: host, identity: identity, clientName: "Apple Watch")
            self.client = client
            let serverName = try await client.start()
            if !serverName.isEmpty { tvName = serverName }
            state = .awaitingCode(tvName: tvName)
        } catch {
            client?.cancel()
            client = nil
            state = .failed(Self.describe(error))
        }
    }

    func submit() async {
        guard case .awaitingCode = state, let client, code.count == 6 else { return }
        state = .verifying
        do {
            try await client.finish(code: code)
            state = .paired
        } catch PairingError.wrongCode {
            // The TV keeps showing the same code; let the user retype it.
            code = ""
            state = .awaitingCode(tvName: tvName)
        } catch {
            client.cancel()
            self.client = nil
            state = .failed(Self.describe(error))
        }
    }

    func cancel() {
        client?.cancel()
        client = nil
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case PairingError.rejected(let status):
            switch status {
            case .badSecret: return "TV rejected the code."
            case .badConfiguration: return "TV rejected the pairing setup."
            default: return "TV reported an error (\(status.rawValue))."
            }
        case PairingError.connectionClosed:
            return "TV closed the connection. Try again."
        case PairingError.serverKeyNotRSA, PairingError.serverCertificateUnavailable:
            return "Couldn't read the TV's certificate."
        case TLSConnectionError.waiting(let detail):
            return "Can't reach the TV (\(detail))."
        default:
            return error.localizedDescription
        }
    }
}
