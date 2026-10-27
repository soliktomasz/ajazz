import AppKit

extension KeyImage {
    /// Render a key symbol (SF or Material, see `KeySymbol`), tinted
    /// `foreground`, centred on `background`.
    public func encode(symbol raw: String,
                       background: (UInt8, UInt8, UInt8) = (0, 0, 0),
                       foreground: (UInt8, UInt8, UInt8) = (255, 255, 255),
                       title: KeyTitle? = nil) throws -> Data {
        let side = CGFloat(size)
        let ctx = try canvas(background)
        switch KeySymbol(raw) {
        case .sf(let name):
            try drawSF(name, in: ctx, side: side, foreground: foreground)
        case .material(let name, let filled):
            try drawMaterial(name, filled: filled, in: ctx, side: side, foreground: foreground)
        }
        if let title { draw(title, in: ctx, overArt: true) }
        guard let img = ctx.makeImage() else { throw ImageError.cannotEncode }
        return try encode(alreadyRendered: img)
    }

    /// Both icon sets fill this share of the key along their longer edge.
    private static let symbolFraction: CGFloat = 0.62

    private func drawSF(_ name: String, in ctx: CGContext, side: CGFloat,
                        foreground: (UInt8, UInt8, UInt8)) throws {
        let tint = NSColor(red: CGFloat(foreground.0) / 255, green: CGFloat(foreground.1) / 255,
                           blue: CGFloat(foreground.2) / 255, alpha: 1)
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.5, weight: .semibold)
            .applying(.init(paletteColors: [tint]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else {
            throw ImageError.cannotLoad("SF Symbol '\(name)'")
        }
        // Symbols aren't square; fit the longer edge into the key's centre.
        let s = symbol.size
        let scale = min(side * Self.symbolFraction / s.width, side * Self.symbolFraction / s.height)
        let w = s.width * scale, h = s.height * scale
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        symbol.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawMaterial(_ name: String, filled: Bool, in ctx: CGContext, side: CGFloat,
                              foreground: (UInt8, UInt8, UInt8)) throws {
        guard let char = MaterialSymbols.character(name) else {
            throw ImageError.cannotLoad("Material symbol '\(name)'")
        }
        let colour = CGColor(red: CGFloat(foreground.0) / 255, green: CGFloat(foreground.1) / 255,
                             blue: CGFloat(foreground.2) / 255, alpha: 1)
        func line(_ pt: CGFloat) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: char, attributes: [
                .init(kCTFontAttributeName as String): MaterialSymbols.font(size: pt, filled: filled),
                .init(kCTForegroundColorAttributeName as String): colour,
            ]))
        }
        // Measure the glyph's ink at a reference size, then size it like an SF Symbol.
        let probe = CTLineGetBoundsWithOptions(line(100), .useGlyphPathBounds)
        guard probe.width > 0, probe.height > 0 else { throw ImageError.cannotLoad("Material symbol '\(name)'") }
        let pt = 100 * side * Self.symbolFraction / max(probe.width, probe.height)
        let l = line(pt)
        let b = CTLineGetBoundsWithOptions(l, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: (side - b.width) / 2 - b.minX, y: (side - b.height) / 2 - b.minY)
        CTLineDraw(l, ctx)
    }
}
