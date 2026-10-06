import Foundation
import TVRemoteCore

/// Roku External Control Protocol (ECP) vocabulary. HTTP on port 8060.
public enum RokuECP {
    public static let port: UInt16 = 8060

    /// ECP key names for our universal keys. Keys missing here are unsupported.
    public static let keyMap: [TVKey: String] = [
        .up: "Up", .down: "Down", .left: "Left", .right: "Right", .select: "Select",
        .back: "Back", .home: "Home", .menu: "Info", .info: "Info",
        .power: "Power", .powerOn: "PowerOn", .powerOff: "PowerOff",
        .volumeUp: "VolumeUp", .volumeDown: "VolumeDown", .mute: "VolumeMute",
        .playPause: "Play", .play: "Play", .pause: "Play",
        .rewind: "Rev", .fastForward: "Fwd", .previous: "InstantReplay",
        .search: "Search", .input: "InputTuner",
        .channelUp: "ChannelUp", .channelDown: "ChannelDown",
    ]

    /// Keys that only Roku TVs (not sticks/boxes) act on.
    public static let tvOnlyKeys: Set<TVKey> = [
        .power, .powerOn, .powerOff, .volumeUp, .volumeDown, .mute, .input, .channelUp, .channelDown,
    ]

    public static func baseURL(host: String) -> URL {
        URL(string: "http://\(host):\(port)/")!
    }

    public static func keyURL(host: String, action: String, key: String) -> URL {
        baseURL(host: host).appendingPathComponent(action).appendingPathComponent(key)
    }
}

/// `/query/device-info`.
public struct RokuDeviceInfo: Equatable, Sendable {
    public var name: String
    public var model: String
    public var isTV: Bool
    public var powerMode: String
    public var serial: String
    public var macAddress: String?

    public var isOn: Bool { powerMode == "PowerOn" }

    public init?(xml data: Data) {
        guard let xml = SimpleXML.parse(data), xml["model-name"] != nil || xml["serial-number"] != nil else { return nil }
        let friendly = xml["user-device-name"].flatMap { $0.isEmpty ? nil : $0 }
            ?? xml["friendly-device-name"].flatMap { $0.isEmpty ? nil : $0 }
        model = xml["model-name"] ?? "Roku"
        name = friendly ?? model
        isTV = (xml["is-tv"] ?? "false").lowercased() == "true"
        powerMode = xml["power-mode"] ?? ""
        serial = xml["serial-number"] ?? ""
        macAddress = xml["wifi-mac"] ?? xml["ethernet-mac"]
    }
}

/// `/query/apps`.
public enum RokuAppList {
    public static func parse(_ data: Data) -> [TVApp] {
        guard let xml = SimpleXML.parse(data) else { return [] }
        return xml.elements
            .filter { $0.name == "app" }
            .compactMap { element in
                guard let id = element.attributes["id"], !element.text.isEmpty else { return nil }
                return TVApp(id: id, name: element.text, symbol: symbol(for: element.text))
            }
    }

    /// `/query/active-app` → app name.
    public static func parseActiveApp(_ data: Data) -> String? {
        guard let xml = SimpleXML.parse(data) else { return nil }
        return xml.elements.first { $0.name == "app" }?.text
    }

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("netflix") { return "n.square.fill" }
        if lower.contains("youtube") { return "play.rectangle.fill" }
        if lower.contains("prime") { return "p.square.fill" }
        if lower.contains("disney") { return "sparkles.tv.fill" }
        if lower.contains("spotify") || lower.contains("music") { return "music.note" }
        if lower.contains("plex") { return "play.square.stack.fill" }
        if lower.contains("hulu") { return "h.square.fill" }
        if lower.contains("max") || lower.contains("hbo") { return "m.square.fill" }
        return "app.fill"
    }
}
