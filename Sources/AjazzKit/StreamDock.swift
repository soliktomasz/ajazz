import Foundation

/// A physical event coming from the panel. All indices are 1-based positions in
/// physical order, not raw protocol indices.
public enum DeckEvent: Equatable {
    /// An LCD key was pressed / released.
    case keyDown(Int)
    case keyUp(Int)
    /// A screenless push button was pressed / released.
    case buttonDown(Int)
    case buttonUp(Int)
    /// Rotary encoder turned. `delta` is negative for counter-clockwise.
    case knobTurn(index: Int, delta: Int)
    /// Rotary encoder pressed inward / released.
    case knobDown(Int)
    case knobUp(Int)
    /// Anything we do not yet model, surfaced so callers can log it.
    case unknown(report: [UInt8])
}

/// High-level driver for one Stream Dock panel.
public final class StreamDock {
    public let transport: HIDTransport
    public let profile: DeckProfile
    public private(set) var isOpen = false

    /// Emitted for every decoded input event.
    public var onEvent: ((DeckEvent) -> Void)?
    /// Emitted for every raw input report — used for protocol calibration.
    public var onRawReport: (([UInt8]) -> Void)?

    private var heartbeatTimer: Timer?

    /// Brightness applied during `open()`; the vendor software uses 90.
    public var defaultBrightness = 90

    public init(transport: HIDTransport, profile: DeckProfile = .akp03e) {
        self.transport = transport
        self.profile = profile
    }

    public static func firstAvailable() -> StreamDock? {
        HIDTransport.discover().first.map { StreamDock(transport: $0) }
    }

    // MARK: - Session

    /// Open the HID interface, start reading, and perform the `HAN` handshake.
    public func open(startHeartbeat: Bool = true, seize: Bool = false) throws {
        try transport.open(seize: seize)
        transport.onInputReport = { [weak self] report in
            guard let self else { return }
            self.onRawReport?(report)
            self.onEvent?(Self.decode(report, profile: self.profile))
        }
        transport.startReading()
        isOpen = true
        // Vendor startup order, captured from the shipping software:
        //   GET_REPORT(21) -> CRT..DIS -> CRT..LIG -> CRT..QUCMD -> CRT..LIG
        // There is no `HAN` handshake for this device family, and the initial
        // GET_REPORT is part of the sequence, not just a convenience read.
        _ = firmwareVersion()
        try send(StreamDockProtocol.wakeScreen)
        try send(StreamDockProtocol.brightness(defaultBrightness))
        try send(StreamDockProtocol.initQuickCommand)
        try send(StreamDockProtocol.brightness(defaultBrightness))
        if startHeartbeat { self.startHeartbeat() }
    }

    /// Close the HID interface.
    ///
    /// `notifyDevice` sends the vendor's shutdown frame (`CRT..CLE` + `"DC"`).
    /// That frame is a *clear* variant, so a short-lived process should leave it
    /// off or the panel blanks the moment the tool exits.
    public func close(notifyDevice: Bool = false) {
        heartbeatTimer?.invalidate(); heartbeatTimer = nil
        if isOpen && notifyDevice { try? send(StreamDockProtocol.disconnect) }
        transport.close()
        isOpen = false
    }

