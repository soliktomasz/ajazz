import SwiftUI
import AppKit
import AjazzKit

/// Where an action is being attached, so we can offer only the choices that
/// make sense there (scrolling is meaningless on a key, for instance).
enum ActionContext {
    case press      // a key, a screenless button, or an encoder press
    case turn       // an encoder rotation
    case step       // one step of a multi-action

    /// The action menu's submenus: built-in actions first, then one per task
    /// group, each holding only what fits this kind of control.
    var menuGroups: [ActionMenuGroup] {
        let builtIn: [ActionMenuGroup]
        switch self {
        case .press, .step:
            builtIn = [
                ActionMenuGroup(name: "General", symbol: "square.grid.2x2",
                                choices: [.kind(.launch), .kind(.url), .kind(.shell), .kind(.hotkey)]),
                ActionMenuGroup(name: "Media & Display", symbol: "speaker.wave.2",
                                choices: [.kind(.media), .kind(.volume), .kind(.brightness), .kind(.deckBrightness)]),
                ActionMenuGroup(name: "Deck", symbol: "square.grid.3x2",
                                choices: [.kind(.page), .kind(self == .press ? .multi : .delay)]),
            ]
        case .turn:
            builtIn = [
                ActionMenuGroup(name: "General", symbol: "square.grid.2x2",
                                choices: [.kind(.scroll), .kind(.hotkey), .kind(.shell)]),
                ActionMenuGroup(name: "Media & Display", symbol: "speaker.wave.2",
                                choices: [.kind(.volume), .kind(.brightness), .kind(.deckBrightness)]),
            ]
        }
        let tasks = TaskLibrary.groups.map { group in
            ActionMenuGroup(name: group.name, symbol: group.symbol,
                            choices: group.tasks.filter { $0.isDial == (self == .turn) }.map { .task($0.id) })
        }
        return builtIn + tasks.filter { !$0.choices.isEmpty }
    }
}

/// One submenu of the action menu.
struct ActionMenuGroup: Identifiable {
    let name: String
    let symbol: String
    let choices: [ActionChoice]
    var id: String { name }
}

/// One entry in the action menu: a built-in kind or a library task.
enum ActionChoice: Hashable {
    case kind(Action.Kind)
    case task(String)

    init?(_ action: Action?) {
        guard let action, action.type != .none else { return nil }
        self = action.type == .task ? .task(action.value ?? "") : .kind(action.type)
    }

    var name: String {
        switch self {
        case .kind(let k):  return k.displayName
        case .task(let id): return TaskLibrary.task(id)?.name ?? "Unknown Task"
        }
    }

    var symbolName: String {
        switch self {
        case .kind(let k):  return symbol(for: Action(type: k, value: ActionEditor.defaultValue(for: k)))
        case .task(let id): return TaskLibrary.task(id)?.symbol ?? "questionmark.circle"
        }
    }

    func makeAction() -> Action {
        switch self {
        case .kind(let k):
            return Action(type: k, value: ActionEditor.defaultValue(for: k), steps: k == .multi ? [] : nil)
        case .task(let id):
            let params = TaskLibrary.task(id)?.parameters ?? []
            return Action(type: .task, value: id, args: params.isEmpty ? nil : Self.defaults(for: params))
        }
    }

    /// Sensible starting settings: for outputs, the one playing now first, then
    /// the others, so "Toggle Output" works before anything is picked.
    private static func defaults(for params: [TaskParameter]) -> [String] {
        let current = AudioDevices.defaultOutput()?.uid
        let outputs = AudioDevices.outputs().map(\.uid)
        let ordered = (current.map { [$0] } ?? []) + outputs.filter { $0 != current }
        return params.indices.map { i in
            switch params[i].kind {
            case .audioOutput: return ordered.indices.contains(i) ? ordered[i] : ""
            }
        }
    }
}

extension Action.Kind {
    var displayName: String {
        switch self {
        case .none:           return "Nothing"
        case .launch:         return "Open App"
        case .url:            return "Open URL"
        case .shell:          return "Run Shell Command"
        case .hotkey:         return "Send Keystroke"
        case .media:          return "Media Control"
        case .volume:         return "System Volume"
        case .brightness:     return "Display Brightness"
        case .deckBrightness: return "Panel Backlight"
        case .scroll:         return "Scroll"
        case .page:           return "Switch Page"
        case .multi:          return "Multi-Action"
        case .delay:          return "Wait"
        case .task:           return "Task"
        }
    }
}

/// Editor for a single optional `Action`.
struct ActionEditor: View {
    @Binding var action: Action?
    let context: ActionContext
    /// Page names, for the "Switch Page" target picker.
    let pageNames: [String]

    var body: some View {
        let current = ActionChoice(action)
        LabeledContent("Action") {
            Menu {
                Button { action = nil } label: { Label("Nothing", systemImage: "circle.dashed") }
                Divider()
                ForEach(context.menuGroups) { group in
                    Menu {
                        ForEach(group.choices, id: \.self) { choice in
                            Button {
                                // Re-picking the current entry keeps its settings.
                                if choice != current { action = choice.makeAction() }
                            } label: {
                                Label(choice.name, systemImage: choice.symbolName)
                            }
                        }
                    } label: {
                        Label(group.name, systemImage: group.symbol)
                    }
                }
            } label: {
                Label(current?.name ?? "Nothing", systemImage: current?.symbolName ?? "circle.dashed")
            }
            .fixedSize()
        }

        if let current = action {
            valueEditor(for: current)
        }
    }

