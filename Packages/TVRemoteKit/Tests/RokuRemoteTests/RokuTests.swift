import XCTest
import TVRemoteCore
@testable import RokuRemote

final class RokuTests: XCTestCase {
    func testKeyURLs() {
        XCTAssertEqual(RokuECP.keyURL(host: "10.0.0.2", action: "keypress", key: "Home").absoluteString,
                       "http://10.0.0.2:8060/keypress/Home")
        XCTAssertEqual(RokuECP.keyMap[.select], "Select")
        XCTAssertEqual(RokuECP.keyMap[.mute], "VolumeMute")
        XCTAssertNil(RokuECP.keyMap[.assistant])
    }

    func testParsesDeviceInfo() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <device-info>
          <serial-number>YH00AB123456</serial-number>
          <model-name>Roku Streaming Stick 4K</model-name>
          <wifi-mac>b0:a7:37:11:22:33</wifi-mac>
          <user-device-name>Living Room</user-device-name>
          <friendly-device-name>Roku Streaming Stick 4K - YH00AB</friendly-device-name>
          <is-tv>false</is-tv>
          <power-mode>PowerOn</power-mode>
        </device-info>
        """
        let info = try XCTUnwrap(RokuDeviceInfo(xml: Data(xml.utf8)))
        XCTAssertEqual(info.name, "Living Room")
        XCTAssertEqual(info.model, "Roku Streaming Stick 4K")
        XCTAssertFalse(info.isTV)
        XCTAssertTrue(info.isOn)
        XCTAssertEqual(info.macAddress, "b0:a7:37:11:22:33")
    }

    func testTVOnlyKeysHiddenOnSticks() throws {
        let xml = "<device-info><model-name>Roku Express</model-name><is-tv>false</is-tv></device-info>"
        let controller = RokuController(host: "10.0.0.2")
        XCTAssertTrue(controller.supportedKeys.contains(.volumeUp)) // unknown until connected
        let info = try XCTUnwrap(RokuDeviceInfo(xml: Data(xml.utf8)))
        XCTAssertFalse(info.isTV)
    }

    func testParsesApps() {
        let xml = """
        <apps>
          <app id="12" type="appl" version="4.1.218">Netflix</app>
          <app id="837" type="appl" version="1.0.80">YouTube</app>
          <app id="13" type="appl" version="1.0">Prime Video</app>
        </apps>
        """
        let apps = RokuAppList.parse(Data(xml.utf8))
        XCTAssertEqual(apps.map(\.id), ["12", "837", "13"])
        XCTAssertEqual(apps.map(\.name), ["Netflix", "YouTube", "Prime Video"])
        XCTAssertEqual(apps[0].symbol, "n.square.fill")
    }

    func testParsesActiveApp() {
        let xml = "<active-app><app id=\"837\" type=\"appl\" version=\"1.0.80\">YouTube</app></active-app>"
        XCTAssertEqual(RokuAppList.parseActiveApp(Data(xml.utf8)), "YouTube")
    }
}

final class RokuTextTests: XCTestCase {
    func testLiteralURLsArePercentEncoded() {
        XCTAssertEqual(RokuECP.literalURL(host: "10.0.0.2", character: "a")?.absoluteString, "http://10.0.0.2:8060/keypress/Lit_a")
        XCTAssertEqual(RokuECP.literalURL(host: "10.0.0.2", character: " ")?.absoluteString, "http://10.0.0.2:8060/keypress/Lit_%20")
        XCTAssertEqual(RokuECP.literalURL(host: "10.0.0.2", character: "&")?.absoluteString, "http://10.0.0.2:8060/keypress/Lit_%26")
        XCTAssertEqual(RokuECP.literalURL(host: "10.0.0.2", character: "é")?.absoluteString, "http://10.0.0.2:8060/keypress/Lit_%C3%A9")
    }
}
