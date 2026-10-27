import Foundation
import AppKit
import CoreGraphics

/// Carries out the actions bound to keys and knobs.
///
/// Synthesising keystrokes and media keys posts CGEvents, which macOS gates
/// behind Accessibility permission — see `hasAccessibilityPermission`.
public final class ActionRunner {

    public init() {}

    /// Whether this process may post synthetic input events. Without it,
    /// `hotkey`, `media`, `volume`, `brightness` and `scroll` silently do nothing.
    ///
    /// This asks `CGPreflightPostEventAccess`, which is the permission that
    /// actually governs `CGEvent.post`. `AXIsProcessTrusted()` covers the
    /// accessibility *API* and is not the same thing — it keeps reporting `true`
    /// from a stale TCC entry after an ad-hoc-signed binary is rebuilt, while
    /// event posting is silently refused.
    public var hasAccessibilityPermission: Bool {
        CGPreflightPostEventAccess()
    }

    /// Ask macOS for permission to post events, showing the system prompt.
    public func requestAccessibilityPermission() {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
    }

    /// Run `action`. `delta` is the signed detent count for knob turns.
    /// Returns a page request when the action asks to change pages.
    @discardableResult
    public func run(_ action: Action, delta: Int = 0) -> String? {
        switch action.type {
        case .none:
            return nil

        case .launch:
            guard let target = action.value else { return nil }
            launch(target)

        case .url:
            guard let v = action.value, let u = URL(string: v) else { return nil }
            NSWorkspace.shared.open(u)

        case .shell:
            guard let cmd = action.value else { return nil }
            shell(cmd)

        case .hotkey:
            // On a knob: `value` per clockwise detent, `args[0]` per counter-clockwise one.
            let combo = delta < 0 ? action.args?.first : action.value
            guard let combo, !combo.isEmpty else { return nil }
            for _ in 0..<max(1, abs(delta)) { sendHotkey(combo) }

        case .media:
            switch (action.value ?? "playpause").lowercased() {
            case "next", "forward":       tapSystemKey(NX_KEYTYPE_NEXT)
            case "previous", "prev", "back": tapSystemKey(NX_KEYTYPE_PREVIOUS)
            default:                      tapSystemKey(NX_KEYTYPE_PLAY)
            }

        case .volume:
            // As a knob: relative. As a key: an explicit up/down/mute.
            if delta != 0 {
                let key = delta > 0 ? NX_KEYTYPE_SOUND_UP : NX_KEYTYPE_SOUND_DOWN
                for _ in 0..<abs(delta) { tapSystemKey(key) }
            } else {
                switch (action.value ?? "up").lowercased() {
                case "down": tapSystemKey(NX_KEYTYPE_SOUND_DOWN)
                case "mute": tapSystemKey(NX_KEYTYPE_MUTE)
                default:     tapSystemKey(NX_KEYTYPE_SOUND_UP)
                }
            }

        case .brightness:
            if delta != 0 {
                let key = delta > 0 ? NX_KEYTYPE_BRIGHTNESS_UP : NX_KEYTYPE_BRIGHTNESS_DOWN
                for _ in 0..<abs(delta) { tapSystemKey(key) }
            } else {
                switch (action.value ?? "up").lowercased() {
                case "down": tapSystemKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
                default:     tapSystemKey(NX_KEYTYPE_BRIGHTNESS_UP)
                }
            }

        case .scroll:
            guard delta != 0 else { return nil }
            if let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                wheelCount: 1, wheel1: Int32(delta), wheel2: 0, wheel3: 0) {
                ev.post(tap: .cghidEventTap)
            }

        case .deckBrightness:
            // Handled by the controller, which owns the device handle.
            return nil

        case .page:
            return action.value ?? "next"

        case .multi, .delay:
            // Sequenced by the controller, which can also switch pages mid-run.
            return nil

        case .task:
            guard let id = action.value, let task = TaskLibrary.task(id) else {
                NSLog("ajazzdeck: unknown task '\(action.value ?? "")'")
                return nil
            }
            switch task.effect {
            case .hotkey(let combo):   sendHotkey(combo)
            case .shell(let command):  shell(command)
            case .open(let target):    launch(target)
            case .appleScript(let s):  run("/usr/bin/osascript", ["-e", s])
            case .dial(let cw, let ccw):
                for _ in 0..<abs(delta) { sendHotkey(delta > 0 ? cw : ccw) }
            case .custom(let run):
                run(action.args ?? [])
            case .customDial(let run):
                if delta != 0 { run(action.args ?? [], delta) }
            }
        }
        return nil
    }

    // MARK: - Launching

    private func launch(_ target: String) {
        let ws = NSWorkspace.shared
        // A path, a bundle identifier, or a plain application name.
        if target.hasPrefix("/") {
            let url = URL(fileURLWithPath: target)
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if target.contains("."), let url = ws.urlForApplication(withBundleIdentifier: target) {
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        for dir in ["/Applications", "/System/Applications",
                    NSHomeDirectory() + "/Applications"] {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(target + ".app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                ws.openApplication(at: candidate, configuration: NSWorkspace.OpenConfiguration())
                return
            }
        }
        // Fall back to `open -a`, which knows about Spotlight's index.
        shell("open -a \(target.replacingOccurrences(of: "'", with: "'\\''"))")
    }

    private func shell(_ command: String) {
        run("/bin/sh", ["-c", command])
    }

    /// Start a process without waiting for it.
    private func run(_ executable: String, _ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        do { try p.run() } catch { NSLog("ajazzdeck: \(executable) failed: \(error)") }
    }

    // MARK: - Synthetic input

    /// Post a media/system key press-and-release (volume, brightness, transport).
    private func tapSystemKey(_ key: Int32) {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: UInt(down ? 0xA00 : 0xB00))
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            guard let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                              modifierFlags: flags, timestamp: 0,
                                              windowNumber: 0, context: nil,
                                              subtype: 8, data1: data1, data2: -1) else { return }
            ev.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    /// Parse and send a combo like "cmd+shift+4" or "ctrl+alt+right".
    private func sendHotkey(_ combo: String) {
        guard let (code, flags) = Self.parseHotkey(combo) else {
            NSLog("ajazzdeck: unrecognised hotkey '\(combo)'")
            return
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Key code and modifier flags for a combo, or nil if a part is unknown.
    static func parseHotkey(_ combo: String) -> (CGKeyCode, CGEventFlags)? {
        var flags = CGEventFlags()
        var keyName: String?
        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part.trimmingCharacters(in: .whitespaces) {
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            case "shift":                  flags.insert(.maskShift)
            case "alt", "opt", "option":   flags.insert(.maskAlternate)
            case "ctrl", "control":        flags.insert(.maskControl)
            case "fn", "function":         flags.insert(.maskSecondaryFn)
            case let other:                keyName = other
            }
        }
        guard let name = keyName, let code = keyCodes[name] else { return nil }
        // A real keyboard flags these keys itself, and system shortcuts such as
        // Mission Control (ctrl+up) only match events that carry the same flags.
        if ["left", "right", "up", "down"].contains(name) {
            flags.formUnion([.maskSecondaryFn, .maskNumericPad])
        } else if name.hasPrefix("f") && name.count > 1 && Int(name.dropFirst()) != nil
                    || ["home", "end", "pageup", "pagedown", "forwarddelete"].contains(name) {
            flags.insert(.maskSecondaryFn)
        }
        return (code, flags)
    }

    /// Virtual key codes for the keys people actually bind.
    static let keyCodes: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
            "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
            "backspace": 51, "escape": 53, "esc": 53, "forwarddelete": 117,
            "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        let fkeys: [String: CGKeyCode] = [
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        ]
        m.merge(fkeys) { a, _ in a }
        return m
    }()
}
