import Foundation

/// A ready-made operation a control can run (`Action.Kind.task`, with the task's
/// `id` as the action's value). Tasks come in groups; add a group to
/// `TaskLibrary.groups` and the configuration UI lists it as its own submenu.
public struct TaskSpec {
    public enum Effect {
        /// A keystroke, in `Action.hotkey` syntax.
        case hotkey(String)
        /// A `/bin/sh` command.
        case shell(String)
        /// An app by path, bundle id, or name.
        case open(String)
        /// An AppleScript, run through `osascript`.
        case appleScript(String)
        /// Knob only: one keystroke per detent, clockwise or counter-clockwise.
        case dial(clockwise: String, counterClockwise: String)
        /// Code of our own, given the action's `args`.
        case custom(([String]) -> Void)
        /// Knob only: code of our own, given `args` and the signed detent count.
        case customDial(([String], Int) -> Void)
    }

    /// Unique and stable, `group.name`; it is what the config stores.
    public let id: String
    public let name: String
    /// SF Symbol shown in menus and on screenless controls.
    public let symbol: String
    public let effect: Effect
    /// Anything the user should know, e.g. that it follows a system shortcut.
    public let note: String?
    /// Settings the user picks in the inspector, stored in `Action.args`.
    public let parameters: [TaskParameter]

    public init(_ id: String, _ name: String, symbol: String, _ effect: Effect, note: String? = nil,
                parameters: [TaskParameter] = []) {
        self.id = id; self.name = name; self.symbol = symbol; self.effect = effect; self.note = note
        self.parameters = parameters
    }

    /// Dial tasks belong on knob rotation; everything else on presses.
    public var isDial: Bool {
        switch effect {
        case .dial, .customDial: return true
        default:                 return false
        }
    }
}

/// One setting a task needs. Each kind gets its own editor in the inspector.
public struct TaskParameter {
    public enum Kind {
        /// A sound output's UID, see `AudioDevices`.
        case audioOutput
    }

    public let label: String
    public let kind: Kind

    public init(_ label: String, _ kind: Kind) {
        self.label = label; self.kind = kind
    }
}

public struct TaskGroup {
    public let id: String
    public let name: String
    public let symbol: String
    public let tasks: [TaskSpec]
}

public enum TaskLibrary {
    /// Every group, in menu order.
    public static let groups: [TaskGroup] = [macOS, audio]

    private static let byID: [String: TaskSpec] =
        Dictionary(uniqueKeysWithValues: groups.flatMap(\.tasks).map { ($0.id, $0) })

    public static func task(_ id: String) -> TaskSpec? { byID[id] }

    // MARK: - Audio

    static let audio = TaskGroup(id: "audio", name: "Audio", symbol: "hifispeaker.2", tasks: [
        TaskSpec("audio.toggleOutput", "Toggle Output", symbol: "arrow.left.arrow.right.circle",
                 .custom { args in
                     guard args.count >= 2, !AudioDevices.toggleOutput(args[0], args[1]) else { return }
                     NSLog("ajazzdeck: toggle output: target not connected")
                 },
                 note: "Each press switches to the other one. Pair it with the Audio Output live text to show which is on.",
                 parameters: [TaskParameter("First", .audioOutput), TaskParameter("Second", .audioOutput)]),
        TaskSpec("audio.setOutput", "Switch to Output", symbol: "hifispeaker",
                 .custom { args in
                     guard let uid = args.first, !AudioDevices.setDefaultOutput(uid: uid) else { return }
                     NSLog("ajazzdeck: switch output: device not connected")
                 },
                 parameters: [TaskParameter("Output", .audioOutput)]),
        TaskSpec("audio.cycleOutputs", "Cycle Outputs", symbol: "hifispeaker.2",
                 .customDial { _, delta in AudioDevices.cycleOutput(by: delta) }),
    ])

    // MARK: - macOS

    private static let shortcutNote = "Uses the default shortcut in System Settings ▸ Keyboard ▸ Keyboard Shortcuts."

    static let macOS = TaskGroup(id: "macos", name: "macOS", symbol: "apple.logo", tasks: [
        TaskSpec("macos.lockScreen", "Lock Screen", symbol: "lock.fill", .hotkey("ctrl+cmd+q")),
        TaskSpec("macos.sleepDisplay", "Sleep Display", symbol: "display", .shell("pmset displaysleepnow")),
        TaskSpec("macos.sleep", "Sleep", symbol: "moon.zzz.fill", .shell("pmset sleepnow")),
        TaskSpec("macos.screenSaver", "Start Screen Saver", symbol: "sparkles.tv",
                 .open("/System/Library/CoreServices/ScreenSaverEngine.app")),
        TaskSpec("macos.missionControl", "Mission Control", symbol: "rectangle.3.group",
                 .hotkey("ctrl+up"), note: shortcutNote),
        TaskSpec("macos.appWindows", "App Windows", symbol: "rectangle.stack",
                 .hotkey("ctrl+down"), note: shortcutNote),
        TaskSpec("macos.showDesktop", "Show Desktop", symbol: "menubar.dock.rectangle",
                 .hotkey("f11"), note: shortcutNote),
        TaskSpec("macos.spotlight", "Spotlight", symbol: "magnifyingglass", .hotkey("cmd+space")),
        TaskSpec("macos.siri", "Siri", symbol: "mic.circle.fill", .open("/System/Applications/Siri.app")),
        TaskSpec("macos.screenshot", "Screenshot…", symbol: "camera.viewfinder", .hotkey("cmd+shift+5")),
        TaskSpec("macos.emoji", "Emoji & Symbols", symbol: "face.smiling", .hotkey("ctrl+cmd+space")),
        TaskSpec("macos.forceQuit", "Force Quit…", symbol: "xmark.octagon", .hotkey("cmd+alt+escape")),
        TaskSpec("macos.darkMode", "Toggle Dark Mode", symbol: "circle.lefthalf.filled",
                 .appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"),
                 note: "macOS asks once for permission to control System Events."),
        TaskSpec("macos.minimize", "Minimize Window", symbol: "minus.square", .hotkey("cmd+m")),
        TaskSpec("macos.fullScreen", "Toggle Full Screen", symbol: "arrow.up.left.and.arrow.down.right",
                 .hotkey("ctrl+cmd+f")),
        TaskSpec("macos.hideApp", "Hide App", symbol: "eye.slash", .hotkey("cmd+h")),
        TaskSpec("macos.ejectAll", "Eject All Disks", symbol: "eject.fill",
                 .appleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)"),
                 note: "macOS asks once for permission to control Finder."),
        TaskSpec("macos.spaces", "Switch Desktops", symbol: "rectangle.split.3x1",
                 .dial(clockwise: "ctrl+right", counterClockwise: "ctrl+left"), note: shortcutNote),
        TaskSpec("macos.tabs", "Switch Tabs", symbol: "square.on.square",
                 .dial(clockwise: "cmd+shift+]", counterClockwise: "cmd+shift+[")),
        TaskSpec("macos.zoom", "Zoom In / Out", symbol: "plus.magnifyingglass",
                 .dial(clockwise: "cmd+=", counterClockwise: "cmd+-")),
        TaskSpec("macos.undoRedo", "Undo / Redo", symbol: "arrow.uturn.backward",
                 .dial(clockwise: "cmd+shift+z", counterClockwise: "cmd+z")),
    ])
}
