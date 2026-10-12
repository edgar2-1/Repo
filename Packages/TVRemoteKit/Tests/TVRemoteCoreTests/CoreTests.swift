import XCTest
@testable import TVRemoteCore

final class SSDPResponseTests: XCTestCase {
    func testParsesRokuReply() throws {
        let raw = """
        HTTP/1.1 200 OK\r
        Cache-Control: max-age=3600\r
        ST: roku:ecp\r
        USN: uuid:roku:ecp:YH00AB123456\r
        Ext: \r
        Server: Roku/12.5.0 UPnP/1.0 Roku/12.5.0\r
        LOCATION: http://192.168.1.42:8060/\r
        \r

        """
        let response = try XCTUnwrap(SSDPResponse(datagram: Data(raw.utf8)))
        XCTAssertEqual(response.host, "192.168.1.42")
        XCTAssertEqual(response.brand, .roku)
        XCTAssertEqual(response.searchTarget, "roku:ecp")
    }

    func testDetectsLGAndSamsung() throws {
        let lg = try XCTUnwrap(SSDPResponse(datagram: Data("HTTP/1.1 200 OK\r\nST: urn:lge-com:service:webos-second-screen:1\r\nLOCATION: http://10.0.0.5:1914/\r\n\r\n".utf8)))
        XCTAssertEqual(lg.brand, .lg)
        XCTAssertEqual(lg.host, "10.0.0.5")

        let samsung = try XCTUnwrap(SSDPResponse(datagram: Data("HTTP/1.1 200 OK\r\nST: urn:samsung.com:device:RemoteControlReceiver:1\r\nLOCATION: http://10.0.0.9:7676/smp_2_\r\nSERVER: SHP, UPnP/1.0, Samsung UPnP SDK/1.0\r\n\r\n".utf8)))
        XCTAssertEqual(samsung.brand, .samsung)
        XCTAssertEqual(samsung.host, "10.0.0.9")
    }

    func testRejectsNonOK() {
        XCTAssertNil(SSDPResponse(datagram: Data("NOTIFY * HTTP/1.1\r\nNT: upnp:rootdevice\r\n\r\n".utf8)))
    }

    func testSearchRequest() {
        let text = String(decoding: SSDPResponse.searchRequest(), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("M-SEARCH * HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("MAN: \"ssdp:discover\"\r\n"))
        XCTAssertTrue(text.contains("ST: ssdp:all\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"))
    }
}

final class LocalNetworkTests: XCTestCase {
    func testScanTargetsForSlash24() {
        let iface = LocalInterface(name: "en0", address: LocalNetwork.parse("192.168.1.20")!, netmask: 0xFFFF_FF00)
        let targets = iface.scanTargets
        XCTAssertEqual(targets.count, 253)
        XCTAssertEqual(targets.first, "192.168.1.1")
        XCTAssertEqual(targets.last, "192.168.1.254")
        XCTAssertFalse(targets.contains("192.168.1.20"))
    }

    func testLargeSubnetIsCappedToOwnSlash24() {
        let iface = LocalInterface(name: "en0", address: LocalNetwork.parse("10.1.7.9")!, netmask: 0xFFFF_0000)
        let targets = iface.scanTargets
        XCTAssertEqual(targets.count, 253)
        XCTAssertTrue(targets.allSatisfy { $0.hasPrefix("10.1.7.") })
    }

    func testParse() {
        XCTAssertEqual(LocalNetwork.parse("1.2.3.4"), 0x01020304)
        XCTAssertNil(LocalNetwork.parse("1.2.3"))
        XCTAssertNil(LocalNetwork.parse("1.2.3.999"))
    }
}

final class WakeOnLANTests: XCTestCase {
    func testMagicPacket() throws {
        let packet = try XCTUnwrap(WakeOnLAN.magicPacket(macAddress: "AA:bb:cc:00:11:22"))
        XCTAssertEqual(packet.count, 102)
        XCTAssertEqual(Array(packet.prefix(6)), [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(Array(packet[6 ..< 12]), [0xAA, 0xBB, 0xCC, 0x00, 0x11, 0x22])
        XCTAssertEqual(Array(packet.suffix(6)), [0xAA, 0xBB, 0xCC, 0x00, 0x11, 0x22])
        XCTAssertNil(WakeOnLAN.magicPacket(macAddress: "not a mac"))
    }
}

final class SavedTVStoreTests: XCTestCase {
    func testUpsertRemoveAndSelection() {
        let defaults = UserDefaults(suiteName: "SavedTVStoreTests-\(UUID().uuidString)")!
        let store = SavedTVStore(defaults: defaults)
        XCTAssertTrue(store.tvs.isEmpty)

        let roku = SavedTV(brand: .roku, name: "Living Room", host: "192.168.1.5")
        let lg = SavedTV(brand: .lg, name: "Bedroom", host: "192.168.1.6")
        store.upsert(roku)
        store.upsert(lg)
        store.selectedID = lg.id
        XCTAssertEqual(store.tvs.map(\.name), ["Living Room", "Bedroom"])

        var renamed = roku
        renamed.name = "Den"
        store.upsert(renamed)
        XCTAssertEqual(store.tvs.map(\.name), ["Den", "Bedroom"])

        store.remove(id: lg.id)
        XCTAssertEqual(store.tvs.map(\.name), ["Den"])
        XCTAssertEqual(store.selectedID, roku.id)
    }
}

final class SimpleXMLTests: XCTestCase {
    func testFlattensLeavesAndKeepsAttributes() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" ?>
        <apps>
          <app id="12" type="appl" version="4.1.218">Netflix</app>
          <app id="837" type="appl" version="1.0.80">YouTube</app>
        </apps>
        """
        let parsed = try XCTUnwrap(SimpleXML.parse(Data(xml.utf8)))
        let apps = parsed.elements.filter { $0.name == "app" }
        XCTAssertEqual(apps.map(\.text), ["Netflix", "YouTube"])
        XCTAssertEqual(apps.map { $0.attributes["id"] }, ["12", "837"])
        XCTAssertEqual(parsed["app"], "YouTube")
    }
}

final class SavedTVCompatibilityTests: XCTestCase {
    func testDecodesRecordsWithoutNewerFields() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","brand":"roku","name":"Den","host":"10.0.0.4"}"#
        let tv = try JSONDecoder().decode(SavedTV.self, from: Data(json.utf8))
        XCTAssertEqual(tv.name, "Den")
        XCTAssertNil(tv.macAddress)
        XCTAssertNil(tv.colorName)
    }

    func testDigits() {
        XCTAssertEqual(TVKey.digits.count, 10)
        XCTAssertEqual(TVKey.num7.digit, 7)
        XCTAssertNil(TVKey.home.digit)
    }
}
