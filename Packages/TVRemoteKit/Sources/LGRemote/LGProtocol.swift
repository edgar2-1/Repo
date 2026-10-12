import Foundation
import TVRemoteCore

/// LG webOS SSAP (Simple Service Access Protocol) vocabulary.
public enum LGProtocol {
    public static let port: UInt16 = 3000
    public static let securePort: UInt16 = 3001

    /// Buttons sent over the pointer-input socket as `type:button\nname:X\n\n`.
    public static let buttonMap: [TVKey: String] = [
        .up: "UP", .down: "DOWN", .left: "LEFT", .right: "RIGHT", .select: "ENTER",
        .back: "BACK", .home: "HOME", .menu: "MENU", .exit: "EXIT",
        .info: "INFO", .guide: "GUIDE", .settings: "MENU",
        .channelUp: "CHANNELUP", .channelDown: "CHANNELDOWN",
        .play: "PLAY", .pause: "PAUSE", .stop: "STOP", .rewind: "REWIND", .fastForward: "FASTFORWARD",
        .volumeUp: "VOLUMEUP", .volumeDown: "VOLUMEDOWN", .mute: "MUTE",
        .num0: "0", .num1: "1", .num2: "2", .num3: "3", .num4: "4",
        .num5: "5", .num6: "6", .num7: "7", .num8: "8", .num9: "9",
    ]

    /// Keys handled through SSAP requests instead of the input socket.
    public static let requestKeys: Set<TVKey> = [.power, .powerOff, .powerOn, .input, .playPause]

    public static var supportedKeys: Set<TVKey> { Set(buttonMap.keys).union(requestKeys) }

    public enum Endpoint {
        public static let systemInfo = "ssap://system/getSystemInfo"
        public static let inputSocket = "ssap://com.webos.service.networkinput/getPointerInputSocket"
        public static let volumeUp = "ssap://audio/volumeUp"
        public static let volumeDown = "ssap://audio/volumeDown"
        public static let getVolume = "ssap://audio/getVolume"
        public static let setMute = "ssap://audio/setMute"
        public static let play = "ssap://media.controls/play"
        public static let pause = "ssap://media.controls/pause"
        public static let powerOff = "ssap://system/turnOff"
        public static let launch = "ssap://system.launcher/launch"
        public static let listApps = "ssap://com.webos.applicationManager/listLaunchPoints"
        public static let foregroundApp = "ssap://com.webos.applicationManager/getForegroundAppInfo"
        public static let powerState = "ssap://com.webos.service.tvpower/power/getPowerState"
        public static let showInputPicker = "ssap://com.webos.surfacemanager/showInputPicker"
        public static let insertText = "ssap://com.webos.service.ime/insertText"
        public static let deleteCharacters = "ssap://com.webos.service.ime/deleteCharacters"
        public static let sendEnter = "ssap://com.webos.service.ime/sendEnterKey"
        public static let setVolume = "ssap://audio/setVolume"
    }

    public static func socketURL(host: String, secure: Bool) -> URL {
        URL(string: secure ? "wss://\(host):\(securePort)" : "ws://\(host):\(port)")!
    }

    public static func buttonMessage(_ name: String) -> String {
        "type:button\nname:\(name)\n\n"
    }

    // MARK: Messages

    public static func helloMessage() -> [String: Any] {
        ["id": "hello", "type": "hello", "payload": [String: Any]()]
    }

    public static func requestMessage(id: String, uri: String, payload: [String: Any] = [:], subscribe: Bool = false) -> [String: Any] {
        ["id": id, "type": subscribe ? "subscribe" : "request", "uri": uri, "payload": payload]
    }

