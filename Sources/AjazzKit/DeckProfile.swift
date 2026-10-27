import Foundation

/// Where a panel's encoders sit relative to its keys, so a configuration UI can
/// mirror the physical device.
public enum KnobPlacement: String, Codable {
    case rightVertical, leftVertical, belowHorizontal, aboveHorizontal
}

/// One encoder's protocol indices.
public struct KnobSpec {
    /// Input index reported for a counter-clockwise detent.
    public let ccw: Int
    /// Input index reported for a clockwise detent.
    public let cw: Int
    /// Input index reported when the encoder is pressed inward, if it clicks.
    public let press: Int?
    /// Human-facing name for this encoder's physical position.
    public let name: String

    public init(ccw: Int, cw: Int, press: Int? = nil, name: String) {
        self.ccw = ccw; self.cw = cw; self.press = press; self.name = name
    }
}

/// One plain (screenless) button's protocol index.
public struct ButtonSpec {
    public let index: Int
    public let name: String
    public init(index: Int, name: String) { self.index = index; self.name = name }
}

/// Physical description of a panel: how many controls it has, how they are
/// arranged, and what bitmap size each image slot expects.
public struct DeckProfile {
    public let model: String
    /// Image slots that accept artwork, in protocol numbering (1-based).
    public let imageSlots: ClosedRange<Int>
    /// LCD keys, in protocol numbering. Slot 1 is top-left.
    public let keySlots: ClosedRange<Int>
    /// Key grid shape, in physical reading order.
    public let keyColumns: Int
    public let keyRows: Int
    /// Screenless push buttons, in physical order.
    public let buttons: [ButtonSpec]
    /// Rotary encoders, in physical order.
    public let knobs: [KnobSpec]
    /// Where the encoders sit relative to the key grid.
    public let knobPlacement: KnobPlacement
    /// Bitmap edge length per slot, for slots that differ from `defaultSize`.
    public let sizeForSlot: [Int: Int]
    public let defaultSize: Int
    /// Rotation needed so artwork appears upright on the physical LCDs.
    public let orientation: KeyImage.Orientation

    public init(model: String, imageSlots: ClosedRange<Int>, keySlots: ClosedRange<Int>,
                keyColumns: Int, keyRows: Int, buttons: [ButtonSpec], knobs: [KnobSpec],
                knobPlacement: KnobPlacement, sizeForSlot: [Int: Int], defaultSize: Int,
                orientation: KeyImage.Orientation) {
        self.model = model; self.imageSlots = imageSlots; self.keySlots = keySlots
        self.keyColumns = keyColumns; self.keyRows = keyRows
        self.buttons = buttons; self.knobs = knobs; self.knobPlacement = knobPlacement
        self.sizeForSlot = sizeForSlot; self.defaultSize = defaultSize
        self.orientation = orientation
    }

    public func imageSize(slot: Int) -> Int { sizeForSlot[slot] ?? defaultSize }

    /// Ajazz AKP03E.
    ///
    /// Six 64x64 LCD keys in a 3x2 grid, three screenless buttons in a row
    /// below them, one large encoder top-right and two small encoders below it.
    /// All indices verified on hardware by counted-press testing.
    ///
    /// The vendor software also uploads artwork to slots 7...9 (slot 7 at
    /// 140x140); this unit has no screens there, so they are excluded from
    /// `imageSlots`.
    public static let akp03e = DeckProfile(
        model: "AKP03E",
        imageSlots: 1...6,
        keySlots: 1...6,
        keyColumns: 3,
        keyRows: 2,
        buttons: [
            ButtonSpec(index: 0x25, name: "Left"),
            ButtonSpec(index: 0x30, name: "Middle"),
            ButtonSpec(index: 0x31, name: "Right"),
        ],
        // Physical order. The protocol indices are deliberately not ascending:
        // the large encoder turns on 0x50/0x51 but presses on 0x35, while the
        // small ones turn on 0x90/0x91 and 0x60/0x61.
        knobs: [
            KnobSpec(ccw: 0x50, cw: 0x51, press: 0x35, name: "Large"),
            KnobSpec(ccw: 0x90, cw: 0x91, press: 0x33, name: "Small left"),
            KnobSpec(ccw: 0x60, cw: 0x61, press: 0x34, name: "Small right"),
        ],
        knobPlacement: .rightVertical,
        sizeForSlot: [7: 140],
        defaultSize: 64,
        orientation: .rotate270)
}
