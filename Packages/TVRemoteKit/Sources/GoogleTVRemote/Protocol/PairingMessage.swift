import Foundation

/// Messages of the Android TV pairing protocol ("Polo") v2 (TCP/TLS port 6467).
public struct PairingMessage: Equatable, Sendable {
    public enum Status: Int32, Sendable {
        case unknown = 0
        case ok = 200
        case error = 400
        case badConfiguration = 401
        case badSecret = 402
    }

    public enum RoleType: Int32, Sendable {
        case unknown = 0
        case input = 1
        case output = 2
    }

    public struct Encoding: Equatable, Sendable {
        public enum EncodingType: Int32, Sendable {
            case unknown = 0
            case alphanumeric = 1
            case numeric = 2
            case hexadecimal = 3
            case qrCode = 4
        }

        public var type: EncodingType
        public var symbolLength: UInt32

        public init(type: EncodingType, symbolLength: UInt32) {
            self.type = type
            self.symbolLength = symbolLength
        }

        /// The encoding Google TV shows on screen: 6 hex characters.
        public static let hex6 = Encoding(type: .hexadecimal, symbolLength: 6)
    }

    public enum Body: Equatable, Sendable {
        case request(serviceName: String, clientName: String)
        case requestAck(serverName: String)
        case option(inputEncodings: [Encoding], outputEncodings: [Encoding], preferredRole: RoleType)
        case configuration(encoding: Encoding, clientRole: RoleType)
        case configurationAck
        case secret([UInt8])
        case secretAck([UInt8])
        case none
    }

    public var protocolVersion: Int32
    public var status: Status
    public var body: Body

    public init(protocolVersion: Int32 = 2, status: Status = .ok, body: Body) {
        self.protocolVersion = protocolVersion
        self.status = status
        self.body = body
    }

    enum Field {
        static let protocolVersion = 1
        static let status = 2
        static let request = 10
        static let requestAck = 11
        static let option = 20
        static let configuration = 30
        static let configurationAck = 31
        static let secret = 40
        static let secretAck = 41
    }

    // MARK: Encoding

    public func encode() -> [UInt8] {
        var w = ProtoWriter()
        w.writeInt32(Field.protocolVersion, protocolVersion)
        w.writeEnum(Field.status, status.rawValue)
        switch body {
        case let .request(serviceName, clientName):
            w.writeMessage(Field.request) { m in
                m.writeString(1, serviceName)
                m.writeString(2, clientName)
            }
        case let .requestAck(serverName):
            w.writeMessage(Field.requestAck) { m in m.writeString(1, serverName) }
        case let .option(inputs, outputs, role):
            w.writeMessage(Field.option) { m in
                for e in inputs { m.writeMessage(1, Self.encode(e)) }
                for e in outputs { m.writeMessage(2, Self.encode(e)) }
                m.writeEnum(3, role.rawValue)
            }
        case let .configuration(encoding, role):
            w.writeMessage(Field.configuration) { m in
                m.writeMessage(1, Self.encode(encoding))
                m.writeEnum(2, role.rawValue)
            }
        case .configurationAck:
            w.writeMessage(Field.configurationAck) { _ in }
        case let .secret(bytes):
            w.writeMessage(Field.secret) { m in m.writeBytes(1, bytes) }
        case let .secretAck(bytes):
            w.writeMessage(Field.secretAck) { m in m.writeBytes(1, bytes) }
        case .none:
            break
        }
        return w.bytes
    }

    private static func encode(_ e: Encoding) -> ProtoWriter {
        var w = ProtoWriter()
        w.writeEnum(1, e.type.rawValue)
        w.writeUInt32(2, e.symbolLength)
        return w
    }

    // MARK: Decoding

    public static func decode(_ bytes: [UInt8]) throws -> PairingMessage {
        var reader = ProtoReader(bytes)
        var version: Int32 = 0
        var status: Status = .unknown
        var body: Body = .none

        while let (field, wire) = try reader.nextField() {
            switch field {
            case Field.protocolVersion:
                version = try reader.readInt32()
            case Field.status:
                status = Status(rawValue: try reader.readInt32()) ?? .unknown
            case Field.request:
                var m = try reader.readMessage()
                var service = "", client = ""
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 1: service = try m.readString()
                    case 2: client = try m.readString()
                    default: try m.skip(w)
                    }
                }
                body = .request(serviceName: service, clientName: client)
            case Field.requestAck:
                var m = try reader.readMessage()
                var name = ""
                while let (f, w) = try m.nextField() {
                    if f == 1 { name = try m.readString() } else { try m.skip(w) }
                }
                body = .requestAck(serverName: name)
            case Field.option:
                var m = try reader.readMessage()
                var inputs: [Encoding] = [], outputs: [Encoding] = []
                var role: RoleType = .unknown
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 1: inputs.append(try decodeEncoding(&m))
                    case 2: outputs.append(try decodeEncoding(&m))
                    case 3: role = RoleType(rawValue: try m.readInt32()) ?? .unknown
                    default: try m.skip(w)
                    }
                }
                body = .option(inputEncodings: inputs, outputEncodings: outputs, preferredRole: role)
            case Field.configuration:
                var m = try reader.readMessage()
                var enc = Encoding(type: .unknown, symbolLength: 0)
                var role: RoleType = .unknown
                while let (f, w) = try m.nextField() {
                    switch f {
                    case 1: enc = try decodeEncoding(&m)
                    case 2: role = RoleType(rawValue: try m.readInt32()) ?? .unknown
                    default: try m.skip(w)
                    }
                }
                body = .configuration(encoding: enc, clientRole: role)
            case Field.configurationAck:
                _ = try reader.readBytes()
                body = .configurationAck
            case Field.secret:
                var m = try reader.readMessage()
                var secret: [UInt8] = []
                while let (f, w) = try m.nextField() {
                    if f == 1 { secret = try m.readBytes() } else { try m.skip(w) }
                }
                body = .secret(secret)
            case Field.secretAck:
                var m = try reader.readMessage()
                var secret: [UInt8] = []
                while let (f, w) = try m.nextField() {
                    if f == 1 { secret = try m.readBytes() } else { try m.skip(w) }
                }
                body = .secretAck(secret)
            default:
                try reader.skip(wire)
            }
        }
        return PairingMessage(protocolVersion: version, status: status, body: body)
    }

    private static func decodeEncoding(_ reader: inout ProtoReader) throws -> Encoding {
        var m = try reader.readMessage()
        var e = Encoding(type: .unknown, symbolLength: 0)
        while let (f, w) = try m.nextField() {
            switch f {
            case 1: e.type = Encoding.EncodingType(rawValue: try m.readInt32()) ?? .unknown
            case 2: e.symbolLength = try m.readUInt32()
            default: try m.skip(w)
            }
        }
        return e
    }
}
