import XCTest
import ImageIO
@testable import AjazzKit

final class KeySymbolTests: XCTestCase {

    override class func setUp() {
        // The font ships in Resources/, two levels above this file's folder.
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/MaterialSymbols").standardized
        XCTAssertTrue(MaterialSymbols.load(from: dir))
    }

    func testParsing() {
        XCTAssertEqual(KeySymbol("play.fill"), .sf("play.fill"))
        XCTAssertEqual(KeySymbol("material:home"), .material("home", filled: false))
        XCTAssertEqual(KeySymbol("material-fill:home"), .material("home", filled: true))
        for raw in ["play.fill", "material:home", "material-fill:home"] {
            XCTAssertEqual(KeySymbol(raw).raw, raw)
        }
    }

    func testValidity() {
        XCTAssertTrue(KeySymbol("play.fill").isValid)
        XCTAssertTrue(KeySymbol("material:home").isValid)
        XCTAssertFalse(KeySymbol("material:no_such_icon").isValid)
        XCTAssertGreaterThan(MaterialSymbols.codepoints.count, 4000)
    }

    func testMaterialIsDrawnAndFillDiffers() throws {
        let outline = try KeyImage(size: 64).encode(symbol: "material:circle")
        let filled = try KeyImage(size: 64).encode(symbol: "material-fill:circle")
        // A filled circle is lit at its centre; an outlined one is hollow there.
        XCTAssertGreaterThan(try centre(filled), 200)
        XCTAssertLessThan(try centre(outline), 60)
    }

    func testUnknownMaterialThrows() {
        XCTAssertThrowsError(try KeyImage(size: 64).encode(symbol: "material:no_such_icon"))
    }

    private func centre(_ jpeg: Data) throws -> UInt8 {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 64, height: 64, bitsPerComponent: 8,
                                          bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        return px[(32 * 64 + 32) * 4]
    }
}
