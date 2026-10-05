import XCTest
@testable import GoogleTVRemoteKit

final class RemoteMessageTests: XCTestCase {
    func testKeyInjectWireFormat() throws {
        // remote_key_inject (field 10, LEN) { key_code = DPAD_UP (19), direction = SHORT (3) }
        let encoded = RemoteMessage.keyInject(.dpadUp, .short).encode()
        XCTAssertEqual(encoded, [0x52, 0x04, 0x08, 0x13, 0x10, 0x03])
        XCTAssertEqual(try RemoteMessage.decode(encoded), .keyInject(.dpadUp, .short))
    }

    func testSetActiveAndPingResponse() throws {
        XCTAssertEqual(RemoteMessage.setActive(622).encode(), [0x12, 0x03, 0x08, 0xEE, 0x04])
        XCTAssertEqual(RemoteMessage.pingResponse(val1: 5).encode(), [0x4A, 0x02, 0x08, 0x05])
        // A zero ping value still has to produce a (now empty) ping_response message.
        XCTAssertEqual(RemoteMessage.pingResponse(val1: 0).encode(), [0x4A, 0x00])
        XCTAssertEqual(try RemoteMessage.decode([0x4A, 0x00]), .pingResponse(val1: 0))
    }

    func testConfigureRoundTrip() throws {
        let info = RemoteDeviceInfo(model: "Apple Watch", vendor: "Apple",
                                    packageName: "watch-remote", appVersion: "1.0")
        let message = RemoteMessage.configure(code1: 622, deviceInfo: info)
        let encoded = message.encode()
        XCTAssertEqual(encoded[0], 0x0A) // field 1, LEN
        XCTAssertEqual(try RemoteMessage.decode(encoded), message)
    }

    func testDecodesServerConfigureWithoutDeviceInfo() throws {
        // remote_configure { code1 = 622 }
        let decoded = try RemoteMessage.decode([0x0A, 0x03, 0x08, 0xEE, 0x04])
        XCTAssertEqual(decoded, .configure(code1: 622, deviceInfo: nil))
    }

    func testDecodesPingRequest() throws {
        // remote_ping_request (field 8) { val1 = 1234, val2 = 1 }
        var body = ProtoWriter()
        body.writeInt32(1, 1234)
        body.writeInt32(2, 1)
        var w = ProtoWriter()
        w.writeMessage(8, body)
        XCTAssertEqual(try RemoteMessage.decode(w.bytes), .pingRequest(val1: 1234, val2: 1))
    }

    func testDecodesVolumeLevel() throws {
        var body = ProtoWriter()
        body.writeInt32(1, 1)
        body.writeString(3, "Chromecast")
        body.writeUInt32(6, 100)
        body.writeUInt32(7, 42)
        body.writeBool(8, true)
        var w = ProtoWriter()
        w.writeMessage(50, body)
        XCTAssertEqual(
            try RemoteMessage.decode(w.bytes),
            .setVolumeLevel(VolumeState(playerModel: "Chromecast", max: 100, level: 42, muted: true))
        )
    }

    func testDecodesStartAndImeApp() throws {
        var start = ProtoWriter()
        start.writeMessage(40) { $0.writeBool(1, true) }
        XCTAssertEqual(try RemoteMessage.decode(start.bytes), .start(true))

        var ime = ProtoWriter()
        ime.writeMessage(20) { m in
            m.writeMessage(1) { $0.writeString(1, "com.netflix.ninja") }
            m.writeMessage(2) { $0.writeInt32(1, 7) } // unrelated sub-message, must be skipped
        }
        XCTAssertEqual(try RemoteMessage.decode(ime.bytes), .imeKeyInject(appPackage: "com.netflix.ninja"))
    }

    func testUnknownMessagesDoNotThrow() throws {
        var w = ProtoWriter()
        w.writeMessage(60) { $0.writeInt32(1, 3) }
        XCTAssertEqual(try RemoteMessage.decode(w.bytes), .unknown(field: 60))
    }

    func testAppLinkRoundTrip() throws {
        let message = RemoteMessage.appLinkLaunchRequest("https://www.youtube.com")
        XCTAssertEqual(try RemoteMessage.decode(message.encode()), message)
    }
}
