import Foundation

/// Device description sent to the TV during the `RemoteConfigure` handshake.
public struct RemoteDeviceInfo: Equatable, Sendable {
    public var model: String
    public var vendor: String
    public var unknown1: Int32
    public var unknown2: String
    public var packageName: String
    public var appVersion: String

    public init(
        model: String,
        vendor: String,
        unknown1: Int32 = 1,
        unknown2: String = "1",
        packageName: String,
        appVersion: String
    ) {
        self.model = model
        self.vendor = vendor
        self.unknown1 = unknown1
        self.unknown2 = unknown2
        self.packageName = packageName
        self.appVersion = appVersion
    }
}

/// Volume report pushed by the TV.
public struct VolumeState: Equatable, Sendable {
    public var playerModel: String
    public var max: UInt32
    public var level: UInt32
    public var muted: Bool

    public init(playerModel: String = "", max: UInt32, level: UInt32, muted: Bool) {
        self.playerModel = playerModel
        self.max = max
        self.level = level
        self.muted = muted
    }
}

/// Messages of the Android TV Remote protocol v2 (TCP/TLS port 6466).
///
/// Only the subset needed for a remote control is modelled; everything else
/// decodes as `.unknown(field:)` so the stream keeps flowing.
public enum RemoteMessage: Equatable, Sendable {
    case configure(code1: Int32, deviceInfo: RemoteDeviceInfo?)
    case setActive(Int32)
    case error(Bool)
    case pingRequest(val1: Int32, val2: Int32)
    case pingResponse(val1: Int32)
    case keyInject(KeyCode, KeyDirection)
    /// The TV tells us which app currently has an input field (we only keep the package).
    case imeKeyInject(appPackage: String)
    case imeShowRequest
    case start(Bool)
    case setVolumeLevel(VolumeState)
    case appLinkLaunchRequest(String)
    case unknown(field: Int)

    // Field numbers of the `RemoteMessage` oneof.
    enum Field {
        static let configure = 1
        static let setActive = 2
        static let error = 3
        static let pingRequest = 8
        static let pingResponse = 9
        static let keyInject = 10
        static let imeKeyInject = 20
        static let imeBatchEdit = 21
        static let imeShowRequest = 22
        static let voiceBegin = 30
        static let voiceEnd = 31
        static let voicePayload = 32
        static let start = 40
        static let setVolumeLevel = 50
        static let adjustVolumeLevel = 51
        static let setPreferredAudioDevice = 60
        static let resetPreferredAudioDevice = 61
        static let appLinkLaunchRequest = 90
    }

    // MARK: Encoding

    public func encode() -> [UInt8] {
        var w = ProtoWriter()
        switch self {
        case let .configure(code1, deviceInfo):
            w.writeMessage(Field.configure) { m in
                m.writeInt32(1, code1)
                if let info = deviceInfo {
                    m.writeMessage(2) { d in
                        d.writeString(1, info.model)
                        d.writeString(2, info.vendor)
                        d.writeInt32(3, info.unknown1)
                        d.writeString(4, info.unknown2)
                        d.writeString(5, info.packageName)
                        d.writeString(6, info.appVersion)
                    }
                }
            }
        case let .setActive(active):
            w.writeMessage(Field.setActive) { m in m.writeInt32(1, active) }
        case let .error(value):
            w.writeMessage(Field.error) { m in m.writeBool(1, value) }
        case let .pingRequest(val1, val2):
            w.writeMessage(Field.pingRequest) { m in
                m.writeInt32(1, val1)
                m.writeInt32(2, val2)
            }
        case let .pingResponse(val1):
            w.writeMessage(Field.pingResponse) { m in m.writeInt32(1, val1) }
        case let .keyInject(key, direction):
            w.writeMessage(Field.keyInject) { m in
                m.writeEnum(1, key.rawValue)
                m.writeEnum(2, direction.rawValue)
            }
        case let .imeKeyInject(appPackage):
            w.writeMessage(Field.imeKeyInject) { m in
                m.writeMessage(1) { a in a.writeString(1, appPackage) }
            }
        case .imeShowRequest:
            w.writeMessage(Field.imeShowRequest) { _ in }
        case let .start(started):
            w.writeMessage(Field.start) { m in m.writeBool(1, started) }
        case let .setVolumeLevel(v):
            w.writeMessage(Field.setVolumeLevel) { m in
                m.writeString(3, v.playerModel)
                m.writeUInt32(6, v.max)
                m.writeUInt32(7, v.level)
                m.writeBool(8, v.muted)
            }
        case let .appLinkLaunchRequest(link):
            w.writeMessage(Field.appLinkLaunchRequest) { m in m.writeString(1, link) }
        case let .unknown(field):
            w.writeMessage(field) { _ in }
        }
        return w.bytes
    }

