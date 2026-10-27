import Foundation

/// What a control does when you use it.
public struct Action: Codable, Equatable {
    public enum Kind: String, Codable {
        /// Launch or focus an application by name, bundle id, or path.
        case launch
        /// Open a URL in the default handler.
        case url
        /// Run a shell command via `/bin/sh -c`.
        case shell
        /// Synthesise a keystroke, e.g. "cmd+shift+4". On a knob, `value` fires per
        /// clockwise detent and `args[0]` per counter-clockwise one.
        case hotkey
        /// Media transport: play, next, previous.
        case media
        /// System output volume. As a key: step up/down/mute. As a knob: relative.
        case volume
        /// Display brightness. As a knob: relative.
        case brightness
        /// The panel's own backlight. As a knob: relative.
        case deckBrightness
        /// Scroll the focused view. Knob only.
        case scroll
        /// Switch pages: "next", "prev", or a page name.
        case page
        /// Run `steps` in order.
        case multi
        /// Inside a multi-action: wait `value` seconds before the next step.
        case delay
        /// A ready-made operation from `TaskLibrary`; `value` is its id.
        case task
        /// Do nothing (useful for a purely decorative key).
        case none
    }

    public var type: Kind
    /// Meaning depends on `type`: app name, URL, command, key combo, etc.
    public var value: String?
    /// The actions a `multi` runs, in order.
    public var steps: [Action]?
    /// A task's settings, in the order its `TaskSpec.parameters` lists them.
    public var args: [String]?

    public init(type: Kind, value: String? = nil, steps: [Action]? = nil, args: [String]? = nil) {
        self.type = type
        self.value = value
        self.steps = steps
        self.args = args
    }
}

/// One key's appearance and behaviour.
public struct KeyConfig: Codable, Equatable {
    /// Text drawn on the key. Omit if you supply an icon.
    public var label: String?
    /// Path to a PNG/JPEG/PDF to draw on the key. Overrides `label` art.
    public var icon: String?
    /// SF Symbol name, e.g. "play.fill", drawn in `textColor`. Overrides `label`
    /// art; `icon` overrides it.
    public var symbol: String?
    /// Background colour, `#rrggbb`. Defaults to black.
    public var color: String?
    /// Text colour, `#rrggbb`. Defaults to white.
    public var textColor: String?
    /// What pressing the key does.
    public var action: Action?
    /// What a long press does, if anything.
    public var longPressAction: Action?
    /// Whether `label` is drawn. Defaults to true.
    public var showTitle: Bool?
    /// Where `label` sits. Defaults to middle on a plain key, bottom over art.
    public var titlePosition: KeyTitle.Position?
    /// Label font size in key pixels; nil fits it automatically.
    public var titleSize: Int?
    /// Makes this a toggle key: each press runs the current state's action, then
    /// flips to the other state.
    public var toggle: ToggleState?
    /// Text that replaces `label` and keeps itself up to date.
    public var live: LiveText?

    public init(label: String? = nil, icon: String? = nil, symbol: String? = nil,
                color: String? = nil, textColor: String? = nil, action: Action? = nil,
                longPressAction: Action? = nil) {
        self.label = label; self.icon = icon; self.symbol = symbol; self.color = color
        self.textColor = textColor; self.action = action
        self.longPressAction = longPressAction
    }
}

/// A self-updating value shown in place of a key's label.
public struct LiveText: Codable, Equatable {
    public enum Source: String, Codable, CaseIterable {
        case clock, volume, audioOutput, cpu, battery, shell
    }

    public var source: Source
    /// Clock: a date format such as "HH:mm". Shell: the command, whose first
    /// output line is shown.
    public var value: String?

    public init(source: Source, value: String? = nil) {
        self.source = source; self.value = value
    }
}

/// A toggle key's second state. Unset fields keep the first state's value.
public struct ToggleState: Codable, Equatable {
    public var label: String?
    public var icon: String?
    public var symbol: String?
    public var color: String?
    public var textColor: String?
    public var action: Action?

    public init(label: String? = nil, symbol: String? = nil, action: Action? = nil) {
        self.label = label; self.symbol = symbol; self.action = action
    }
}

extension KeyConfig {
    /// This key as it looks and acts in its second state.
    public var toggled: KeyConfig {
        guard let t = toggle else { return self }
        var k = self
        k.label = t.label ?? label
        // Either kind of art replaces both, or the first state's icon would win.
        if t.icon != nil || t.symbol != nil { k.icon = t.icon; k.symbol = t.symbol }
        k.color = t.color ?? color
        k.textColor = t.textColor ?? textColor
        k.action = t.action ?? action
        return k
    }
}

/// A screenless push button's behaviour.
public struct ButtonConfig: Codable, Equatable {
    public var action: Action?
    public var longPressAction: Action?

    public init(action: Action? = nil, longPressAction: Action? = nil) {
        self.action = action; self.longPressAction = longPressAction
    }
}

/// One encoder's behaviour.
public struct KnobConfig: Codable, Equatable {
    /// What turning the knob does. `delta` is applied for relative actions.
    public var action: Action?
    /// How much one detent counts for. Defaults to 1.
    public var step: Int?
    /// What pressing the encoder inward does, on units whose knobs click.
    public var pressAction: Action?

    public init(action: Action? = nil, step: Int? = nil, pressAction: Action? = nil) {
        self.action = action; self.step = step; self.pressAction = pressAction
    }
}

