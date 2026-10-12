import XCTest
import TVRemoteCore
@testable import SamsungRemote

final class SamsungTests: XCTestCase {
    func testSocketURL() {
        let url = SamsungProtocol.socketURL(host: "10.0.0.3", name: "Apple Watch", token: "12345678", secure: true)
        XCTAssertEqual(url.absoluteString,
                       "wss://10.0.0.3:8002/api/v2/channels/samsung.remote.control?name=QXBwbGUgV2F0Y2g%3D&token=12345678")
        let legacy = SamsungProtocol.socketURL(host: "10.0.0.3", name: "Apple Watch", token: "12345678", secure: false)
        XCTAssertEqual(legacy.absoluteString,
                       "ws://10.0.0.3:8001/api/v2/channels/samsung.remote.control?name=QXBwbGUgV2F0Y2g%3D")
    }

    func testKeyMessage() throws {
        let text = SamsungProtocol.encode(SamsungProtocol.keyMessage("KEY_VOLUP", command: "Click"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(object["method"] as? String, "ms.remote.control")
        let params = try XCTUnwrap(object["params"] as? [String: String])
        XCTAssertEqual(params, ["Cmd": "Click", "DataOfCmd": "KEY_VOLUP", "Option": "false", "TypeOfRemote": "SendRemoteKey"])
    }

    func testParsesConnectEventWithToken() throws {
        let text = """
        {"data":{"clients":[{"attributes":{"name":"QXBwbGUgV2F0Y2g="},"connectTime":1,"deviceName":"QXBwbGUgV2F0Y2g=","id":"abc","isHost":false}],"id":"abc","token":"19588326"},"event":"ms.channel.connect"}
        """
        let event = try XCTUnwrap(SamsungProtocol.Event(json: text))
        XCTAssertEqual(event.name, "ms.channel.connect")
        XCTAssertEqual(event.token, "19588326")
        XCTAssertEqual(event.clientID, "abc")

        let unauthorized = try XCTUnwrap(SamsungProtocol.Event(json: "{\"event\":\"ms.channel.unauthorized\"}"))
        XCTAssertEqual(unauthorized.name, SamsungProtocol.Event.unauthorized)
        XCTAssertNil(unauthorized.token)
    }

    func testParsesDeviceInfo() throws {
        let json = """
        {"device":{"FrameTVSupport":"false","GamePadSupport":"true","ImeSyncedSupport":"true","OS":"Tizen","TokenAuthSupport":"true","VoiceSupport":"true","countryCode":"US","description":"Samsung DTV RCR","developerIP":"0.0.0.0","developerMode":"0","duid":"uuid:1","firmwareVersion":"Unknown","id":"uuid:1","ip":"10.0.0.3","model":"20_MUSEM_UHD","modelName":"UN55TU8000","name":"[TV] Samsung 8 Series (55)","networkType":"wireless","resolution":"3840x2160","smartHubAgreement":"true","type":"Samsung SmartTV","udn":"uuid:1","wifiMac":"8C:79:F5:AA:BB:CC"},"id":"uuid:1","isSupport":"{}","name":"[TV] Samsung 8 Series (55)","remote":"1.0","type":"Samsung SmartTV","uri":"http://10.0.0.3:8001/api/v2/","version":"2.0.25"}
        """
        let info = try XCTUnwrap(SamsungProtocol.DeviceInfo(json: Data(json.utf8)))
        XCTAssertEqual(info.name, "[TV] Samsung 8 Series (55)")
        XCTAssertEqual(info.model, "UN55TU8000")
        XCTAssertEqual(info.macAddress, "8C:79:F5:AA:BB:CC")
        XCTAssertTrue(info.supportsToken)
    }

    func testKeyMapCoversNavigation() {
        for key in [TVKey.up, .down, .left, .right, .select, .back, .home, .volumeUp, .volumeDown, .mute, .power] {
            XCTAssertNotNil(SamsungProtocol.keyMap[key], "\(key)")
        }
        XCTAssertEqual(SamsungProtocol.keyMap[.back], "KEY_RETURN")
        XCTAssertEqual(SamsungProtocol.keyMap[.num0], "KEY_0")
        XCTAssertEqual(SamsungProtocol.keyMap[.num9], "KEY_9")
    }
}

final class SamsungTextTests: XCTestCase {
    func testTextMessages() throws {
        let text = SamsungProtocol.encode(SamsungProtocol.textMessage("Hi there"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let params = try XCTUnwrap(object["params"] as? [String: String])
        XCTAssertEqual(params["TypeOfRemote"], "SendInputString")
        XCTAssertEqual(params["DataOfCmd"], "base64")
        XCTAssertEqual(params["Cmd"], "SGkgdGhlcmU=")

        let end = SamsungProtocol.encode(SamsungProtocol.textEndMessage())
        XCTAssertEqual(end, #"{"method":"ms.remote.control","params":{"TypeOfRemote":"SendInputEnd"}}"#)

        let broadcast = SamsungProtocol.encode(SamsungProtocol.textReceivedMessage())
        XCTAssertTrue(broadcast.contains("custom.remote.textReceived"))
    }
}
