import Foundation

/// Protobuf wire types used by the Android TV Remote protocol.
public enum WireType: UInt8, Sendable {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

/// A tiny hand-rolled protobuf encoder.
///
/// The Android TV Remote / Pairing protocols only use varints, strings, bytes
/// and nested messages, so a full protobuf runtime is not needed. Proto3
/// semantics are followed: zero / empty scalar values are not written.
public struct ProtoWriter: Sendable {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    // MARK: Primitives

    public mutating func writeVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v))
    }

    public mutating func writeTag(field: Int, wireType: WireType) {
        writeVarint(UInt64(field) << 3 | UInt64(wireType.rawValue))
    }

    /// Appends raw bytes (e.g. a fixed-width value) after a tag written with `writeTag`.
    public mutating func writeRaw(_ raw: [UInt8]) {
        bytes.append(contentsOf: raw)
    }

    // MARK: Fields (proto3: defaults are omitted)

    public mutating func writeInt32(_ field: Int, _ value: Int32) {
        guard value != 0 else { return }
        writeTag(field: field, wireType: .varint)
        // Negative int32 values are sign-extended to 64 bits on the wire.
        writeVarint(UInt64(bitPattern: Int64(value)))
    }

    public mutating func writeUInt32(_ field: Int, _ value: UInt32) {
        guard value != 0 else { return }
        writeTag(field: field, wireType: .varint)
        writeVarint(UInt64(value))
    }

    public mutating func writeEnum(_ field: Int, _ value: Int32) {
        writeInt32(field, value)
    }

    public mutating func writeBool(_ field: Int, _ value: Bool) {
        guard value else { return }
        writeTag(field: field, wireType: .varint)
        writeVarint(1)
    }

    public mutating func writeString(_ field: Int, _ value: String) {
        guard !value.isEmpty else { return }
        writeBytes(field, Array(value.utf8))
    }

    public mutating func writeBytes(_ field: Int, _ value: [UInt8]) {
        guard !value.isEmpty else { return }
        writeTag(field: field, wireType: .lengthDelimited)
        writeVarint(UInt64(value.count))
        bytes.append(contentsOf: value)
    }

    /// Writes a nested message. Unlike scalars, an empty nested message *is*
    /// written (as a zero-length field), because presence of a sub-message is
    /// how the remote protocol distinguishes message kinds.
    public mutating func writeMessage(_ field: Int, _ message: ProtoWriter) {
        writeTag(field: field, wireType: .lengthDelimited)
        writeVarint(UInt64(message.bytes.count))
        bytes.append(contentsOf: message.bytes)
    }

    public mutating func writeMessage(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        writeMessage(field, nested)
    }
}
