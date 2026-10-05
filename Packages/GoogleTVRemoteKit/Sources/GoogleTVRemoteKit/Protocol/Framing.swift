import Foundation

/// Both the pairing (6467) and remote (6466) protocols frame each protobuf
/// message with a varint length prefix. `FrameBuffer` accumulates raw TLS
/// bytes and yields complete messages.
public struct FrameBuffer: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public static func frame(_ payload: [UInt8]) -> [UInt8] {
        var w = ProtoWriter()
        w.writeVarint(UInt64(payload.count))
        return w.bytes + payload
    }

    public mutating func append(_ data: [UInt8]) {
        buffer.append(contentsOf: data)
    }

    public mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    /// Pops the next complete message if one is fully buffered.
    public mutating func next() throws -> [UInt8]? {
        var reader = ProtoReader(buffer)
        let length: Int
        do {
            length = Int(try reader.readVarint())
        } catch ProtoError.truncated {
            return nil
        }
        // Length of the varint prefix = total consumed by the reader so far.
        var prefixLength = 0
        var remaining = length
        repeat {
            prefixLength += 1
            remaining >>= 7
        } while remaining > 0

        guard buffer.count >= prefixLength + length else { return nil }
        let message = Array(buffer[prefixLength ..< prefixLength + length])
        buffer.removeFirst(prefixLength + length)
        return message
    }
}
