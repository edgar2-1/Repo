import Foundation

public enum ProtoError: Error, Equatable, Sendable {
    case truncated
    case malformedVarint
    case unsupportedWireType(UInt8)
    case invalidUTF8
}

/// A tiny hand-rolled protobuf decoder matching `ProtoWriter`.
public struct ProtoReader {
    private let bytes: [UInt8]
    private var index: Int

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
        self.index = 0
    }

    public init(_ slice: ArraySlice<UInt8>) {
        self.init(Array(slice))
    }

    public var isAtEnd: Bool { index >= bytes.count }

    /// Returns the next field header, or `nil` at end of input.
    public mutating func nextField() throws -> (field: Int, wireType: WireType)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        let rawWire = UInt8(key & 0x7)
        guard let wire = WireType(rawValue: rawWire) else {
            throw ProtoError.unsupportedWireType(rawWire)
        }
        return (Int(key >> 3), wire)
    }

    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < bytes.count else { throw ProtoError.truncated }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { throw ProtoError.malformedVarint }
        }
    }

    public mutating func readInt32() throws -> Int32 {
        Int32(truncatingIfNeeded: Int64(bitPattern: try readVarint()))
    }

    public mutating func readUInt32() throws -> UInt32 {
        UInt32(truncatingIfNeeded: try readVarint())
    }

    public mutating func readBool() throws -> Bool {
        try readVarint() != 0
    }

    public mutating func readBytes() throws -> [UInt8] {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= bytes.count else { throw ProtoError.truncated }
        let out = Array(bytes[index ..< index + length])
        index += length
        return out
    }

    public mutating func readString() throws -> String {
        guard let s = String(bytes: try readBytes(), encoding: .utf8) else {
            throw ProtoError.invalidUTF8
        }
        return s
    }

    public mutating func readMessage() throws -> ProtoReader {
        ProtoReader(try readBytes())
    }

    public mutating func skip(_ wireType: WireType) throws {
        switch wireType {
        case .varint:
            _ = try readVarint()
        case .fixed64:
            try advance(8)
        case .lengthDelimited:
            _ = try readBytes()
        case .fixed32:
            try advance(4)
        }
    }

    private mutating func advance(_ n: Int) throws {
        guard index + n <= bytes.count else { throw ProtoError.truncated }
        index += n
    }
}