    @ViewBuilder
    private func valueEditor(for current: Action) -> some View {
        switch current.type {
        case .launch:
            LabeledContent("Application") {
                HStack(spacing: 8) {
                    TextField("Application", text: valueBinding, prompt: Text("Finder"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                    Button("Choose…") { chooseApplication() }
                }
            }

        case .url:
            TextField("URL", text: valueBinding, prompt: Text("https://example.com"))

        case .shell:
            TextField("Command", text: valueBinding, prompt: Text("say hello"))
                .font(.system(.body, design: .monospaced))
            Text("Runs with /bin/sh.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .hotkey where context == .turn:
            TextField("Clockwise", text: valueBinding, prompt: Text("cmd+shift+]"))
            TextField("Counter-clockwise", text: argBinding(0), prompt: Text("cmd+shift+["))
            Text("Sent once per click of the knob. Modifiers: cmd, shift, alt, ctrl, fn.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .hotkey:
            TextField("Keystroke", text: valueBinding, prompt: Text("cmd+shift+4"))
            Text("Modifiers: cmd, shift, alt, ctrl, fn.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .media:
            Picker("Control", selection: valueBinding) {
                Text("Play / Pause").tag("playpause")
                Text("Next Track").tag("next")
                Text("Previous Track").tag("previous")
            }

        case .volume where context != .turn:
            Picker("Change", selection: valueBinding) {
                Text("Volume Up").tag("up")
                Text("Volume Down").tag("down")
                Text("Mute").tag("mute")
            }

        case .brightness where context != .turn:
            Picker("Change", selection: valueBinding) {
                Text("Brighter").tag("up")
                Text("Dimmer").tag("down")
            }

        case .page:
            Picker("Target", selection: valueBinding) {
                Text("Next Page").tag("next")
                Text("Previous Page").tag("prev")
                Divider()
                ForEach(pageNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

        case .multi:
            let steps = current.steps ?? []
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(i + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    VStack {
                        // AnyView breaks the recursive opaque type.
                        AnyView(ActionEditor(action: stepBinding(i), context: .step,
                                             pageNames: pageNames))
                    }
                    Button {
                        action?.steps?.remove(at: i)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove step")
                }
            }
            Button("Add Step") { action?.steps = steps + [Action(type: .hotkey)] }

        case .delay:
            let seconds = Double(current.value ?? "") ?? 0.5
            Stepper(value: Binding(
                get: { seconds },
                set: { action?.value = String(format: "%.1f", $0) }),
                in: 0.1...10, step: 0.1) {
                LabeledContent("Wait") { Text("\(seconds, specifier: "%.1f") s") }
            }

        case .task:
            let task = TaskLibrary.task(current.value ?? "")
            ForEach(Array((task?.parameters ?? []).enumerated()), id: \.offset) { i, param in
                parameterEditor(param, binding: argBinding(i))
            }
            if let note = task?.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func parameterEditor(_ param: TaskParameter, binding: Binding<String>) -> some View {
        switch param.kind {
        case .audioOutput:
            let outputs = AudioDevices.outputs()
            Picker(param.label, selection: binding) {
                ForEach(outputs, id: \.uid) { Text($0.name).tag($0.uid) }
                // Keep a chosen device listed while it's unplugged (headphones).
                if !binding.wrappedValue.isEmpty, !outputs.contains(where: { $0.uid == binding.wrappedValue }) {
                    Text("Not connected").tag(binding.wrappedValue)
                }
                if binding.wrappedValue.isEmpty { Text("Choose…").tag("") }
            }
        }
    }

    /// A task setting by position, padding `args` as needed.
    private func argBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { action?.args.flatMap { $0.indices.contains(i) ? $0[i] : nil } ?? "" },
            set: { new in
                var args = action?.args ?? []
                while args.count <= i { args.append("") }
                args[i] = new
                action?.args = args
            })
    }

    /// Steps are edited by index; a stale index after a removal reads as empty.
    private func stepBinding(_ i: Int) -> Binding<Action?> {
        Binding(
            get: { action?.steps.flatMap { $0.indices.contains(i) ? $0[i] : nil } },
            set: { new in
                guard action?.steps?.indices.contains(i) == true else { return }
                action?.steps?[i] = new ?? Action(type: .none)
            })
    }

    private var valueBinding: Binding<String> {
        Binding(
            get: { action?.value ?? "" },
            set: { action?.value = $0 })
    }

    static func defaultValue(for kind: Action.Kind) -> String? {
        switch kind {
        case .media:      return "playpause"
        case .volume:     return "up"
        case .brightness: return "up"
        case .page:       return "next"
        case .delay:      return "0.5"
        default:          return nil
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Store the plain name where we can; it survives the app moving.
        action?.value = url.deletingPathExtension().lastPathComponent
    }
}
