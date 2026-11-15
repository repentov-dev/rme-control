import XCTest
@testable import RME_Control

final class OSCCodecTests: XCTestCase {
    func testParseFloat() {
        var bytes = OSCCodec.padded("/level")
        bytes += OSCCodec.padded(",f")
        bytes += [0x3F, 0x80, 0x00, 0x00] // 1.0
        let msg = OSCCodec.parseMessage(bytes, 0)
        XCTAssertEqual(msg?.address, "/level")
        XCTAssertEqual(msg?.floatValue ?? 0, 1.0, accuracy: 0.0001)
        XCTAssertNil(msg?.stringValue)
    }

    func testParseString() {
        var bytes = OSCCodec.padded("/device")
        bytes += OSCCodec.padded(",s")
        bytes += OSCCodec.padded("Fireface")
        let msg = OSCCodec.parseMessage(bytes, 0)
        XCTAssertEqual(msg?.address, "/device")
        XCTAssertNil(msg?.floatValue)
        XCTAssertEqual(msg?.stringValue, "Fireface")
    }

    func testParseNegativeFloat() {
        var bytes = OSCCodec.padded("/level")
        bytes += OSCCodec.padded(",f")
        bytes += [0xC3, 0x48, 0x00, 0x00] // -200.0
        let msg = OSCCodec.parseMessage(bytes, 0)
        XCTAssertEqual(msg?.floatValue ?? 0, -200, accuracy: 0.0001)
    }

    /// Пакет с одним сообщением даёт ровно одно сообщение — без «мусорных» хвостов.
    func testSingleMessagePacketYieldsOneMessage() {
        let floatPacket = [UInt8](OSCCodec.encode(address: "/output/0/volume", value: -12))
        XCTAssertEqual(OSCCodec.parsePacket(floatPacket).map(\.address), ["/output/0/volume"])

        let stringPacket = OSCCodec.padded("/status/device") + OSCCodec.padded(",s") + OSCCodec.padded("Fireface UFX")
        let messages = OSCCodec.parsePacket(stringPacket)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.stringValue, "Fireface UFX")
    }

    func testGarbageIsIgnored() {
        XCTAssertTrue(OSCCodec.parsePacket([]).isEmpty)
        XCTAssertTrue(OSCCodec.parsePacket(Array("hello".utf8) + [0, 0, 0]).isEmpty)
    }

    func testEncodeDecodeRoundTrip() {
        let data = OSCCodec.encode(address: "/output/0/faderlin", value: 0.75)
        XCTAssertEqual(data.count % 4, 0)
        let messages = OSCCodec.parsePacket([UInt8](data))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.address, "/output/0/faderlin")
        XCTAssertEqual(messages.first?.floatValue ?? 0, 0.75, accuracy: 0.0001)
    }

    func testBundleIsUnpacked() {
        let a = [UInt8](OSCCodec.encode(address: "/a", value: 1))
        let b = [UInt8](OSCCodec.encode(address: "/b", value: 2))
        var bundle = OSCCodec.padded("#bundle") + [UInt8](repeating: 0, count: 8)
        for el in [a, b] {
            let n = UInt32(el.count).bigEndian
            bundle += withUnsafeBytes(of: n) { Array($0) } + el
        }
        let messages = OSCCodec.parsePacket(bundle)
        XCTAssertEqual(messages.map(\.address), ["/a", "/b"])
        XCTAssertEqual(messages.compactMap(\.floatValue), [1, 2])
    }
}
