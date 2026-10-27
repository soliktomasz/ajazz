import XCTest
@testable import AjazzKit

/// Pins the wire format to the values verified on hardware (see PROTOCOL.md).
final class DecodeTests: XCTestCase {

    /// An `ACK..OK..` input report for `index` in `state`.
    private func report(_ index: UInt8, _ state: UInt8) -> [UInt8] {
        var r: [UInt8] = Array("ACK".utf8) + [0, 0] + Array("OK".utf8) + [0, 0, index, state]
        r += [UInt8](repeating: 0, count: 512 - r.count)
        return r
    }

    func testKeys() {
        XCTAssertEqual(StreamDock.decode(report(1, 1)), .keyDown(1))
        XCTAssertEqual(StreamDock.decode(report(6, 0)), .keyUp(6))
    }

    func testButtons() {
        XCTAssertEqual(StreamDock.decode(report(0x25, 1)), .buttonDown(1))
        XCTAssertEqual(StreamDock.decode(report(0x30, 1)), .buttonDown(2))
        XCTAssertEqual(StreamDock.decode(report(0x31, 0)), .buttonUp(3))
    }

    func testKnobs() {
        XCTAssertEqual(StreamDock.decode(report(0x50, 0)), .knobTurn(index: 1, delta: -1))
        XCTAssertEqual(StreamDock.decode(report(0x51, 0)), .knobTurn(index: 1, delta: 1))
        XCTAssertEqual(StreamDock.decode(report(0x90, 0)), .knobTurn(index: 2, delta: -1))
        XCTAssertEqual(StreamDock.decode(report(0x61, 0)), .knobTurn(index: 3, delta: 1))
        XCTAssertEqual(StreamDock.decode(report(0x35, 1)), .knobDown(1))
        XCTAssertEqual(StreamDock.decode(report(0x33, 0)), .knobUp(2))
        XCTAssertEqual(StreamDock.decode(report(0x34, 1)), .knobDown(3))
    }

    func testGarbage() {
        guard case .unknown = StreamDock.decode(report(0x7F, 1)) else { return XCTFail() }
        guard case .unknown = StreamDock.decode(Array("ACK".utf8)) else { return XCTFail() }
        guard case .unknown = StreamDock.decode([UInt8](repeating: 0, count: 512)) else { return XCTFail() }
    }
}

final class FrameTests: XCTestCase {

    private let crt: [UInt8] = Array("CRT".utf8) + [0, 0]

    func testPlainCommands() {
        XCTAssertEqual(StreamDockProtocol.heartbeat, crt + Array("CONNECT".utf8))
        XCTAssertEqual(StreamDockProtocol.wakeScreen, crt + Array("DIS".utf8))
        XCTAssertEqual(StreamDockProtocol.screenOff, crt + Array("HAN".utf8))
        XCTAssertEqual(StreamDockProtocol.refresh, crt + Array("STP".utf8))
    }

    func testBrightnessClamps() {
        XCTAssertEqual(StreamDockProtocol.brightness(42), crt + Array("LIG".utf8) + [0, 0, 42])
        XCTAssertEqual(StreamDockProtocol.brightness(250)[10], 100)
        XCTAssertEqual(StreamDockProtocol.brightness(-5)[10], 0)
    }

    func testClear() {
        XCTAssertEqual(StreamDockProtocol.clearKey(3), crt + Array("CLE".utf8) + [0, 0, 0, 3])
        XCTAssertEqual(StreamDockProtocol.clearAllKeys[11], 0xFF)
        XCTAssertEqual(Array(StreamDockProtocol.disconnect[10...11]), Array("DC".utf8))
    }

    func testKeyImageHeader() {
        let f = StreamDockProtocol.keyImageHeader(byteCount: 0x1234, key: 5)
        XCTAssertEqual(Array(f[0..<8]), crt + Array("BAT".utf8))
        XCTAssertEqual(Array(f[10...12]), [0x12, 0x34, 5])
    }

    func testLogoHeader() {
        let f = StreamDockProtocol.logoHeader(byteCount: 0x0102_0304)
        XCTAssertEqual(Array(f[8...12]), [1, 2, 3, 4, 0])
    }

    func testInitQuickCommand() {
        XCTAssertEqual(Array(StreamDockProtocol.initQuickCommand[10...15]),
                       [0x11, 0x11, 0x00, 0x11, 0x00, 0x11])
    }
}
