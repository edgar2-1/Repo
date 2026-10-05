import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum PairingSecretError: Error, Equatable, Sendable {
    /// The code must be exactly 6 hexadecimal characters.
    case invalidCode
    /// The first byte of the hash did not match the check byte in the code —
    /// the code was typed wrong.
    case checkByteMismatch
}

/// Computes the pairing secret for the Polo protocol.
///
/// Google TV shows a 6-character hex code. The first two characters are a
/// check byte; the last four are a nonce. The secret is
/// `SHA256(clientModulus ‖ clientExponent ‖ serverModulus ‖ serverExponent ‖ nonce)`
/// where every big integer is big-endian with leading zero bytes removed.
public enum PairingSecret {
    public static func compute(
        clientModulus: [UInt8],
        clientExponent: [UInt8],
        serverModulus: [UInt8],
        serverExponent: [UInt8],
        code: String
    ) throws -> [UInt8] {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 6, let codeBytes = hexBytes(normalized) else {
            throw PairingSecretError.invalidCode
        }
        let check = codeBytes[0]
        let nonce = Array(codeBytes[1...])

        var hasher = SHA256()
        hasher.update(data: stripLeadingZeros(clientModulus))
        hasher.update(data: stripLeadingZeros(clientExponent))
        hasher.update(data: stripLeadingZeros(serverModulus))
        hasher.update(data: stripLeadingZeros(serverExponent))
        hasher.update(data: nonce)
        let digest = Array(hasher.finalize())

        guard digest[0] == check else { throw PairingSecretError.checkByteMismatch }
        return digest
    }

    static func stripLeadingZeros(_ bytes: [UInt8]) -> [UInt8] {
        guard let first = bytes.firstIndex(where: { $0 != 0 }) else { return [] }
        return Array(bytes[first...])
    }

    static func hexBytes(_ s: String) -> [UInt8]? {
        let chars = Array(s.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = hexValue(chars[i]), let lo = hexValue(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
}
