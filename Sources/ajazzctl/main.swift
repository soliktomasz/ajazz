import Foundation
import AjazzKit

// Line-buffer stdout so `listen` streams usefully through a pipe.
setvbuf(stdout, nil, _IOLBF, 0)

func usage() -> Never {
    print("""
    ajazzctl — control an Ajazz Stream Dock panel natively on macOS

      info                        show HID interfaces and device identity
      version                     read the firmware version string
      listen                      print key and knob events as they happen
      bright <0-100>              set backlight brightness
      clear [<slot>|all]          blank one image slot or all of them
      solid <slot> <#rrggbb>      fill one slot with a colour
      label <slot> <text>         render centred text onto one slot
      image <slot> <file>         upload artwork to one slot
      rawimage <slot> <file.jpg>  upload a JPEG verbatim (no re-encode)
      background <file>           upload a full-panel background
      calibrate                   label every slot with its index
      hold [seconds]              paint every slot and keep the session open
      wake | sleep                power the key screens on / off
      refresh                     commit pending image writes
      raw <hex>                   send a raw payload, e.g. 4352540000...
      replay <capture.bin>        replay a captured vendor session verbatim

    options:
      --size <px>                 override the slot's bitmap size
      --rot <none|90|180|270|fliph|flipv>
      --seize                     open the device exclusively
    """)
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { usage() }

func takeOption(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

var sizeOverride: Int? = nil
var orientationOverride: KeyImage.Orientation? = nil
var seize = false

if let v = takeOption("--size"), let n = Int(v) { sizeOverride = n }
if let v = takeOption("--rot") {
    switch v {
    case "none":  orientationOverride = KeyImage.Orientation.none
    case "90":    orientationOverride = .rotate90
    case "180":   orientationOverride = .rotate180
    case "270":   orientationOverride = .rotate270
    case "fliph": orientationOverride = .flipHorizontal
    case "flipv": orientationOverride = .flipVertical
    default: FileHandle.standardError.write("unknown --rot \(v)\n".data(using: .utf8)!); exit(1)
    }
}
if let i = args.firstIndex(of: "--seize") { args.remove(at: i); seize = true }

let command = args.removeFirst()

func die(_ msg: String) -> Never {
    FileHandle.standardError.write("ajazzctl: \(msg)\n".data(using: .utf8)!)
    exit(1)
}
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined(separator: " ") }

// `info` needs no open device.
if command == "info" {
    let all = HIDTransport.discoverAllInterfaces()
    if all.isEmpty { die("no Ajazz device found (VID 0x0300 / PID 0x3002)") }
    for iface in all.sorted(by: { ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage) }) {
        let role = iface.usagePage == 0xFFA0 ? "vendor control interface  <-- used by ajazzctl"
                 : (iface.usagePage == 0x01 && iface.usage == 0x06 ? "boot keyboard" : "other")
        print("""
        usagePage 0x\(String(iface.usagePage, radix: 16)) usage 0x\(String(iface.usage, radix: 16))  \(role)
          product      \(iface.info.product)
          manufacturer \(iface.info.manufacturer)
          serial       \(iface.info.serialNumber)
          reports      in=\(iface.info.maxInputReportSize) out=\(iface.info.maxOutputReportSize)
        """)
    }
    exit(0)
}

guard let deck = StreamDock.firstAvailable() else {
    die("no Ajazz vendor interface found. Quit 'Stream Dock AJAZZ.app' first.")
}
do { try deck.open(seize: seize) }
catch { die("open failed: \(error)") }

/// Bitmap size for a slot: explicit override, else the device profile.
func slotSize(_ slot: Int) -> Int { sizeOverride ?? deck.profile.imageSize(slot: slot) }
/// Rotation: explicit override, else whatever this panel needs to look upright.
let orientation = orientationOverride ?? deck.profile.orientation

switch command {
case "version":
    print(deck.firmwareVersion() ?? "<no version reported>")

case "listen":
    print("device: \(deck.transport.info.product) serial \(deck.transport.info.serialNumber)")
    print("listening — press keys and turn knobs; Ctrl-C to stop\n")
    deck.onEvent = { print("  \($0)") }
    RunLoop.current.run()

case "bright":
    guard let v = args.first, let n = Int(v) else { die("bright needs 0-100") }
    try deck.setBrightness(n)
    print("brightness -> \(n)%")

case "clear":
    let target = args.first ?? "all"
    if target == "all" { try deck.clearAllKeys(); try deck.refresh(); print("cleared all slots") }
    else if let k = Int(target) { try deck.clearKey(k); try deck.refresh(); print("cleared slot \(k)") }
    else { die("clear needs a slot index or 'all'") }

case "solid":
    guard args.count >= 2, let slot = Int(args[0]) else { die("solid <slot> <#rrggbb>") }
    var s = args[1]
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = Int(s, radix: 16) else { die("colour must be #rrggbb") }
    let px = slotSize(slot)
    let data = try KeyImage(size: px, orientation: orientation)
        .encode(solid: (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)))
    try deck.setKeyImage(slot, jpeg: data, commit: true)
    print("slot \(slot) <- #\(s)  (\(data.count) B JPEG, \(px)x\(px))")

