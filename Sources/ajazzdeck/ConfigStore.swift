import Foundation
import AppKit
import SwiftUI
import AjazzKit

/// Which physical control the configuration UI is editing.
enum ControlSelection: Hashable {
    case key(Int)
    case button(Int)
    case knob(Int)
}

/// What the sidebar has selected.
enum SidebarItem: Hashable {
    case page(Int)
    case general
}

/// Single owner of the configuration: holds the document, drives the device
/// through `DeckController`, persists changes, and watches the file for edits
/// made outside the app.
@MainActor
final class ConfigStore: ObservableObject {

    @Published var config: DeckConfig {
        didSet { if config != oldValue { scheduleCommit() } }
    }
    @Published var sidebar: SidebarItem = .page(0)
    @Published var selection: ControlSelection? = .key(1)
    @Published private(set) var isConnected = false
    @Published private(set) var firmware: String?
    @Published private(set) var serialNumber: String?
    /// The control the user most recently touched, for a live highlight.
    @Published private(set) var activeControl: ControlSelection?

    let controller: DeckController
    let profile = DeckProfile.akp03e

    private var commitTimer: Timer?
    private var watchTimer: Timer?
    private var activityTimer: Timer?
    private var lastWrittenModified: Date?

    var pageIndex: Int {
        if case .page(let i) = sidebar, config.pages.indices.contains(i) { return i }
        return min(max(0, controller.pageIndex), max(0, config.pages.count - 1))
    }

    var currentPage: Page? {
        config.pages.indices.contains(pageIndex) ? config.pages[pageIndex] : nil
    }

