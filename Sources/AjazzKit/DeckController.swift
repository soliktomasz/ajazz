import Foundation
import AppKit

/// Binds a `DeckConfig` to a physical panel: paints the current page, and turns
/// key and knob events into actions.
public final class DeckController {

    public private(set) var config: DeckConfig
    public private(set) var pageIndex = 0
    public private(set) var deck: StreamDock?

    private let runner = ActionRunner()
    private var pressStarted: [Int: Date] = [:]
    private var longPressFired: Set<Int> = []
    private var longPressTimers: [Int: Timer] = [:]
    private var reconnectTimer: Timer?
    private var liveTimer: Timer?
    private let readings = LiveReadings()
    /// Text last drawn on each live key of the current page.
    private var shownLive: [Int: String] = [:]
    private var observers: [NSObjectProtocol] = []
    /// The page last chosen by hand; shown again when the frontmost app has no
    /// page of its own.
    private var manualPageIndex = 0
    private var lastActivity = Date()
    /// Screens are off for inactivity; the panel ignores artwork until woken.
    private var isIdle = false
    /// Releases still to come for presses that only woke the panel.
    private var swallowedReleases: [DeckEvent] = []
    /// Toggle keys currently in their second state, as "page name#slot".
    private var toggledOn: Set<String> = []
    private var deckBrightness: Int

    /// Called whenever the connection state or current page changes, so a UI can
    /// refresh. Delivered on the main run loop.
    public var onStateChange: (() -> Void)?

    /// Every decoded device event, forwarded so a UI can show live activity.
    public var onDeckEvent: ((DeckEvent) -> Void)?

    public var isConnected: Bool { deck?.isOpen ?? false }
    public var currentPageName: String {
        config.pages.indices.contains(pageIndex) ? config.pages[pageIndex].name : "—"
    }

    public init(config: DeckConfig) {
        self.config = config
        self.deckBrightness = config.brightness
    }

    // MARK: - Connection

