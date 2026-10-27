import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Renders artwork into the JPEG form the panel expects for a single key.
public struct KeyImage {

    /// How the source image must be transformed before encoding. Panels differ
    /// in how their LCDs are physically mounted, so this is configurable.
    public enum Orientation: String, CaseIterable {
        case none, rotate90, rotate180, rotate270, flipHorizontal, flipVertical
    }

    public var size: Int
    public var orientation: Orientation
    public var quality: CGFloat

    public init(size: Int = 126, orientation: Orientation = .none, quality: CGFloat = 0.9) {
        self.size = size
        self.orientation = orientation
        self.quality = quality
    }

    public enum ImageError: Error, CustomStringConvertible {
        case cannotLoad(String)
        case cannotEncode
        public var description: String {
            switch self {
            case .cannotLoad(let p): return "cannot load image at \(p)"
            case .cannotEncode:      return "JPEG encoding failed"
            }
        }
    }

    /// Load an image file and encode it for `key`-sized display.
    public func encode(contentsOf url: URL, title: KeyTitle? = nil) throws -> Data {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw ImageError.cannotLoad(url.path)
        }
        return try encode(img, title: title)
    }

    /// Encode a solid colour — handy for testing and for simple button styling.
    public func encode(solid rgb: (UInt8, UInt8, UInt8)) throws -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw ImageError.cannotEncode
        }
        ctx.setFillColor(red: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
                         blue: CGFloat(rgb.2) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        guard let img = ctx.makeImage() else { throw ImageError.cannotEncode }
        return try jpeg(img)
    }

    /// Scale (aspect-fill, centre-cropped) and orient, then JPEG-encode.
    public func encode(_ image: CGImage, title: KeyTitle? = nil) throws -> Data {
        // Opaque black behind any transparency — the panel has no alpha channel.
        let ctx = try canvas((0, 0, 0))
        ctx.interpolationQuality = .high

        let side = CGFloat(size)
        // Aspect-fill so square keys are fully covered.
        let scale = max(side / CGFloat(image.width), side / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        ctx.draw(image, in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        if let title { draw(title, in: ctx, overArt: true) }

        guard let scaled = ctx.makeImage() else { throw ImageError.cannotEncode }
        return try jpeg(oriented(scaled))
    }

    private func oriented(_ image: CGImage) -> CGImage {
        if orientation == .none { return image }
        let side = CGFloat(size)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return image
        }
        ctx.translateBy(x: side / 2, y: side / 2)
        switch orientation {
        case .none: break
        case .rotate90:  ctx.rotate(by: .pi / 2)
        case .rotate180: ctx.rotate(by: .pi)
        case .rotate270: ctx.rotate(by: -.pi / 2)
        case .flipHorizontal: ctx.scaleBy(x: -1, y: 1)
        case .flipVertical:   ctx.scaleBy(x: 1, y: -1)
        }
        ctx.translateBy(x: -side / 2, y: -side / 2)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage() ?? image
    }

    /// Encode an image that is already exactly `size`x`size`, applying only
    /// the orientation transform.
    public func encode(alreadyRendered image: CGImage) throws -> Data {
        try jpeg(oriented(image))
    }

    private func jpeg(_ image: CGImage) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageError.cannotEncode
        }
        CGImageDestinationAddImage(dest, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageError.cannotEncode }
        return out as Data
    }
}
