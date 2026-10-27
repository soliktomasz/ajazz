import Foundation
import CoreGraphics
import CoreText

/// Text drawn on a key, either as the whole artwork or over an image or symbol.
public struct KeyTitle {
    public enum Position: String, Codable, CaseIterable {
        case top, middle, bottom
    }

    public var text: String
    public var position: Position
    /// Font size in key pixels (the AKP03E keys are 64 px). Nil picks a size
    /// for the position and shrinks long text to fit.
    public var size: Int?
    public var color: (UInt8, UInt8, UInt8)

    public init(_ text: String, position: Position = .middle, size: Int? = nil,
                color: (UInt8, UInt8, UInt8) = (255, 255, 255)) {
        self.text = text; self.position = position; self.size = size; self.color = color
    }
}

extension KeyImage {
    /// Render centred text onto a key — used for labelled buttons and for
    /// calibrating the physical key indexing.
    public func encode(text: String,
                       background: (UInt8, UInt8, UInt8) = (0, 0, 0),
                       foreground: (UInt8, UInt8, UInt8) = (255, 255, 255),
                       position: KeyTitle.Position = .middle,
                       size: Int? = nil) throws -> Data {
        let ctx = try canvas(background)
        draw(KeyTitle(text, position: position, size: size, color: foreground), in: ctx, overArt: false)
        guard let img = ctx.makeImage() else { throw ImageError.cannotEncode }
        return try encode(alreadyRendered: img)
    }

    /// A `size`-square opaque context filled with `rgb`.
    func canvas(_ rgb: (UInt8, UInt8, UInt8)) throws -> CGContext {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageError.cannotEncode
        }
        ctx.setFillColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
                         blue: CGFloat(rgb.2) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx
    }

    /// Draw `title` into an already-painted key. Over artwork it gets a dark
    /// halo so it stays readable on any image.
    func draw(_ title: KeyTitle, in ctx: CGContext, overArt: Bool) {
        guard !title.text.isEmpty else { return }
        let side = CGFloat(size)
        let colour = CGColor(red: CGFloat(title.color.0) / 255, green: CGFloat(title.color.1) / 255,
                             blue: CGFloat(title.color.2) / 255, alpha: 1)
        // Shrink to fit rather than overflow the key.
        var pt = title.size.map { CGFloat($0) * side / 64 }
            ?? side * (title.position == .middle && !overArt ? 0.55 : 0.22)
        var line: CTLine
        var bounds: CGRect
        repeat {
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, pt, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                .init(kCTFontAttributeName as String): font,
                .init(kCTForegroundColorAttributeName as String): colour,
            ]
            line = CTLineCreateWithAttributedString(NSAttributedString(string: title.text, attributes: attrs))
            bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            if bounds.width <= side * 0.86 || pt <= 6 { break }
            pt -= 1
        } while true

        let margin = side * 0.07
        let y: CGFloat
        switch title.position {
        case .top:    y = side - margin - bounds.height - bounds.minY
        case .middle: y = (side - bounds.height) / 2 - bounds.minY
        case .bottom: y = margin - bounds.minY
        }
        ctx.saveGState()
        if overArt {
            ctx.setShadow(offset: .zero, blur: side * 0.05, color: CGColor(gray: 0, alpha: 0.9))
        }
        ctx.textPosition = CGPoint(x: (side - bounds.width) / 2 - bounds.minX, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