    /// Connect if the device is present, and keep retrying while it is not.
    public func start() {
        connectIfPossible()
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isConnected { self.sleepIfIdle() } else { self.connectIfPossible() }
        }
        liveTimer?.invalidate()
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshLiveKeys()
        }
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        // After system sleep the HID handle still looks open but the panel is
        // dead, so drop it and reconnect; the timer retries if USB isn't back yet.
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.deck?.close()
            self.deck = nil
            self.connectIfPossible()
            self.onStateChange?()
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  // Our own window coming forward shouldn't flip the panel.
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let id = app.bundleIdentifier else { return }
            let target = Self.page(forApp: id, in: self.config.pages, fallback: self.manualPageIndex)
            if target != self.pageIndex { self.show(target) }
        })
    }

    /// The page linked to `bundleID`, or `fallback` when none is.
    static func page(forApp bundleID: String, in pages: [Page], fallback: Int) -> Int {
        pages.firstIndex { $0.apps.contains(bundleID) } ?? fallback
    }

    public func stop() {
        reconnectTimer?.invalidate(); reconnectTimer = nil
        liveTimer?.invalidate(); liveTimer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        longPressTimers.values.forEach { $0.invalidate() }
        longPressTimers.removeAll()
        deck?.close()
        deck = nil
        onStateChange?()
    }

    private func connectIfPossible() {
        guard let dock = StreamDock.firstAvailable() else { return }
        do {
            dock.defaultBrightness = config.brightness
            try dock.open()
        } catch {
            NSLog("ajazzdeck: open failed: \(error)")
            return
        }
        dock.onEvent = { [weak self] event in self?.handle(event) }
        deck = dock
        deckBrightness = config.brightness
        isIdle = false  // open() wakes the screens
        lastActivity = Date()
        renderCurrentPage()
        onStateChange?()
    }

    // MARK: - Configuration

    public func apply(_ newConfig: DeckConfig) {
        config = newConfig
        lastActivity = Date()
        isIdle = false
        try? deck?.wake()
        if pageIndex >= config.pages.count { pageIndex = 0 }
        if manualPageIndex >= config.pages.count { manualPageIndex = 0 }
        deckBrightness = config.brightness
        try? deck?.setBrightness(config.brightness)
        renderCurrentPage()
        onStateChange?()
    }

    /// Switch pages by hand (UI, menu, or a page action).
    public func selectPage(_ index: Int) {
        guard config.pages.indices.contains(index) else { return }
        manualPageIndex = index
        if isIdle { wakeFromIdle() }
        show(index)
    }

    private func show(_ index: Int) {
        guard config.pages.indices.contains(index) else { return }
        pageIndex = index
        renderCurrentPage()
        onStateChange?()
    }

    // MARK: - Rendering

    /// Paint every slot for the active page, then commit once.
    public func renderCurrentPage() {
        guard let deck, deck.isOpen, !isIdle, config.pages.indices.contains(pageIndex) else { return }
        let page = config.pages[pageIndex]
        shownLive.removeAll()
        do {
            try deck.clearAllKeys()
            for slot in deck.profile.imageSlots {
                guard let key = currentLook(slot, in: page) else { continue }
                try deck.setKeyImage(slot, jpeg: image(for: key, slot: slot, on: deck))
                if key.live != nil { shownLive[slot] = key.label }
            }
            try deck.refresh()
        } catch {
            NSLog("ajazzdeck: render failed: \(error)")
        }
    }

    /// Re-upload only the live keys whose text changed since they were drawn.
    private func refreshLiveKeys() {
        guard let deck, deck.isOpen, !isIdle, config.pages.indices.contains(pageIndex) else { return }
        let page = config.pages[pageIndex]
        var changed = false
        for slot in deck.profile.imageSlots {
            guard let key = currentLook(slot, in: page), key.live != nil,
                  key.label != shownLive[slot] else { continue }
            do {
                try deck.setKeyImage(slot, jpeg: image(for: key, slot: slot, on: deck))
                shownLive[slot] = key.label
                changed = true
            } catch {
                NSLog("ajazzdeck: live refresh failed: \(error)")
            }
        }
        if changed { try? deck.refresh() }
    }

    /// The key as it should look right now: toggle state and live text applied.
    private func currentLook(_ slot: Int, in page: Page) -> KeyConfig? {
        guard var key = page.keys[String(slot)] else { return nil }
        if toggledOn.contains("\(page.name)#\(slot)") { key = key.toggled }
        if let live = key.live { key.label = readings.text(for: live) ?? "—" }
        return key
    }

    private func image(for key: KeyConfig, slot: Int, on deck: StreamDock) throws -> Data {
        let img = KeyImage(size: deck.profile.imageSize(slot: slot), orientation: deck.profile.orientation)
        let bg = Self.rgb(key.color) ?? (0, 0, 0)
        let fg = Self.rgb(key.textColor) ?? (255, 255, 255)
        let text = (key.showTitle ?? true) ? (key.label ?? "") : ""
        let overArt = KeyTitle(text, position: key.titlePosition ?? .bottom, size: key.titleSize, color: fg)
        if let icon = key.icon, !icon.isEmpty {
            return try img.encode(contentsOf: URL(fileURLWithPath: icon), title: overArt)
        }
        // A mistyped symbol name falls back to the label, not a blank panel.
        if let symbol = key.symbol, !symbol.isEmpty,
           let art = try? img.encode(symbol: symbol, background: bg, foreground: fg, title: overArt) {
            return art
        }
        return try img.encode(text: text, background: bg, foreground: fg,
                              position: key.titlePosition ?? .middle, size: key.titleSize)
    }

    /// Long-press timers are keyed by an Int; screenless buttons are offset so
    /// their tokens cannot collide with LCD key slot numbers.
    static func buttonToken(_ n: Int) -> Int { 1000 + n }

    static func rgb(_ hex: String?) -> (UInt8, UInt8, UInt8)? {
        guard var s = hex else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    // MARK: - Events

    /// Set AJAZZDECK_DEBUG=1 to trace event dispatch on stderr.
    private static let debugLogging =
        ProcessInfo.processInfo.environment["AJAZZDECK_DEBUG"] == "1"

    private func debug(_ message: String) {
        guard Self.debugLogging else { return }
        FileHandle.standardError.write("ajazzdeck: \(message)\n".data(using: .utf8)!)
    }

    // MARK: - Idle

    private func sleepIfIdle() {
        guard let minutes = config.idleMinutes, minutes > 0, !isIdle,
              Date().timeIntervalSince(lastActivity) >= Double(minutes) * 60 else { return }
        try? deck?.sleep()
        isIdle = true
    }

    private func wakeFromIdle() {
        isIdle = false
        try? deck?.wake()
        try? deck?.setBrightness(deckBrightness)
        renderCurrentPage()
    }

    private func handle(_ event: DeckEvent) {
        onDeckEvent?(event)
        debug("event \(event) pageIndex=\(pageIndex) pages=\(config.pages.count)")
        // Unrecognised reports may be device chatter, not a person touching it.
        if case .unknown = event { return }
        lastActivity = Date()
        if let i = swallowedReleases.firstIndex(of: event) {
            swallowedReleases.remove(at: i)
            return
        }
        // While the screens are dark the first touch only wakes them; firing an
        // action you can't see the label of would be a surprise.
        if isIdle {
            wakeFromIdle()
            switch event {
            case .keyDown(let n):    swallowedReleases.append(.keyUp(n))
            case .buttonDown(let n): swallowedReleases.append(.buttonUp(n))
            case .knobDown(let n):   swallowedReleases.append(.knobUp(n))
            default:                 break
            }
            return
        }
        guard config.pages.indices.contains(pageIndex) else {
            debug("  -> no such page, dropping")
            return
        }
        let page = config.pages[pageIndex]

        switch event {
        case .keyDown(let slot):
            pressStarted[slot] = Date()
            longPressFired.remove(slot)
            guard let key = page.keys[String(slot)], key.longPressAction != nil else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: config.longPressSeconds,
                                             repeats: false) { [weak self] _ in
                guard let self, let long = key.longPressAction else { return }
                self.longPressFired.insert(slot)
                self.perform(long, delta: 0)
            }
            longPressTimers[slot] = timer

        case .keyUp(let slot):
            longPressTimers[slot]?.invalidate()
            longPressTimers[slot] = nil
            pressStarted[slot] = nil
            // A long press already ran; don't also fire the short action.
            if longPressFired.remove(slot) != nil { return }
            guard let base = page.keys[String(slot)] else { return }
            let id = "\(page.name)#\(slot)"
            let key = toggledOn.contains(id) ? base.toggled : base
            // Flip before acting, so a page switch in the action repaints last.
            if base.toggle != nil {
                if toggledOn.remove(id) == nil { toggledOn.insert(id) }
                renderCurrentPage()
            }
            if let action = key.action { perform(action, delta: 0) }

        case .buttonDown(let n):
            // Screenless buttons share the long-press machinery, offset so their
            // timer keys cannot collide with LCD key slots.
            let token = Self.buttonToken(n)
            longPressFired.remove(token)
            guard let cfg = page.buttons[String(n)], cfg.longPressAction != nil else { return }
            longPressTimers[token] = Timer.scheduledTimer(
                withTimeInterval: config.longPressSeconds, repeats: false) { [weak self] _ in
                    guard let self, let long = cfg.longPressAction else { return }
                    self.longPressFired.insert(token)
                    self.perform(long, delta: 0)
                }

        case .buttonUp(let n):
            let token = Self.buttonToken(n)
            longPressTimers[token]?.invalidate()
            longPressTimers[token] = nil
            if longPressFired.remove(token) != nil { return }
            guard let action = page.buttons[String(n)]?.action else {
                debug("  -> button \(n) unassigned (page '\(page.name)' buttons=\(page.buttons.keys.sorted()))")
                return
            }
            perform(action, delta: 0)

        case .knobTurn(let index, let delta):
            guard let knob = page.knobs[String(index)], let action = knob.action else {
                debug("  -> knob \(index) unassigned (page '\(page.name)' knobs=\(page.knobs.keys.sorted()))")
                return
            }
            perform(action, delta: delta * max(1, knob.step ?? 1))

        case .knobDown(let index):
            guard let action = page.knobs[String(index)]?.pressAction else { return }
            perform(action, delta: 0)

        case .knobUp, .unknown:
            break
        }
    }

    private func perform(_ action: Action, delta: Int) {
        debug("  perform \(action.type) value=\(action.value ?? "-") delta=\(delta) ax=\(runner.hasAccessibilityPermission)")
        // The panel's own backlight is ours to change, not the action runner's.
        if action.type == .multi {
            runSteps(action.steps ?? [])
            return
        }
        if action.type == .deckBrightness {
            let step = delta == 0 ? 5 : delta
            deckBrightness = max(0, min(100, deckBrightness + step))
            try? deck?.setBrightness(deckBrightness)
            return
        }
        if let pageRequest = runner.run(action, delta: delta) {
            switch pageRequest.lowercased() {
            case "next":
                selectPage((pageIndex + 1) % max(1, config.pages.count))
            case "prev", "previous":
                selectPage((pageIndex - 1 + config.pages.count) % max(1, config.pages.count))
            default:
                if let i = config.pages.firstIndex(where: {
                    $0.name.caseInsensitiveCompare(pageRequest) == .orderedSame
                }) { selectPage(i) }
            }
        }
    }

    /// Run a multi-action's steps in order; `delay` steps pause without blocking
    /// the main thread, so the panel stays responsive.
    private func runSteps<C: Collection>(_ steps: C) where C.Element == Action {
        guard let step = steps.first else { return }
        let rest = steps.dropFirst()
        if step.type == .delay {
            let seconds = max(0, Double(step.value ?? "") ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.runSteps(rest)
            }
        } else {
            perform(step, delta: 0)
            runSteps(rest)
        }
    }

    /// Whether synthetic-input actions will work, and a way to ask for the right.
    public var hasAccessibilityPermission: Bool { runner.hasAccessibilityPermission }
    public func requestAccessibilityPermission() { runner.requestAccessibilityPermission() }
}
