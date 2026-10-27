import AppKit
import CoreText

/// A key's `symbol` value. Plain names are SF Symbols; `material:` and
/// `material-fill:` pick a Material Symbols Rounded icon, outlined or filled.
public enum KeySymbol: Equatable {
    case sf(String)
    case material(String, filled: Bool)

    public init(_ raw: String) {
        if raw.hasPrefix("material-fill:") {
            self = .material(String(raw.dropFirst("material-fill:".count)), filled: true)
        } else if raw.hasPrefix("material:") {
            self = .material(String(raw.dropFirst("material:".count)), filled: false)
        } else {
            self = .sf(raw)
        }
    }

    /// The string stored in the config.
    public var raw: String {
        switch self {
        case .sf(let name):                return name
        case .material(let name, false):   return "material:" + name
        case .material(let name, true):    return "material-fill:" + name
        }
    }

    /// Whether this names an icon that can actually be drawn.
    public var isValid: Bool {
        switch self {
        case .sf(let name):          return NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        case .material(let name, _): return MaterialSymbols.codepoints[name] != nil
        }
    }
}

/// The bundled Material Symbols Rounded font and its name → codepoint table.
public enum MaterialSymbols {
    public static let postScriptName = "MaterialSymbolsRounded-Regular"
    public static let fileName = "MaterialSymbolsRounded"

    /// Empty until `load(from:)` succeeds.
    public private(set) static var codepoints: [String: UInt32] = [:]

    /// Register the font for this process and read its codepoints, both found in
    /// `directory`. Call once at launch, on the main thread.
    @discardableResult
    public static func load(from directory: URL) -> Bool {
        let font = directory.appendingPathComponent(fileName + ".ttf")
        guard let table = try? String(contentsOf: directory.appendingPathComponent(fileName + ".codepoints"),
                                      encoding: .utf8) else { return false }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(font as CFURL, .process, &error) {
            // Already registered (a second load) is fine; anything else isn't.
            let code = (error?.takeRetainedValue()).map(CFErrorGetCode)
            guard code == CTFontManagerError.alreadyRegistered.rawValue else { return false }
        }
        var map: [String: UInt32] = [:]
        for line in table.split(separator: "\n") {
            let parts = line.split(separator: " ")
            if parts.count == 2, let cp = UInt32(parts[1], radix: 16) { map[String(parts[0])] = cp }
        }
        codepoints = map
        return !map.isEmpty
    }

    /// The font at `size` points, outlined or filled. Weight 500 holds up better
    /// than 400 on the small key LCDs.
    public static func font(size: CGFloat, filled: Bool) -> CTFont {
        let base = CTFontCreateWithName(postScriptName as CFString, size, nil)
        let axes: [UInt32: CGFloat] = [
            fourCC("FILL"): filled ? 1 : 0,
            fourCC("wght"): 500,
            fourCC("opsz"): min(48, max(20, size)),
        ]
        let desc = CTFontDescriptorCreateWithAttributes(
            [kCTFontVariationAttribute: axes as CFDictionary] as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, size, nil, desc)
    }

    /// The icon's character, for drawing with `font(size:filled:)`.
    public static func character(_ name: String) -> String? {
        codepoints[name].flatMap(Unicode.Scalar.init).map { String(Character($0)) }
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
