import XCTest
import X509
import SwiftASN1
@testable import GoogleTVRemoteKit

final class ClientCertificateTests: XCTestCase {
    func testGeneratesSelfSignedRSACertificate() throws {
        let generated = try ClientCertificate.generate(commonName: "Test Remote")

        // 2048-bit modulus with the common exponent; this is what feeds the pairing hash.
        XCTAssertEqual(PairingSecret.stripLeadingZeros(generated.publicKey.modulus).count, 256)
        XCTAssertEqual(generated.publicKey.exponent, [0x01, 0x00, 0x01])

        // The DER parses back as a valid self-signed certificate...
        let certificate = try Certificate(derEncoded: generated.certificateDER)
        XCTAssertEqual(certificate.subject, certificate.issuer)
        XCTAssertTrue(try certificate.subject.contains { $0.contains { $0.type == .RDNAttributeType.commonName } })
        XCTAssertTrue(certificate.notValidBefore < Date())
        XCTAssertTrue(certificate.notValidAfter > Date().addingTimeInterval(365 * 24 * 3600))

        // ...whose public key matches the one we extracted.
        let certKey = try RSAPublicKey(der: Array(certificate.publicKey.subjectPublicKeyInfoBytes))
        XCTAssertEqual(PairingSecret.stripLeadingZeros(certKey.modulus),
                       PairingSecret.stripLeadingZeros(generated.publicKey.modulus))

        // The private key is PKCS#1 (SEQUENCE { INTEGER version(0), INTEGER n, ... }).
        XCTAssertEqual(generated.privateKeyDER.prefix(1), [0x30])
        var reader = DERReader(generated.privateKeyDER)
        var seq = DERReader(try reader.readSequence())
        XCTAssertEqual(try seq.read(tag: 0x02), [0x00])
        XCTAssertEqual(PairingSecret.stripLeadingZeros(try seq.read(tag: 0x02)),
                       PairingSecret.stripLeadingZeros(generated.publicKey.modulus))
    }

    func testEachGenerationIsUnique() throws {
        let a = try ClientCertificate.generate()
        let b = try ClientCertificate.generate()
        XCTAssertNotEqual(a.publicKey, b.publicKey)
        XCTAssertNotEqual(a.certificateDER, b.certificateDER)
    }
}
