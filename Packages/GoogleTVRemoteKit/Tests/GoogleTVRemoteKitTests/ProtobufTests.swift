import XCTest
@testable import GoogleTVRemoteKit

final class ProtobufTests: XCTestCase {
    func testVarintEncoding() {
        var w = ProtoWriter()
        w.writeVarint(0)
        w.writeVarint(1)
        w.writeVarint(127)
        w.writeVarint(128)
        w.writeVarint(300)
        w.writeVarint(622)
        XCTAssertEqual(w.bytes, [0x00, 0x01, 0x7F, 0x80, 0x01, 0xAC, 0x02, 0xEE, 0x04])
    }

    func testVarintRoundTrip() throws {
        let values: [UInt64] = [0, 1, 127, 128, 255, 256, 16383, 16384, 1 << 32, UInt64.max]
        var w = ProtoWriter()
        values.forEach { w.writeVarint($0) }
        var r = ProtoReader(w.bytes)
        for expected in values {
            XCTAssertEqual(try r.readVarint(), expected)
        }
        XCTAssertTrue(r.isAtEnd)
    }

    func testNegativeInt32IsSignExtended() throws {
        var w = ProtoWriter()
        w.writeInt32(1, -1)
        XCTAssertEqual(w.bytes, [0x08, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01])
        var r = ProtoReader(w.bytes)
        let field = try XCTUnwrap(try r.nextField())
        XCTAssertEqual(field.field, 1)
        XCTAssertEqual(field.wireType, .varint)
        XCTAssertEqual(try r.readInt32(), -1)
    }

    func testProto3DefaultsAreOmitted() {
        var w = ProtoWriter()
        w.writeInt32(1, 0)
        w.writeBool(2, false)
        w.writeString(3, "")
        w.writeBytes(4, [])
        XCTAssertTrue(w.bytes.isEmpty)
        // ...but an empty nested message is still present.
        w.writeMessage(5) { _ in }
        XCTAssertEqual(w.bytes, [0x2A, 0x00])
    }

    func testStringAndNestedMessage() throws {
        var w = ProtoWriter()
        w.writeMessage(2) { m in
            m.writeString(1, "hi")
            m.writeUInt32(7, 15)
        }
        // tag(2, LEN)=0x12, len=6, tag(1,LEN)=0x0A len=2 'h' 'i', tag(7,VARINT)=0x38 15
        XCTAssertEqual(w.bytes, [0x12, 0x06, 0x0A, 0x02, 0x68, 0x69, 0x38, 0x0F])

        var r = ProtoReader(w.bytes)
        let outer = try XCTUnwrap(try r.nextField())
        XCTAssertEqual(outer.field, 2)
        var m = try r.readMessage()
        let f1 = try XCTUnwrap(try m.nextField())
        XCTAssertEqual(f1.field, 1)
        XCTAssertEqual(try m.readString(), "hi")
        let f7 = try XCTUnwrap(try m.nextField())
        XCTAssertEqual(f7.field, 7)
        XCTAssertEqual(try m.readUInt32(), 15)
        XCTAssertNil(try m.nextField())
    }

    func testSkipUnknownFields() throws {
        var w = ProtoWriter()
        w.writeTag(field: 9, wireType: .fixed64)
        w.writeRaw([UInt8](repeating: 0xAB, count: 8))
        w.writeTag(field: 10, wireType: .fixed32)
        w.writeRaw([1, 2, 3, 4])
        w.writeBytes(11, [9, 9])
        w.writeInt32(12, 5)

        var r = ProtoReader(w.bytes)
        var seen: [Int] = []
        while let (field, wire) = try r.nextField() {
            seen.append(field)
            if field == 12 {
                XCTAssertEqual(try r.readInt32(), 5)
            } else {
                try r.skip(wire)
            }
        }
        XCTAssertEqual(seen, [9, 10, 11, 12])
    }

    func testTruncatedInputThrows() {
        var r = ProtoReader([0x0A, 0x05, 0x01])
        XCTAssertNoThrow(try r.nextField())
        XCTAssertThrowsError(try r.readBytes()) { error in
            XCTAssertEqual(error as? ProtoError, .truncated)
        }
    }
}

final class FramingTests: XCTestCase {
    func testFramePrefixesLength() {
        XCTAssertEqual(FrameBuffer.frame([1, 2, 3]), [3, 1, 2, 3])
        let big = [UInt8](repeating: 7, count: 300)
        XCTAssertEqual(Array(FrameBuffer.frame(big).prefix(2)), [0xAC, 0x02])
    }

    func testReassemblesSplitAndCoalescedFrames() throws {
        var buffer = FrameBuffer()
        let a: [UInt8] = [0xAA]
        let b = [UInt8](repeating: 0xBB, count: 200)
        let stream = FrameBuffer.frame(a) + FrameBuffer.frame(b)

        // Deliver in awkward chunks: first byte only, then up to mid-frame, then the rest.
        buffer.append(Array(stream[0 ..< 1]))
        XCTAssertNil(try buffer.next())
        buffer.append(Array(stream[1 ..< 3]))
        XCTAssertEqual(try buffer.next(), a)
        XCTAssertNil(try buffer.next())
        buffer.append(Array(stream[3 ..< 50]))
        XCTAssertNil(try buffer.next())
        buffer.append(Array(stream[50...]))
        XCTAssertEqual(try buffer.next(), b)
        XCTAssertNil(try buffer.next())
    }

    func testEmptyFrame() throws {
        var buffer = FrameBuffer()
        buffer.append([0x00, 0x01, 0x42])
        XCTAssertEqual(try buffer.next(), [])
        XCTAssertEqual(try buffer.next(), [0x42])
    }
}
