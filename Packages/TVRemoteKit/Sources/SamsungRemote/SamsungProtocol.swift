import Foundation
import TVRemoteCore

/// Samsung Tizen remote-control WebSocket vocabulary.
public enum SamsungProtocol {
    public static let securePort: UInt16 = 8002
    public static let legacyPort: UInt16 = 8001
    public static let channel = "samsung.remote.control"

    public static let keyMap: [TVKey: String] = [
        .up: "KEY_UP", .down: "KEY_DOWN", .left: "KEY_LEFT", .right: "KEY_RIGHT", .select: "KEY_ENTER",
        .back: "KEY_RETURN", .home: "KEY_HOME", .menu: "KEY_MENU", .exit: "KEY_EXIT",
        .power: "KEY_POWER", .powerOff: "KEY_POWER",
        .volumeUp: "KEY_VOLUP", .volumeDown: "KEY_VOLDOWN", .mute: "KEY_MUTE",
        .playPause: "KEY_PLAY", .play: "KEY_PLAY", .pause: "KEY_PAUSE", .stop: "KEY_STOP",
        .rewind: "KEY_REWIND", .fastForward: "KEY_FF",
        .info: "KEY_INFO", .guide: "KEY_GUIDE", .settings: "KEY_MENU", .input: "KEY_SOURCE",
        .channelUp: "KEY_CHUP", .channelDown: "KEY_CHDOWN",
    ]

    /// `wss://host:8002/api/v2/channels/samsung.remote.control?name=<base64>&token=<token>`
    public static func socketURL(host: String, name: String, token: String?, secure: Bool) -> URL {
        var components = URLComponents()
        components.scheme = secure ? "wss" : "ws"
        components.host = host
        components.port = Int(secure ? securePort : legacyPort)
        components.path = "/api/v2/channels/\(channel)"
        var query = [URLQueryItem(name: "name", value: Data(name.utf8).base64EncodedString())]
        if secure, let token, !token.isEmpty {
            query.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = query
        return components.url!
    }

    public static func restURL(host: String, path: String = "") -> URL {
        URL(string: "http://\(host):\(legacyPort)/api/v2/\(path)")!
    }

    // MARK: Outgoing messages

    public static func keyMessage(_ key: String, command: String) -> [String: Any] {
        [
            "method": "ms.remote.control",
            "params": [
                "Cmd": command,
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ]
    }

    public static func launchMessage(appID: String, deepLink: Bool = false) -> [String: Any] {
        [
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": [
                    "action_type": deepLink ? "DEEP_LINK" : "NATIVE_LAUNCH",
                    "appId": appID,
                ],
            ],
        ]
    }

    public static func encode(_ message: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Incoming messages

    public struct Event: Equatable, Sendable {
        public var name: String
        public var token: String?
        public var clientID: String?

        public init?(json text: String) {
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = object["event"] as? String else { return nil }
            name = event
            let payload = object["data"] as? [String: Any]
            token = (payload?["token"] as? String) ?? (payload?["token"] as? Int).map(String.init)
            clientID = payload?["id"] as? String
        }

        public static let connected = "ms.channel.connect"
        public static let unauthorized = "ms.channel.unauthorized"
        public static let timeout = "ms.channel.timeOut"
    }

    /// `GET http://host:8001/api/v2/`
    public struct DeviceInfo: Equatable, Sendable {
        public var name: String
        public var model: String
        public var macAddress: String?
        public var supportsToken: Bool

        public init?(json data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let device = object["device"] as? [String: Any] else { return nil }
            let rawName = (device["name"] as? String) ?? ""
            model = (device["modelName"] as? String) ?? "Samsung TV"
            name = rawName.isEmpty ? model : rawName
            macAddress = device["wifiMac"] as? String
            let tokenFlag = device["TokenAuthSupport"] as? String
            supportsToken = tokenFlag?.lowercased() == "true"
        }
    }

    /// Well-known Tizen app ids.
    public static let apps: [TVApp] = [
        TVApp(id: "11101200001", name: "Netflix", symbol: "n.square.fill"),
        TVApp(id: "111299001912", name: "YouTube", symbol: "play.rectangle.fill"),
        TVApp(id: "3201910019365", name: "Prime Video", symbol: "p.square.fill"),
        TVApp(id: "3201901017640", name: "Disney+", symbol: "sparkles.tv.fill"),
        TVApp(id: "3201606009684", name: "Spotify", symbol: "music.note"),
        TVApp(id: "3201512006963", name: "Plex", symbol: "play.square.stack.fill"),
        TVApp(id: "3201601007625", name: "Hulu", symbol: "h.square.fill"),
        TVApp(id: "3201806016381", name: "Apple TV", symbol: "appletv.fill"),
    ]
}