    init() {
        let loaded = Self.loadOrCreate()
        config = loaded
        controller = DeckController(config: loaded)
        lastWrittenModified = Self.modificationDate(of: DeckConfig.defaultURL)

        controller.onStateChange = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.isConnected = self.controller.isConnected
                self.firmware = self.controller.deck?.firmwareVersion()
                self.serialNumber = self.controller.deck?.transport.info.serialNumber
                NotificationCenter.default.post(name: NSNotification.Name("AjazzDeckStateChanged"),
                                                object: nil)
            }
        }
        controller.onDeckEvent = { [weak self] event in
            Task { @MainActor in self?.noteActivity(event) }
        }
        // Debug aid: preselect a pane or control so UI states can be inspected
        // without clicking, e.g. AJAZZDECK_PANE=general.
        switch ProcessInfo.processInfo.environment["AJAZZDECK_PANE"] {
        case "general": sidebar = .general
        case "knob":    selection = .knob(1)
        case "button":  selection = .button(1)
        default:        break
        }
        controller.start()
        startWatchingFile()
    }

    // MARK: - Loading and saving

    private static func loadOrCreate() -> DeckConfig {
        if let existing = try? DeckConfig.load() { return existing }
        let starter = DeckConfig.starter
        try? starter.save()
        return starter
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Coalesce rapid edits — typing in a text field shouldn't hammer the device
    /// or the disk on every keystroke.
    private func scheduleCommit() {
        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commit() }
        }
    }

    private func commit() {
        do {
            try config.save()
            lastWrittenModified = Self.modificationDate(of: DeckConfig.defaultURL)
        } catch {
            NSLog("ajazzdeck: save failed: \(error)")
        }
        controller.apply(config)
        if case .page(let i) = sidebar { controller.selectPage(i) }
    }

    /// Write and push immediately, for actions that shouldn't wait on the timer.
    func commitNow() {
        commitTimer?.invalidate()
        commit()
    }

    /// Poll the file's mtime so edits made in a text editor still take effect.
    private func startWatchingFile() {
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let url = DeckConfig.defaultURL
                guard let mod = Self.modificationDate(of: url) else { return }
                if let last = self.lastWrittenModified, mod <= last { return }
                guard let fresh = try? DeckConfig.load(), fresh != self.config else {
                    self.lastWrittenModified = mod
                    return
                }
                self.lastWrittenModified = mod
                // Assign without re-triggering a save of what we just read.
                self.commitTimer?.invalidate()
                self.config = fresh
                self.commitTimer?.invalidate()
                self.controller.apply(fresh)
            }
        }
    }

    // MARK: - Live activity

    /// Track which control is being touched. Presses stay lit for as long as
    /// they are held; rotations have no release event, so they self-clear.
    private func noteActivity(_ event: DeckEvent) {
        switch event {
        case .keyDown(let i):     light(.key(i), holding: true)
        case .keyUp(let i):       unlight(.key(i))
        case .buttonDown(let i):  light(.button(i), holding: true)
        case .buttonUp(let i):    unlight(.button(i))
        case .knobDown(let i):    light(.knob(i), holding: true)
        case .knobUp(let i):      unlight(.knob(i))
        case .knobTurn(let i, _): light(.knob(i), holding: false)
        case .unknown:            break
        }
    }

    private func light(_ control: ControlSelection, holding: Bool) {
        activeControl = control
        activityTimer?.invalidate()
        guard !holding else { return }
        activityTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.activeControl = nil }
        }
    }

    private func unlight(_ control: ControlSelection) {
        guard activeControl == control else { return }
        activityTimer?.invalidate()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.activeControl = nil }
        }
    }

    // MARK: - Editing helpers
    //
    // Bindings that read and write straight into the config document, creating
    // the entry on first edit so the UI never has to special-case "unassigned".

    func keyBinding(_ slot: Int) -> Binding<KeyConfig> {
        Binding(
            get: { [weak self] in
                guard let self, self.config.pages.indices.contains(self.pageIndex) else { return KeyConfig() }
                return self.config.pages[self.pageIndex].keys[String(slot)] ?? KeyConfig()
            },
            set: { [weak self] newValue in
                guard let self, self.config.pages.indices.contains(self.pageIndex) else { return }
                self.config.pages[self.pageIndex].keys[String(slot)] = newValue
            })
    }

    func buttonBinding(_ n: Int) -> Binding<ButtonConfig> {
        Binding(
            get: { [weak self] in
                guard let self, self.config.pages.indices.contains(self.pageIndex) else { return ButtonConfig() }
                return self.config.pages[self.pageIndex].buttons[String(n)] ?? ButtonConfig()
            },
            set: { [weak self] newValue in
                guard let self, self.config.pages.indices.contains(self.pageIndex) else { return }
                self.config.pages[self.pageIndex].buttons[String(n)] = newValue
            })
    }

    func knobBinding(_ n: Int) -> Binding<KnobConfig> {
        Binding(
            get: { [weak self] in
                guard let self, self.config.pages.indices.contains(self.pageIndex) else { return KnobConfig() }
                return self.config.pages[self.pageIndex].knobs[String(n)] ?? KnobConfig()
            },
            set: { [weak self] newValue in
                guard let self, self.config.pages.indices.contains(self.pageIndex) else { return }
                self.config.pages[self.pageIndex].knobs[String(n)] = newValue
            })
    }

    // MARK: - Pages

    func addPage() {
        let name = uniquePageName("Page \(config.pages.count + 1)")
        config.pages.append(Page(name: name))
        sidebar = .page(config.pages.count - 1)
    }

    func duplicatePage(_ index: Int) {
        guard config.pages.indices.contains(index) else { return }
        var copy = config.pages[index]
        copy.name = uniquePageName(copy.name + " Copy")
        config.pages.insert(copy, at: index + 1)
        sidebar = .page(index + 1)
    }

    func removePage(_ index: Int) {
        guard config.pages.count > 1, config.pages.indices.contains(index) else { return }
        config.pages.remove(at: index)
        sidebar = .page(min(index, config.pages.count - 1))
    }

    private func uniquePageName(_ base: String) -> String {
        var name = base, n = 2
        while config.pages.contains(where: { $0.name == name }) {
            name = "\(base) \(n)"; n += 1
        }
        return name
    }

    func renamePage(_ index: Int, to name: String) {
        guard config.pages.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        config.pages[index].name = trimmed
    }

    /// Where the configuration in use is kept just before an import replaces it.
    static var preImportURL: URL {
        DeckConfig.defaultURL.deletingLastPathComponent().appendingPathComponent("config.before-import.json")
    }

    /// Replace the configuration with a profile file. The current one is saved
    /// to `preImportURL` first, so an import is never a one-way trip.
    func importConfig(from url: URL) throws {
        let imported = try DeckConfig.load(from: url)
        guard !imported.pages.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        try config.save(to: Self.preImportURL)
        config = imported
        sidebar = .page(0)
        selection = .key(1)
        commitNow()
    }

    /// Replace the configuration with the shipped defaults.
    func resetToDefaults() {
        config = DeckConfig.starter
        sidebar = .page(0)
        selection = .key(1)
        commitNow()
    }

    // MARK: - Rearranging and clipboard

    /// One control's settings on the pasteboard.
    enum ControlClipboard: Codable {
        case key(KeyConfig), button(ButtonConfig), knob(KnobConfig)
    }

    static let pasteboardType = NSPasteboard.PasteboardType("local.ajazzdeck.control")

    func swapKeys(_ a: Int, _ b: Int) {
        guard a != b, config.pages.indices.contains(pageIndex) else { return }
        config.pages[pageIndex].swapKeys(a, b)
        selection = .key(b)
    }

    private func content(of control: ControlSelection) -> ControlClipboard? {
        guard let page = currentPage else { return nil }
        switch control {
        case .key(let n):    return page.keys[String(n)].map(ControlClipboard.key)
        case .button(let n): return page.buttons[String(n)].map(ControlClipboard.button)
        case .knob(let n):   return page.knobs[String(n)].map(ControlClipboard.knob)
        }
    }

    func hasContent(_ control: ControlSelection) -> Bool { content(of: control) != nil }

    func copy(_ control: ControlSelection) {
        guard let item = content(of: control), let data = try? JSONEncoder().encode(item) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: Self.pasteboardType)
    }

    func cut(_ control: ControlSelection) {
        copy(control)
        clear(control)
    }

    private var clipboard: ControlClipboard? {
        NSPasteboard.general.data(forType: Self.pasteboardType)
            .flatMap { try? JSONDecoder().decode(ControlClipboard.self, from: $0) }
    }

    /// Pasting only works between controls of the same kind.
    func canPaste(into control: ControlSelection) -> Bool {
        switch (control, clipboard) {
        case (.key, .key?), (.button, .button?), (.knob, .knob?): return true
        default: return false
        }
    }

    func paste(into control: ControlSelection) {
        guard config.pages.indices.contains(pageIndex) else { return }
        switch (control, clipboard) {
        case (.key(let n), .key(let k)?):       config.pages[pageIndex].keys[String(n)] = k
        case (.button(let n), .button(let b)?): config.pages[pageIndex].buttons[String(n)] = b
        case (.knob(let n), .knob(let k)?):     config.pages[pageIndex].knobs[String(n)] = k
        default:                                NSSound.beep()
        }
    }

    func clear(_ control: ControlSelection) {
        guard config.pages.indices.contains(pageIndex) else { return }
        switch control {
        case .key(let n):    config.pages[pageIndex].keys[String(n)] = nil
        case .button(let n): config.pages[pageIndex].buttons[String(n)] = nil
        case .knob(let n):   config.pages[pageIndex].knobs[String(n)] = nil
        }
    }

    func repaint() { controller.renderCurrentPage() }
    var hasAccessibilityPermission: Bool { controller.hasAccessibilityPermission }
    func requestAccessibility() { controller.requestAccessibilityPermission() }
}