    // MARK: Decoding

    public static func decode(_ bytes: [UInt8]) throws -> RemoteMessage {
        var reader = ProtoReader(bytes)
        var result: RemoteMessage?
        while let (field, wire) = try reader.nextField() {
            guard wire == .lengthDelimited else {
                try reader.skip(wire)
                continue
            }
            var m = try reader.readMessage()
            switch field {
            case Field.configure:
                var code1: Int32 = 0
                var info: RemoteDeviceInfo?
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 1: code1 = try m.readInt32()
                    case 2:
                        var d = try m.readMessage()
                        var model = "", vendor = "", u2 = "", pkg = "", ver = ""
                        var u1: Int32 = 0
                        while let (df, dw) = try d.nextField() {
                            switch df {
                            case 1: model = try d.readString()
                            case 2: vendor = try d.readString()
                            case 3: u1 = try d.readInt32()
                            case 4: u2 = try d.readString()
                            case 5: pkg = try d.readString()
                            case 6: ver = try d.readString()
                            default: try d.skip(dw)
                            }
                        }
                        info = RemoteDeviceInfo(model: model, vendor: vendor, unknown1: u1,
                                                unknown2: u2, packageName: pkg, appVersion: ver)
                    default: try m.skip(w)
                    }
                }
                result = .configure(code1: code1, deviceInfo: info)

            case Field.setActive:
                var active: Int32 = 0
                while let (f, w) = try m.nextField() {
                    if f == 1 { active = try m.readInt32() } else { try m.skip(w) }
                }
                result = .setActive(active)

            case Field.error:
                var value = false
                while let (f, w) = try m.nextField() {
                    if f == 1 { value = try m.readBool() } else { try m.skip(w) }
                }
                result = .error(value)

            case Field.pingRequest:
                var v1: Int32 = 0, v2: Int32 = 0
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 1: v1 = try m.readInt32()
                    case 2: v2 = try m.readInt32()
                    default: try m.skip(w)
                    }
                }
                result = .pingRequest(val1: v1, val2: v2)

            case Field.pingResponse:
                var v1: Int32 = 0
                while let (f, w) = try m.nextField() {
                    if f == 1 { v1 = try m.readInt32() } else { try m.skip(w) }
                }
                result = .pingResponse(val1: v1)

            case Field.keyInject:
                var key: Int32 = 0, dir: Int32 = 0
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 1: key = try m.readInt32()
                    case 2: dir = try m.readInt32()
                    default: try m.skip(w)
                    }
                }
                if let k = KeyCode(rawValue: key), let d = KeyDirection(rawValue: dir) {
                    result = .keyInject(k, d)
                } else {
                    result = .unknown(field: field)
                }

            case Field.imeKeyInject:
                var pkg = ""
                while let (f, w) = try m.nextField() {
                    if f == 1 {
                        var a = try m.readMessage()
                        while let (af, aw) = try a.nextField() {
                            if af == 1 { pkg = try a.readString() } else { try a.skip(aw) }
                        }
                    } else {
                        try m.skip(w)
                    }
                }
                result = .imeKeyInject(appPackage: pkg)

            case Field.imeShowRequest:
                result = .imeShowRequest

            case Field.start:
                var started = false
                while let (f, w) = try m.nextField() {
                    if f == 1 { started = try m.readBool() } else { try m.skip(w) }
                }
                result = .start(started)

            case Field.setVolumeLevel:
                var v = VolumeState(max: 0, level: 0, muted: false)
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 3: v.playerModel = try m.readString()
                    case 6: v.max = try m.readUInt32()
                    case 7: v.level = try m.readUInt32()
                    case 8: v.muted = try m.readBool()
                    default: try m.skip(w)
                    }
                }
                result = .setVolumeLevel(v)

            case Field.appLinkLaunchRequest:
                var link = ""
                while let (f, w) = try m.nextField() {
                    if f == 1 { link = try m.readString() } else { try m.skip(w) }
                }
                result = .appLinkLaunchRequest(link)

            default:
                result = .unknown(field: field)
            }
        }
        return result ?? .unknown(field: 0)
    }
}
