import SwiftUI
import AppKit
import AjazzKit

/// Editing surface for whichever control is selected on the canvas.
struct InspectorView: View {
    @ObservedObject var store: ConfigStore

    private var pageNames: [String] { store.config.pages.map(\.name) }

    var body: some View {
        Form {
            switch store.selection {
            case .key(let slot):    keyEditor(slot)
            case .button(let n):    buttonEditor(n)
            case .knob(let n):      knobEditor(n)
            case nil:               emptySelection
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
    }

    private var emptySelection: some View {
        ContentUnavailableView("No Control Selected",
                               systemImage: "hand.tap",
                               description: Text("Select a key, button, or knob on the panel."))
    }

    // MARK: - LCD key

    @ViewBuilder
    private func keyEditor(_ slot: Int) -> some View {
        let binding = store.keyBinding(slot)

        Section("Key \(slot)") {
            TextField("Label", text: Binding(
                get: { binding.wrappedValue.label ?? "" },
                set: { binding.wrappedValue.label = $0.isEmpty ? nil : $0 }),
                prompt: Text("Shown on the key"))

            LabeledContent("Icon") {
                HStack(spacing: 8) {
                    Text(iconName(binding.wrappedValue.icon))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if binding.wrappedValue.icon != nil {
                        Button {
                            binding.wrappedValue.icon = nil
                        } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                            .help("Remove icon")
                    }
                    Button("Choose…") { chooseIcon(into: binding) }
                }
            }

            SymbolField(title: "Symbol", symbol: binding.symbol)

            ColorPicker("Background", selection: Binding(
                get: { Color(hex: binding.wrappedValue.color, fallback: .black) },
                set: { binding.wrappedValue.color = $0.hexString }),
                supportsOpacity: false)

            ColorPicker("Text", selection: Binding(
                get: { Color(hex: binding.wrappedValue.textColor, fallback: .white) },
                set: { binding.wrappedValue.textColor = $0.hexString }),
                supportsOpacity: false)
        }

        Section("Live Text") {
            Picker("Show", selection: Binding(
                get: { binding.wrappedValue.live?.source },
                set: { binding.wrappedValue.live = $0.map { LiveText(source: $0) } })) {
                Text("Label").tag(LiveText.Source?.none)
                ForEach(LiveText.Source.allCases, id: \.self) { s in
                    Text(s.displayName).tag(Optional(s))
                }
            }
            if let live = binding.wrappedValue.live {
                let value = optionalText(Binding(
                    get: { binding.wrappedValue.live?.value },
                    set: { binding.wrappedValue.live?.value = $0 }))
                switch live.source {
                case .clock:
                    TextField("Format", text: value, prompt: Text("HH:mm"))
                    Text("Unicode date format, e.g. HH:mm:ss or EEE d.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .shell:
                    TextField("Command", text: value, prompt: Text("date +%S"))
                        .font(.system(.body, design: .monospaced))
                    Text("Runs with /bin/sh every 5 s; the first line of output is shown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
        }

        if !(binding.wrappedValue.label ?? "").isEmpty || binding.wrappedValue.live != nil {
            Section("Title") {
                Toggle("Show on key", isOn: Binding(
                    get: { binding.wrappedValue.showTitle ?? true },
                    set: { binding.wrappedValue.showTitle = $0 ? nil : false }))
                Picker("Position", selection: binding.titlePosition) {
                    Text("Automatic").tag(KeyTitle.Position?.none)
                    ForEach(KeyTitle.Position.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized).tag(Optional(p))
                    }
                }
                Picker("Size", selection: binding.titleSize) {
                    Text("Automatic").tag(Int?.none)
                    ForEach([8, 10, 12, 14, 16, 20, 24, 32], id: \.self) { n in
                        Text("\(n) px").tag(Optional(n))
                    }
                }
            }
        }

        Section("When Pressed") {
            ActionEditor(action: binding.action, context: .press, pageNames: pageNames)
        }

        Section("Toggle") {
            Toggle("Two states", isOn: Binding(
                get: { binding.wrappedValue.toggle != nil },
                set: { binding.wrappedValue.toggle = $0 ? ToggleState() : nil }))
            if binding.wrappedValue.toggle != nil {
                let second = Binding(
                    get: { binding.wrappedValue.toggle ?? ToggleState() },
                    set: { binding.wrappedValue.toggle = $0 })
                TextField("Label", text: optionalText(second.label),
                          prompt: Text(binding.wrappedValue.label ?? "Same as first"))
                SymbolField(title: "Symbol", symbol: second.symbol,
                            placeholder: binding.wrappedValue.symbol ?? "Same as first")
                ColorPicker("Background", selection: Binding(
                    get: { Color(hex: second.wrappedValue.color ?? binding.wrappedValue.color,
                                 fallback: .black) },
                    set: { second.wrappedValue.color = $0.hexString }),
                    supportsOpacity: false)
                ActionEditor(action: second.action, context: .press, pageNames: pageNames)
                Text("Each press runs the current state's action, then flips. Empty fields reuse the first state's.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("When Held") {
            ActionEditor(action: binding.longPressAction, context: .press, pageNames: pageNames)
            if binding.wrappedValue.longPressAction != nil {
                LabeledContent("Hold for") {
                    Text("\(store.config.longPressSeconds, specifier: "%.1f") s")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Edits an optional string, storing nil rather than "".
    private func optionalText(_ b: Binding<String?>) -> Binding<String> {
        Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func iconName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "None" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseIcon(into binding: Binding<KeyConfig>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        binding.wrappedValue.icon = url.path
    }

    // MARK: - Screenless button

    @ViewBuilder
    private func buttonEditor(_ n: Int) -> some View {
        let binding = store.buttonBinding(n)
        let name = store.profile.buttons.indices.contains(n - 1)
            ? store.profile.buttons[n - 1].name : "Button \(n)"

        Section("\(name) Button") {
            Text("This button has no screen, so it shows no label on the device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("When Pressed") {
            ActionEditor(action: binding.action, context: .press, pageNames: pageNames)
        }

        Section("When Held") {
            ActionEditor(action: binding.longPressAction, context: .press, pageNames: pageNames)
        }
    }

    // MARK: - Knob

    @ViewBuilder
    private func knobEditor(_ n: Int) -> some View {
        let binding = store.knobBinding(n)
        let spec = store.profile.knobs.indices.contains(n - 1) ? store.profile.knobs[n - 1] : nil

        Section("\(spec?.name ?? "Knob \(n)") Knob") {
            Text("Clockwise increases, counter-clockwise decreases.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("When Turned") {
            ActionEditor(action: binding.action, context: .turn, pageNames: pageNames)
            if binding.wrappedValue.action != nil {
                Stepper(value: Binding(
                    get: { binding.wrappedValue.step ?? 1 },
                    set: { binding.wrappedValue.step = max(1, $0) }),
                    in: 1...20) {
                    LabeledContent("Step per click") {
                        Text("\(binding.wrappedValue.step ?? 1)")
                    }
                }
            }
        }

        if spec?.press != nil {
            Section("When Pressed") {
                ActionEditor(action: binding.pressAction, context: .press, pageNames: pageNames)
            }
        }
    }
}
