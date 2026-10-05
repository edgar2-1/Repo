import Foundation

public enum RSAPublicKeyError: Error, Equatable, Sendable {
    case malformedDER
    case notRSA
}

/// Modulus and public exponent of an RSA key, as big-endian byte strings.
public struct RSAPublicKey: Equatable, Sendable {
    public var modulus: [UInt8]
    public var exponent: [UInt8]

    public init(modulus: [UInt8], exponent: [UInt8]) {
        self.modulus = modulus
        self.exponent = exponent
    }

    /// Parses either a PKCS#1 `RSAPublicKey` (`SEQUENCE { INTEGER n, INTEGER e }`,
    /// which is what `SecKeyCopyExternalRepresentation` returns) or an X.509
    /// `SubjectPublicKeyInfo` wrapping one.
    public init(der: [UInt8]) throws {
        var reader = DERReader(der)
        let outer = try reader.readSequence()
        var seq = DERReader(outer)

        // Peek: PKCS#1 starts with INTEGER; SPKI starts with SEQUENCE (AlgorithmIdentifier).
        guard let firstTag = seq.peekTag() else { throw RSAPublicKeyError.malformedDER }
        if firstTag == 0x30 {
            // SubjectPublicKeyInfo
            let algorithm = try seq.readSequence()
            var alg = DERReader(algorithm)
            let oid = try alg.read(tag: 0x06)
            // 1.2.840.113549.1.1.1 rsaEncryption
            let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
            guard oid == rsaEncryption else { throw RSAPublicKeyError.notRSA }
            let bitString = try seq.read(tag: 0x03)
            guard let unused = bitString.first, unused == 0 else { throw RSAPublicKeyError.malformedDER }
            var inner = DERReader(Array(bitString.dropFirst()))
            let pkcs1 = try inner.readSequence()
            seq = DERReader(pkcs1)
        }

        let n = try seq.read(tag: 0x02)
        let e = try seq.read(tag: 0x02)
        self.modulus = n
        self.exponent = e
    }
}

/// Minimal DER TLV reader (enough for RSA public keys).
struct DERReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    func peekTag() -> UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    mutating func readSequence() throws -> [UInt8] {
        try read(tag: 0x30)
    }

    mutating func read(tag expected: UInt8) throws -> [UInt8] {
        guard index < bytes.count, bytes[index] == expected else { throw RSAPublicKeyError.malformedDER }
        index += 1
        let length = try readLength()
        guard index + length <= bytes.count else { throw RSAPublicKeyError.malformedDER }
        let value = Array(bytes[index ..< index + length])
        index += length
        return value
    }

    private mutating func readLength() throws -> Int {
        guard index < bytes.count else { throw RSAPublicKeyError.malformedDER }
        let first = bytes[index]
        index += 1
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7F)
        guard count > 0, count <= 4, index + count <= bytes.count else { throw RSAPublicKeyError.malformedDER }
        var length = 0
        for _ in 0 ..< count {
            length = length << 8 | Int(bytes[index])
            index += 1
        }
        return length
    }
}
