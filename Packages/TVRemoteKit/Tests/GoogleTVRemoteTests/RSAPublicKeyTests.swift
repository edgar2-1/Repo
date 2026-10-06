import XCTest
@testable import GoogleTVRemote

final class RSAPublicKeyTests: XCTestCase {
    // Same 2048-bit key exported by OpenSSL in both encodings.
    let spki = "30820122300d06092a864886f70d01010105000382010f003082010a0282010100adc4bd526f1644e5e22a1ffc91033efb208ea1d75cd09a7b39a4bff4031959ad29269e95d6fa97b5aea7e8603cdc9a406014add7fa2c144b3a7177a93e8ce8711e5aa3f6016bbbce867916b6acea3fbbe693e1e5747779c4d2c16ca6f246dc63b4b4e0768ee9ab0d6f10fafd6d74cdbe330462c3745acae8893ffba4aeb608f14eb6a1acdc508c328332f9f65894192d7e6b5fc4654a75eb2516680dd4098d991e98a6ee24ef34d7a0a21a3296d68b533dbbed6b54fa2007f279d43734311c9fa76435f0dd125e2b23425fcc2d6516c90844187c77b4b4320d2f357caf01f1df3f22a5ff078563adbdf000e81ba5e909d2a6ea23e0ef2254c29eb146351dac8f0203010001"
    let pkcs1 = "3082010a0282010100adc4bd526f1644e5e22a1ffc91033efb208ea1d75cd09a7b39a4bff4031959ad29269e95d6fa97b5aea7e8603cdc9a406014add7fa2c144b3a7177a93e8ce8711e5aa3f6016bbbce867916b6acea3fbbe693e1e5747779c4d2c16ca6f246dc63b4b4e0768ee9ab0d6f10fafd6d74cdbe330462c3745acae8893ffba4aeb608f14eb6a1acdc508c328332f9f65894192d7e6b5fc4654a75eb2516680dd4098d991e98a6ee24ef34d7a0a21a3296d68b533dbbed6b54fa2007f279d43734311c9fa76435f0dd125e2b23425fcc2d6516c90844187c77b4b4320d2f357caf01f1df3f22a5ff078563adbdf000e81ba5e909d2a6ea23e0ef2254c29eb146351dac8f0203010001"
    let modulusHex = "adc4bd526f1644e5e22a1ffc91033efb208ea1d75cd09a7b39a4bff4031959ad29269e95d6fa97b5aea7e8603cdc9a406014add7fa2c144b3a7177a93e8ce8711e5aa3f6016bbbce867916b6acea3fbbe693e1e5747779c4d2c16ca6f246dc63b4b4e0768ee9ab0d6f10fafd6d74cdbe330462c3745acae8893ffba4aeb608f14eb6a1acdc508c328332f9f65894192d7e6b5fc4654a75eb2516680dd4098d991e98a6ee24ef34d7a0a21a3296d68b533dbbed6b54fa2007f279d43734311c9fa76435f0dd125e2b23425fcc2d6516c90844187c77b4b4320d2f357caf01f1df3f22a5ff078563adbdf000e81ba5e909d2a6ea23e0ef2254c29eb146351dac8f"

    func testParsesPKCS1() throws {
        let key = try RSAPublicKey(der: bytes(fromHex: pkcs1))
        // DER INTEGER keeps a leading 0x00 because the high bit is set; the secret
        // computation strips it, the parser must preserve the raw value.
        XCTAssertEqual(hex(key.modulus), "00" + modulusHex)
        XCTAssertEqual(key.exponent, [0x01, 0x00, 0x01])
    }

    func testParsesSubjectPublicKeyInfo() throws {
        let key = try RSAPublicKey(der: bytes(fromHex: spki))
        XCTAssertEqual(try RSAPublicKey(der: bytes(fromHex: pkcs1)), key)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try RSAPublicKey(der: [0x30, 0x03, 0x02, 0x01]))
        XCTAssertThrowsError(try RSAPublicKey(der: []))
        // EC key OID instead of rsaEncryption.
        let ec = "3059301306072a8648ce3d020106082a8648ce3d030107034200" + String(repeating: "04", count: 65)
        XCTAssertThrowsError(try RSAPublicKey(der: bytes(fromHex: ec))) {
            XCTAssertEqual($0 as? RSAPublicKeyError, .notRSA)
        }
    }
}