    /// Registration handshake. Mirrors what the official LG apps send; without
    /// the permissions list the TV refuses most commands.
    public static func registerMessage(clientKey: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "appVersion": "1.1",
                "manifestVersion": 1,
                "permissions": permissions,
            ],
        ]
        if let clientKey, !clientKey.isEmpty { payload["client-key"] = clientKey }
        return ["id": "register_0", "type": "register", "payload": payload]
    }

    public static let permissions: [String] = [
        "APP_TO_APP", "CLOSE", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
        "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_MEDIA_RECORDING", "CONTROL_INPUT_TEXT",
        "CONTROL_INPUT_TV", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_POWER", "CONTROL_TV_SCREEN",
        "LAUNCH", "LAUNCH_WEBAPP", "READ_APP_STATUS", "READ_COUNTRY_INFO", "READ_CURRENT_CHANNEL",
        "READ_INPUT_DEVICE_LIST", "READ_INSTALLED_APPS", "READ_LGE_SDX", "READ_LGE_TV_INPUT_EVENTS",
        "READ_NETWORK_STATE", "READ_NOTIFICATIONS", "READ_POWER_STATE", "READ_RUNNING_APPS",
        "READ_SETTINGS", "READ_TV_CHANNEL_LIST", "READ_TV_CURRENT_TIME", "READ_UPDATE_INFO", "SEARCH",
        "TEST_OPEN", "TEST_PROTECTED", "TEST_SECURE", "UPDATE_FROM_REMOTE_APP",
        "WRITE_NOTIFICATION_ALERT", "WRITE_NOTIFICATION_TOAST", "WRITE_SETTINGS",
    ]

    public static func encode(_ message: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Incoming

    public struct Message: @unchecked Sendable {
        public var type: String
        public var id: String?
        public var payload: [String: Any]
        public var error: String?

        public init?(json text: String) {
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else { return nil }
            self.type = type
            self.id = object["id"] as? String
            self.payload = (object["payload"] as? [String: Any]) ?? [:]
            self.error = object["error"] as? String
        }

        public var clientKey: String? { payload["client-key"] as? String }
        public var pairingType: String? { payload["pairingType"] as? String }
        public var returnValue: Bool { (payload["returnValue"] as? Bool) ?? true }

        /// Volume from `audio/getVolume` in either the old or new shape.
        public var volume: (level: Int, muted: Bool)? {
            if let status = payload["volumeStatus"] as? [String: Any], let level = status["volume"] as? Int {
                return (level, (status["muteStatus"] as? Bool) ?? false)
            }
            if let level = payload["volume"] as? Int {
                return (level, (payload["muted"] as? Bool) ?? false)
            }
            return nil
        }

        /// `getPowerState` → on when the panel is active (including screen-off/screen saver).
        public var isOn: Bool? {
            guard let state = payload["state"] as? String else { return nil }
            return state == "Active" || state == "Screen Off"
        }

        public var launchPoints: [TVApp] {
            guard let points = payload["launchPoints"] as? [[String: Any]] else { return [] }
            return points.compactMap { point in
                guard let id = point["id"] as? String, let title = point["title"] as? String else { return nil }
                return TVApp(id: id, name: title, symbol: LGProtocol.symbol(for: id))
            }
        }
    }

    /// Well-known webOS app ids, used when the TV's own list is unavailable.
    public static let apps: [TVApp] = [
        TVApp(id: "netflix", name: "Netflix", symbol: "n.square.fill"),
        TVApp(id: "youtube.leanback.v4", name: "YouTube", symbol: "play.rectangle.fill"),
        TVApp(id: "amazon", name: "Prime Video", symbol: "p.square.fill"),
        TVApp(id: "com.disney.disneyplus-prod", name: "Disney+", symbol: "sparkles.tv.fill"),
        TVApp(id: "spotify-beehive", name: "Spotify", symbol: "music.note"),
        TVApp(id: "cdp-30", name: "Plex", symbol: "play.square.stack.fill"),
        TVApp(id: "com.apple.appletv", name: "Apple TV", symbol: "appletv.fill"),
        TVApp(id: "com.webos.app.livetv", name: "Live TV", symbol: "tv.fill"),
    ]

    static func symbol(for id: String) -> String {
        apps.first { $0.id == id }?.symbol ?? "app.fill"
    }
}