case "label":
    guard args.count >= 2, let slot = Int(args[0]) else { die("label <slot> <text>") }
    let px = slotSize(slot)
    let data = try KeyImage(size: px, orientation: orientation).encode(text: args[1])
    try deck.setKeyImage(slot, jpeg: data, commit: true)
    print("slot \(slot) <- '\(args[1])'  (\(data.count) B JPEG, \(px)x\(px))")

case "image":
    guard args.count >= 2, let slot = Int(args[0]) else { die("image <slot> <file>") }
    let url = URL(fileURLWithPath: args[1])
    let px = slotSize(slot)
    let data = try KeyImage(size: px, orientation: orientation).encode(contentsOf: url)
    try deck.setKeyImage(slot, jpeg: data, commit: true)
    print("slot \(slot) <- \(url.lastPathComponent)  (\(data.count) B JPEG, \(px)x\(px))")

case "rawimage":
    // Send a JPEG file's bytes verbatim, with no re-encoding. Used to test
    // whether the firmware is rejecting our encoder's output specifically.
    guard args.count >= 2, let slot = Int(args[0]) else { die("rawimage <slot> <file.jpg>") }
    guard let data = FileManager.default.contents(atPath: args[1]) else { die("cannot read \(args[1])") }
    try deck.setKeyImage(slot, jpeg: data, commit: true)
    print("slot \(slot) <- \(args[1]) verbatim (\(data.count) B)")

case "background":
    guard let path = args.first else { die("background <file>") }
    let px = sizeOverride ?? 320
    let data = try KeyImage(size: px, orientation: orientation)
        .encode(contentsOf: URL(fileURLWithPath: path))
    try deck.setBackground(jpeg: data)
    print("background <- \(path) (\(data.count) B)")

case "hold":
    // Open with the vendor init sequence, paint every slot, commit once, then
    // keep the HID session open with heartbeats. Tests whether the firmware
    // discards uncommitted state when the host closes the interface.
    let seconds = Double(args.first ?? "") ?? 60
    print("painting slots, then holding the session open for \(Int(seconds))s")
    try deck.clearAllKeys()
    for slot in deck.profile.imageSlots {
        let px = slotSize(slot)
        let data = try KeyImage(size: px, orientation: orientation).encode(text: "\(slot)")
        try deck.setKeyImage(slot, jpeg: data)
        print("  slot \(slot): \(data.count) B at \(px)x\(px)")
    }
    try deck.refresh()
    print("committed (CRT..STP); holding with heartbeat — Ctrl-C to stop")
    deck.onEvent = { print("  event: \($0)") }
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    print("done holding")

case "calibrate":
    try deck.clearAllKeys()
    for slot in deck.profile.imageSlots {
        let px = slotSize(slot)
        let data = try KeyImage(size: px, orientation: orientation).encode(text: "\(slot)")
        try deck.setKeyImage(slot, jpeg: data)
    }
    try deck.refresh()
    print("labelled slots \(deck.profile.imageSlots.lowerBound)...\(deck.profile.imageSlots.upperBound)")

case "replay":
    // Replay a capture produced by the hidspy interposer, byte for byte, at the
    // original report lengths. If the panel responds to a replay but not to our
    // own frames, the difference is in construction/order, not the write path.
    guard let path = args.first else { die("replay <hidspy.bin>") }
    guard let blob = FileManager.default.contents(atPath: path) else { die("cannot read \(path)") }
    let bytes = [UInt8](blob)
    func u32(_ o: Int) -> Int {
        Int(bytes[o]) | Int(bytes[o+1]) << 8 | Int(bytes[o+2]) << 16 | Int(bytes[o+3]) << 24
    }
    var off = 0, sent = 0, got = 0
    while off + 12 <= bytes.count {
        let tag = String(bytes: bytes[off..<off+4], encoding: .ascii) ?? "?"
        let len = u32(off + 8)
        let start = off + 12
        guard start + len <= bytes.count else { break }
        let payload = Array(bytes[start..<start+len])
        off = start + len
        switch tag {
        case "SETR":
            do { try deck.transport.write(payload, reportLength: len); sent += 1 }
            catch { print("  write failed at record \(sent): \(error)") }
            // pace roughly like the vendor did
            Thread.sleep(forTimeInterval: 0.002)
        case "GETR":
            _ = deck.transport.getInputReport(length: len); got += 1
        default: break
        }
    }
    print("replayed \(sent) output reports, \(got) get-reports")

case "wake":
    try deck.wake(); print("screens woken")

case "sleep":
    try deck.sleep(); print("screens asleep")

case "refresh":
    try deck.refresh(); print("refreshed")

case "raw":
    guard let h = args.first else { die("raw <hex>") }
    let clean = h.replacingOccurrences(of: " ", with: "")
    var bytes: [UInt8] = []
    var i = clean.startIndex
    while i < clean.endIndex {
        let j = clean.index(i, offsetBy: 2, limitedBy: clean.endIndex) ?? clean.endIndex
        guard let b = UInt8(clean[i..<j], radix: 16) else { die("bad hex") }
        bytes.append(b); i = j
    }
    try deck.send(bytes)
    print("sent \(bytes.count) bytes: \(hex(bytes))")

default:
    usage()
}

// Let the write queue drain before tearing the session down.
Thread.sleep(forTimeInterval: 0.35)
deck.close()
