import XCTest
@testable import GoogleTVRemote

final class PairingSecretTests: XCTestCase {
    // Reference vector computed independently with Python's hashlib:
    //   sha256(strip(cm) + strip(ce) + strip(sm) + strip(se) + bytes.fromhex("BEEF"))
    let clientModulus: [UInt8] = [0x00, 0xC1, 0x02, 0x7F]
    let clientExponent: [UInt8] = [0x01, 0x00, 0x01]
    let serverModulus: [UInt8] = [0xD5, 0x00, 0x33]
    let serverExponent: [UInt8] = [0x00, 0x01, 0x00, 0x01]
    let expectedDigest = "87ab06ceb3bc51da6b91814d6b01e14ba7344761cafedd44b7e1f7d653d6cde5"

    func testMatchesReferenceImplementation() throws {
        let secret = try PairingSecret.compute(
            clientModulus: clientModulus, clientExponent: clientExponent,
            serverModulus: serverModulus, serverExponent: serverExponent,
            code: "87BEEF"
        )
        XCTAssertEqual(hex(secret), expectedDigest)
    }

    func testCodeIsCaseAndWhitespaceInsensitive() throws {
        let secret = try PairingSecret.compute(
            clientModulus: clientModulus, clientExponent: clientExponent,
            serverModulus: serverModulus, serverExponent: serverExponent,
            code: " 87beef\n"
        )
        XCTAssertEqual(hex(secret), expectedDigest)
    }

    func testWrongCheckByteIsRejected() {
        XCTAssertThrowsError(try PairingSecret.compute(
            clientModulus: clientModulus, clientExponent: clientExponent,
            serverModulus: serverModulus, serverExponent: serverExponent,
            code: "88BEEF"
        )) { XCTAssertEqual($0 as? PairingSecretError, .checkByteMismatch) }
    }

    func testMalformedCodesAreRejected() {
        for code in ["", "87BEE", "87BEEFF", "8GBEEF", "87-BEEF"] {
            XCTAssertThrowsError(try PairingSecret.compute(
                clientModulus: clientModulus, clientExponent: clientExponent,
                serverModulus: serverModulus, serverExponent: serverExponent,
                code: code
            ), code) { XCTAssertEqual($0 as? PairingSecretError, .invalidCode) }
        }
    }

    func testStripLeadingZeros() {
        XCTAssertEqual(PairingSecret.stripLeadingZeros([0, 0, 1, 0]), [1, 0])
        XCTAssertEqual(PairingSecret.stripLeadingZeros([0, 0]), [])
        XCTAssertEqual(PairingSecret.stripLeadingZeros([9]), [9])
    }
}
