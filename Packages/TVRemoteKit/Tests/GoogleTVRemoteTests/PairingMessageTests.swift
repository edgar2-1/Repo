import XCTest
@testable import GoogleTVRemote

final class PairingMessageTests: XCTestCase {
    func testRequestWireFormat() throws {
        let message = PairingMessage(body: .request(serviceName: "atvremote", clientName: "watch"))
        let encoded = message.encode()
        // protocol_version=2, status=200, pairing_request(field 10)
        XCTAssertEqual(Array(encoded.prefix(6)), [0x08, 0x02, 0x10, 0xC8, 0x01, 0x52])
        XCTAssertEqual(try PairingMessage.decode(encoded), message)
    }

    func testOptionAndConfigurationRoundTrip() throws {
        let option = PairingMessage(body: .option(inputEncodings: [.hex6], outputEncodings: [], preferredRole: .input))
        XCTAssertEqual(try PairingMessage.decode(option.encode()), option)

        let configuration = PairingMessage(body: .configuration(encoding: .hex6, clientRole: .input))
        XCTAssertEqual(try PairingMessage.decode(configuration.encode()), configuration)

        let ack = PairingMessage(body: .configurationAck)
        XCTAssertEqual(ack.encode().suffix(2), [0xFA, 0x01, 0x00].suffix(2))
        XCTAssertEqual(try PairingMessage.decode(ack.encode()), ack)
    }

    func testSecretRoundTrip() throws {
        let secret = [UInt8](repeating: 0x5A, count: 32)
        let message = PairingMessage(body: .secret(secret))
        XCTAssertEqual(try PairingMessage.decode(message.encode()), message)
        let ack = PairingMessage(body: .secretAck(secret))
        XCTAssertEqual(try PairingMessage.decode(ack.encode()), ack)
    }

    func testDecodesErrorStatus() throws {
        var w = ProtoWriter()
        w.writeInt32(1, 2)
        w.writeInt32(2, 402)
        let decoded = try PairingMessage.decode(w.bytes)
        XCTAssertEqual(decoded.status, .badSecret)
        XCTAssertEqual(decoded.body, .none)
    }
}
