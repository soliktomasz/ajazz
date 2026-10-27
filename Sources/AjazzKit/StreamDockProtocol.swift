import Foundation

/// The Ajazz / Mirabox "Stream Dock" vendor protocol.
///
/// Reverse engineered from `libSDLibrary.dylib` (`SDDevice::*Command` /
/// `SDDevice::add*Pack` builders). Every command is an output report padded with
/// zeroes to the interface's output report size (1024 bytes on the AKP03E), with
/// HID report ID 0.
///
/// The frame layout is:
/// ```
///   [0..2]  'C' 'R' 'T'      magic
///   [3..4]  0x00 0x00
///   [5..]   opcode (ASCII, 3-5 bytes)
///   ...     opcode-specific parameters
/// ```
/// The handshake is the one exception: it is the bare ASCII `"HAN"` with no magic.
public enum StreamDockProtocol {

    /// `"CRT" 00 00` + opcode, as the start of a command frame.
    static func command(_ opcode: String) -> [UInt8] {
        var f: [UInt8] = Array("CRT".utf8)
        f += [0x00, 0x00]
        f += Array(opcode.utf8)
        return f
    }

    /// Pad `bytes` so that writing a value at `index` is possible.
    static func frame(_ base: [UInt8], _ assignments: [(Int, UInt8)]) -> [UInt8] {
        let needed = (assignments.map { $0.0 }.max() ?? (base.count - 1)) + 1
        var f = base
        if f.count < needed { f += [UInt8](repeating: 0, count: needed - f.count) }
        for (i, v) in assignments { f[i] = v }
        return f
    }

    // MARK: - Session

    /// `"HAN"` — open the session. Must be sent before anything else.
    public static var handshake: [UInt8] { Array("HAN".utf8) }

    /// `CRT..CONNECT` — keep-alive. The vendor software sends this periodically.
    public static var heartbeat: [UInt8] { command("CONNECT") }

    /// `CRT..CLE` with `"DC"` at [10..11] — tell the device the host is going away.
    public static var disconnect: [UInt8] {
        frame(command("CLE"), [(10, UInt8(ascii: "D")), (11, UInt8(ascii: "C"))])
    }

    /// `CRT..DIS` — wake the key screens. The panel powers its LCDs down on
    /// idle and ignores artwork until it is woken.
    public static var wakeScreen: [UInt8] { command("DIS") }

    /// `CRT..HAN` — put the key screens to sleep.
    public static var screenOff: [UInt8] { command("HAN") }

    /// `CRT..VER` — ask for the hardware firmware version. The device answers on
    /// the input pipe with an ASCII version string, which makes this the most
    /// useful probe for validating frame formatting.
    public static var firmwareVersion: [UInt8] { command("VER") }

    // MARK: - Display

    /// `CRT..LIG` with the level at [10]. `level` is a percentage, 0...100.
    public static func brightness(_ level: Int) -> [UInt8] {
        frame(command("LIG"), [(10, UInt8(clamping: max(0, min(100, level))))])
    }

    /// `CRT..CLE` with the key index at [11]. Blanks one key.
    public static func clearKey(_ key: Int) -> [UInt8] {
        frame(command("CLE"), [(11, UInt8(clamping: key))])
    }

    /// `CRT..CLE` with 0xFF at [11]. Blanks every key.
    public static var clearAllKeys: [UInt8] {
        frame(command("CLE"), [(11, 0xFF)])
    }

    /// `CRT..STP` — commit pending image writes to the panel.
    ///
    /// Captured traffic from the vendor software shows a plain `CRT..STP` with
    /// no parameters. (`SDDevice::getFinishCommand` also builds a variant with
    /// `'!'` at byte 9, exposed below as `finishBatch`, but the shipping
    /// software does not use it for ordinary refreshes.)
    public static var refresh: [UInt8] { command("STP") }

    /// `CRT..STP` with `'!'` at [9] — the alternate finish frame.
    public static var finishBatch: [UInt8] {
        frame(command("STP"), [(9, UInt8(ascii: "!"))])
    }

    /// `CRT..BAT` — announce a key image: 16-bit big-endian byte count at
    /// [10..11], key index at [12]. The JPEG bytes follow as raw output reports.
    public static func keyImageHeader(byteCount: Int, key: Int) -> [UInt8] {
        frame(command("BAT"), [
            (10, UInt8((byteCount >> 8) & 0xFF)),
            (11, UInt8(byteCount & 0xFF)),
            (12, UInt8(clamping: key)),
        ])
    }

    /// `CRT..LOG` — announce a full-panel background/logo image: 32-bit
    /// big-endian byte count at [8..11].
    public static func logoHeader(byteCount: Int) -> [UInt8] {
        frame(command("LOG"), [
            (8,  UInt8((byteCount >> 24) & 0xFF)),
            (9,  UInt8((byteCount >> 16) & 0xFF)),
            (10, UInt8((byteCount >> 8) & 0xFF)),
            (11, UInt8(byteCount & 0xFF)),
            (12, 0),
        ])
    }

    /// `CRT..ULEND` — end of a logo/background upload.
    public static var uploadFinished: [UInt8] { command("ULEND") }

    // MARK: - Misc

    /// `CRT..MOD` with the mode at [10].
    public static func mode(_ mode: Int) -> [UInt8] {
        frame(command("MOD"), [(10, UInt8(clamping: mode))])
    }

    /// `CRT..SET` with two parameters at [10..11] (panel orientation).
    public static func direction(_ a: Int, _ b: Int) -> [UInt8] {
        frame(command("SET"), [(10, UInt8(clamping: a)), (11, UInt8(clamping: b))])
    }

    /// The exact `QUCMD` the vendor software issues once during startup, before
    /// it will paint the panel. Captured verbatim: `11 11 00 11 00 11` at [10..15].
    public static var initQuickCommand: [UInt8] {
        frame(command("QUCMD"), [(10, 0x11), (11, 0x11), (12, 0x00),
                                 (13, 0x11), (14, 0x00), (15, 0x11)])
    }

    /// `CRT..QUCMD` with five parameter bytes at [10..14].
    public static func quickCommand(_ p: [UInt8]) -> [UInt8] {
        var assignments: [(Int, UInt8)] = []
        for (i, v) in p.prefix(5).enumerated() { assignments.append((10 + i, v)) }
        return frame(command("QUCMD"), assignments)
    }
}