/// A full set of control assignments.
public struct Page: Codable, Equatable {
    public var name: String
    /// LCD keys, keyed by slot number as a string, e.g. "1"..."6".
    public var keys: [String: KeyConfig]
    /// Screenless buttons, keyed by position as a string, e.g. "1"..."3".
    public var buttons: [String: ButtonConfig]
    /// Encoders, keyed by position as a string, e.g. "1"..."3".
    public var knobs: [String: KnobConfig]
    /// Bundle identifiers that bring this page up while they are frontmost.
    public var apps: [String]

    public init(name: String, keys: [String: KeyConfig] = [:],
                buttons: [String: ButtonConfig] = [:],
                knobs: [String: KnobConfig] = [:], apps: [String] = []) {
        self.name = name; self.keys = keys; self.buttons = buttons; self.knobs = knobs
        self.apps = apps
    }

    // Hand-written so configs written before screenless buttons or per-app
    // pages were supported still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name    = try c.decode(String.self, forKey: .name)
        keys    = try c.decodeIfPresent([String: KeyConfig].self, forKey: .keys) ?? [:]
        buttons = try c.decodeIfPresent([String: ButtonConfig].self, forKey: .buttons) ?? [:]
        knobs   = try c.decodeIfPresent([String: KnobConfig].self, forKey: .knobs) ?? [:]
        apps    = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
    }
}

extension Page {
    /// Exchange two LCD keys; moving onto an empty slot is a swap with nothing.
    public mutating func swapKeys(_ a: Int, _ b: Int) {
        let first = keys[String(a)]
        keys[String(a)] = keys[String(b)]
        keys[String(b)] = first
    }
}

/// The whole user configuration.
public struct DeckConfig: Codable, Equatable {
    /// Panel backlight, 0...100.
    public var brightness: Int
    /// Seconds a press must be held to count as a long press.
    public var longPressSeconds: Double
    /// Turn the key screens off after this many minutes without input; nil or 0
    /// leaves them on.
    public var idleMinutes: Int?
    public var pages: [Page]

    public init(brightness: Int = 90, longPressSeconds: Double = 0.5, pages: [Page]) {
        self.brightness = brightness
        self.longPressSeconds = longPressSeconds
        self.pages = pages
    }

    /// `~/.config/ajazzdeck/config.json`
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ajazzdeck/config.json")
    }

    public static func load(from url: URL = defaultURL) throws -> DeckConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DeckConfig.self, from: data)
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// A working starter configuration, so a first run does something useful.
    public static var starter: DeckConfig {
        DeckConfig(brightness: 90, longPressSeconds: 0.5, pages: [
            Page(name: "Main",
                 keys: [
                    "1": KeyConfig(label: "Finder", color: "#0a84ff",
                                   action: Action(type: .launch, value: "Finder")),
                    "2": KeyConfig(label: "Term", color: "#2c2c2e",
                                   action: Action(type: .launch, value: "Terminal")),
                    "3": KeyConfig(label: "Shot", color: "#ff9f0a",
                                   action: Action(type: .hotkey, value: "cmd+shift+4")),
                    "4": KeyConfig(label: "Play", color: "#30d158",
                                   action: Action(type: .media, value: "playpause")),
                    "5": KeyConfig(label: "Mute", color: "#ff453a",
                                   action: Action(type: .volume, value: "mute")),
                    "6": KeyConfig(label: "Page", color: "#5e5ce6",
                                   action: Action(type: .page, value: "next")),
                 ],
                 buttons: [
                    "1": ButtonConfig(action: Action(type: .media, value: "previous")),
                    "2": ButtonConfig(action: Action(type: .media, value: "playpause")),
                    "3": ButtonConfig(action: Action(type: .media, value: "next")),
                 ],
                 knobs: [
                    "1": KnobConfig(action: Action(type: .volume), step: 1,
                                    pressAction: Action(type: .volume, value: "mute")),
                    "2": KnobConfig(action: Action(type: .scroll), step: 3),
                    "3": KnobConfig(action: Action(type: .brightness), step: 1),
                 ]),
            Page(name: "Media",
                 keys: [
                    "1": KeyConfig(label: "<<", color: "#2c2c2e",
                                   action: Action(type: .media, value: "previous")),
                    "2": KeyConfig(label: ">||", color: "#30d158",
                                   action: Action(type: .media, value: "playpause")),
                    "3": KeyConfig(label: ">>", color: "#2c2c2e",
                                   action: Action(type: .media, value: "next")),
                    "4": KeyConfig(label: "Vol-", color: "#3a3a3c",
                                   action: Action(type: .volume, value: "down")),
                    "5": KeyConfig(label: "Vol+", color: "#3a3a3c",
                                   action: Action(type: .volume, value: "up")),
                    "6": KeyConfig(label: "Back", color: "#5e5ce6",
                                   action: Action(type: .page, value: "prev")),
                 ],
                 buttons: [
                    "1": ButtonConfig(action: Action(type: .volume, value: "down")),
                    "2": ButtonConfig(action: Action(type: .volume, value: "mute")),
                    "3": ButtonConfig(action: Action(type: .volume, value: "up")),
                 ],
                 knobs: [
                    "1": KnobConfig(action: Action(type: .volume), step: 1),
                    "2": KnobConfig(action: Action(type: .deckBrightness), step: 5),
                    "3": KnobConfig(action: Action(type: .scroll), step: 3),
                 ]),
        ])
    }
}
