import XCTest
import TVRemoteCore
@testable import LGRemote

final class LGTests: XCTestCase {
    func testRegisterMessage() throws {
        let text = LGProtocol.encode(LGProtocol.registerMessage(clientKey: "abc123"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "register")
        XCTAssertEqual(object["id"] as? String, "register_0")
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["client-key"] as? String, "abc123")
        XCTAssertEqual(payload["pairingType"] as? String, "PROMPT")
        let manifest = try XCTUnwrap(payload["manifest"] as? [String: Any])
        XCTAssertEqual(manifest["manifestVersion"] as? Int, 1)
        XCTAssertTrue(((manifest["permissions"] as? [String]) ?? []).contains("CONTROL_INPUT_JOYSTICK"))

        let fresh = LGProtocol.registerMessage(clientKey: nil)
        XCTAssertNil((fresh["payload"] as? [String: Any])?["client-key"])
    }

    func testRequestAndButtonMessages() throws {
        let text = LGProtocol.encode(LGProtocol.requestMessage(id: "7", uri: LGProtocol.Endpoint.launch, payload: ["id": "netflix"]))
        XCTAssertEqual(text, #"{"id":"7","payload":{"id":"netflix"},"type":"request","uri":"ssap:\/\/system.launcher\/launch"}"#)
        XCTAssertEqual(LGProtocol.buttonMessage("UP"), "type:button\nname:UP\n\n")
        XCTAssertEqual(LGProtocol.buttonMap[.select], "ENTER")
        XCTAssertTrue(LGProtocol.supportedKeys.contains(.power))
        XCTAssertFalse(LGProtocol.supportedKeys.contains(.assistant))
    }

    func testParsesRegistrationReplies() throws {
        let prompt = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}"#))
        XCTAssertEqual(prompt.pairingType, "PROMPT")
        let registered = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"registered","id":"register_0","payload":{"client-key":"deadbeef"}}"#))
        XCTAssertEqual(registered.clientKey, "deadbeef")
        let error = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"error","id":"register_0","error":"403 pairing cancelled","payload":{}}"#))
        XCTAssertEqual(error.error, "403 pairing cancelled")
    }

    func testParsesVolumeShapes() throws {
        let new = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"response","id":"3","payload":{"returnValue":true,"volumeStatus":{"volume":17,"muteStatus":true,"maxVolume":100}}}"#))
        XCTAssertEqual(new.volume?.level, 17)
        XCTAssertEqual(new.volume?.muted, true)
        let old = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"response","id":"3","payload":{"returnValue":true,"volume":5,"muted":false}}"#))
        XCTAssertEqual(old.volume?.level, 5)
        XCTAssertEqual(old.volume?.muted, false)
    }

    func testParsesPowerAndApps() throws {
        let power = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"response","id":"4","payload":{"returnValue":true,"state":"Active"}}"#))
        XCTAssertEqual(power.isOn, true)
        let standby = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"response","id":"4","payload":{"state":"Suspend"}}"#))
        XCTAssertEqual(standby.isOn, false)

        let apps = try XCTUnwrap(LGProtocol.Message(json: #"{"type":"response","id":"5","payload":{"launchPoints":[{"id":"netflix","title":"Netflix"},{"id":"youtube.leanback.v4","title":"YouTube"}]}}"#))
        XCTAssertEqual(apps.launchPoints.map(\.name), ["Netflix", "YouTube"])
        XCTAssertEqual(apps.launchPoints.first?.symbol, "n.square.fill")
    }
}

final class LGTextTests: XCTestCase {
    func testTextEndpoints() {
        XCTAssertEqual(LGProtocol.Endpoint.insertText, "ssap://com.webos.service.ime/insertText")
        XCTAssertEqual(LGProtocol.Endpoint.deleteCharacters, "ssap://com.webos.service.ime/deleteCharacters")
        XCTAssertEqual(LGProtocol.Endpoint.sendEnter, "ssap://com.webos.service.ime/sendEnterKey")
        let text = LGProtocol.encode(LGProtocol.requestMessage(id: "9", uri: LGProtocol.Endpoint.insertText, payload: ["text": "abc", "replace": 0]))
        XCTAssertEqual(text, #"{"id":"9","payload":{"replace":0,"text":"abc"},"type":"request","uri":"ssap:\/\/com.webos.service.ime\/insertText"}"#)
    }
}
