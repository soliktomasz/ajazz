import XCTest
import ImageIO
@testable import AjazzKit

final class KeyImageTests: XCTestCase {

    func testSymbolIsDrawn() throws {
        let jpeg = try KeyImage(size: 64).encode(symbol: "circle.fill",
                                                 background: (0, 0, 0), foreground: (255, 255, 255))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        // Redraw into a known RGBA layout and sample the centre: a filled circle is white there.
        var px = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 64, height: 64, bitsPerComponent: 8,
                                          bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let centre = (32 * 64 + 32) * 4
        XCTAssertGreaterThan(px[centre], 200)
        XCTAssertLessThan(px[0], 30)  // corner stays background
    }

    /// Brightest pixel in rows `rows` (0 = top of the key as drawn, before orientation).
    private func maxBrightness(_ jpeg: Data, rows: Range<Int>) throws -> UInt8 {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 64, height: 64, bitsPerComponent: 8,
                                          bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        return rows.flatMap { r in (0..<64).map { px[(r * 64 + $0) * 4] } }.max() ?? 0
    }

    func testTitlePosition() throws {
        let k = KeyImage(size: 64)
        let top = try k.encode(text: "TOP", position: .top, size: 12)
        XCTAssertGreaterThan(try maxBrightness(top, rows: 0..<16), 200)
        XCTAssertLessThan(try maxBrightness(top, rows: 40..<64), 30)
        let bottom = try k.encode(text: "BOT", position: .bottom, size: 12)
        XCTAssertGreaterThan(try maxBrightness(bottom, rows: 48..<64), 200)
        XCTAssertLessThan(try maxBrightness(bottom, rows: 0..<24), 30)
    }

    func testTitleOverSymbol() throws {
        // A tiny symbol leaves the bottom strip dark unless the title is drawn there.
        let plain = try KeyImage(size: 64).encode(symbol: "circle.fill")
        let titled = try KeyImage(size: 64).encode(symbol: "circle.fill",
                                                   title: KeyTitle("Hi", position: .bottom, size: 10))
        XCTAssertLessThan(try maxBrightness(plain, rows: 58..<64), 30)
        XCTAssertGreaterThan(try maxBrightness(titled, rows: 52..<64), 200)
    }

    func testUnknownSymbolThrows() {
        XCTAssertThrowsError(try KeyImage(size: 64).encode(symbol: "no.such.symbol.xyz"))
    }
}