    /// The vendor software pings the device every few seconds; without this the
    /// panel eventually drops back to its idle screen.
    public func startHeartbeat(interval: TimeInterval = 3.0) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            try? self?.send(StreamDockProtocol.heartbeat)
        }
    }

    /// The firmware version string. The vendor software reads this with a
    /// GET_REPORT on the *input* report rather than a command write.
    public func firmwareVersion() -> String? {
        transport.getInputReport(length: 21).flatMap { bytes in
            let trimmed = bytes.prefix { $0 != 0 }
            return String(bytes: trimmed, encoding: .ascii)
        }
    }

    public func send(_ payload: [UInt8]) throws {
        try transport.write(payload)
    }

    // MARK: - Commands

    public func wake() throws {
        try send(StreamDockProtocol.wakeScreen)
    }

    public func sleep() throws {
        try send(StreamDockProtocol.screenOff)
    }

    public func setBrightness(_ percent: Int) throws {
        try send(StreamDockProtocol.brightness(percent))
    }

    /// Blank one slot. Call `refresh()` when you have finished a batch — the
    /// vendor software does not commit after each clear.
    public func clearKey(_ key: Int) throws {
        try send(StreamDockProtocol.clearKey(key))
    }

    public func clearAllKeys() throws {
        try send(StreamDockProtocol.clearAllKeys)
    }

    public func refresh() throws {
        try send(StreamDockProtocol.refresh)
    }

    /// Upload one slot's artwork: a `BAT` header followed by the JPEG as raw
    /// output reports.
    ///
    /// This does *not* commit. The vendor software uploads every slot it wants
    /// to change and then issues a single `CRT..STP`; committing after each
    /// image is not how the firmware expects to be driven.
    public func setKeyImage(_ key: Int, jpeg: Data, commit: Bool = false) throws {
        try send(StreamDockProtocol.keyImageHeader(byteCount: jpeg.count, key: key))
        let chunk = max(transport.info.maxOutputReportSize, 1)
        var offset = 0
        let bytes = [UInt8](jpeg)
        while offset < bytes.count {
            let end = min(offset + chunk, bytes.count)
            try send(Array(bytes[offset..<end]))
            offset = end
        }
        if commit { try refresh() }
    }

    /// Upload a full-panel background image.
    public func setBackground(jpeg: Data) throws {
        try send(StreamDockProtocol.logoHeader(byteCount: jpeg.count))
        let chunk = max(transport.info.maxOutputReportSize, 1)
        let bytes = [UInt8](jpeg)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunk, bytes.count)
            try send(Array(bytes[offset..<end]))
            offset = end
        }
        try send(StreamDockProtocol.uploadFinished)
        try refresh()
    }

    // MARK: - Input decoding

    /// Decode an input report into a `DeckEvent`.
    ///
    /// Input reports are 512 bytes but only the first eleven carry meaning:
    /// ```
    ///   [0..2] 'A' 'C' 'K'
    ///   [3..4] 0x00 0x00
    ///   [5..6] 'O' 'K'
    ///   [7..8] 0x00 0x00
    ///   [9]    control index
    ///   [10]   state: 1 = pressed, 0 = released
    /// ```
    /// LCD keys use indices 1...6. Screenless buttons and encoder presses use
    /// scattered indices in the 0x25...0x35 range. Encoders report one event per
    /// detent with state 0, using paired indices where one member of the pair is
    /// clockwise and the other counter-clockwise. See `DeckProfile.akp03e`.
    public static func decode(_ report: [UInt8],
                              profile: DeckProfile = .akp03e) -> DeckEvent {
        guard report.count >= 11, report[0] == 0x41, report[1] == 0x43, report[2] == 0x4B else {
            return .unknown(report: Array(report.prefix(16)))
        }
        let index = Int(report[9])
        let pressed = report[10] == 0x01

        // Encoder rotation: one-shot events, distinct index per direction.
        for (i, knob) in profile.knobs.enumerated() {
            if index == knob.ccw { return .knobTurn(index: i + 1, delta: -1) }
            if index == knob.cw  { return .knobTurn(index: i + 1, delta: +1) }
        }
        // Encoder press.
        for (i, knob) in profile.knobs.enumerated() where knob.press == index {
            return pressed ? .knobDown(i + 1) : .knobUp(i + 1)
        }
        // Screenless buttons.
        for (i, button) in profile.buttons.enumerated() where button.index == index {
            return pressed ? .buttonDown(i + 1) : .buttonUp(i + 1)
        }
        // LCD keys.
        if profile.keySlots.contains(index) {
            return pressed ? .keyDown(index) : .keyUp(index)
        }
        return .unknown(report: Array(report.prefix(16)))
    }
}
