import SwiftUI
import AjazzKit

extension Color {
    /// Parse `#rrggbb`, falling back to `fallback`.
    init(hex: String?, fallback: Color) {
        guard var s = hex else { self = fallback; return }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { self = fallback; return }
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    /// `#rrggbb` for persisting back into the config.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02x%02x%02x",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }
}

extension LiveText.Source {
    var displayName: String {
        switch self {
        case .clock:   return "Clock"
        case .volume:  return "Volume %"
        case .audioOutput: return "Audio Output"
        case .cpu:     return "CPU %"
        case .battery: return "Battery %"
        case .shell:   return "Shell Output"
        }
    }
}

extension LiveText {
    /// A stand-in for the canvas; the real value only exists on the panel.
    var previewText: String {
        switch source {
        case .clock:
            let f = DateFormatter()
            f.dateFormat = (value?.isEmpty == false) ? value : "HH:mm"
            return f.string(from: Date())
        case .volume, .cpu, .battery: return "42%"
        case .audioOutput:            return AudioDevices.defaultOutput()?.name ?? "Speakers"
        case .shell:                  return "$_"
        }
    }
}

extension KeyTitle.Position {
    var alignment: Alignment {
        switch self {
        case .top:    return .top
        case .middle: return .center
        case .bottom: return .bottom
        }
    }
}

/// SF Symbol that suggests an action, used on the screenless controls.
func symbol(for action: Action?) -> String {
    guard let action else { return "circle.dashed" }
    switch action.type {
    case .launch:         return "app.badge"
    case .url:            return "safari"
    case .shell:          return "terminal"
    case .hotkey:         return "command"
    case .media:
        switch (action.value ?? "").lowercased() {
        case "next", "forward":          return "forward.end.fill"
        case "previous", "prev", "back": return "backward.end.fill"
        default:                         return "playpause.fill"
        }
    case .volume:
        switch (action.value ?? "").lowercased() {
        case "mute": return "speaker.slash.fill"
        case "down": return "speaker.wave.1.fill"
        default:     return "speaker.wave.3.fill"
        }
    case .brightness:     return "sun.max.fill"
    case .deckBrightness: return "light.panel.fill"
    case .scroll:         return "arrow.up.arrow.down"
    case .page:           return "square.stack"
    case .multi:          return "list.number"
    case .delay:          return "timer"
    case .task:           return TaskLibrary.task(action.value ?? "")?.symbol ?? "questionmark.circle"
    case .none:           return "circle.dashed"
    }
}

/// A visual replica of the panel. Every control is selectable, and pulses when
/// the matching physical control is touched.
struct DeviceCanvasView: View {
    @ObservedObject var store: ConfigStore
    /// The key a drag is hovering over.
    @State private var dropTarget: Int?

    private let tile: CGFloat = 74
    private static let dragPrefix = "ajazzdeck-key:"
    private let tileGap: CGFloat = 10

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 20) {
                keyGrid
                buttonRow
            }
            knobStack
        }
        .padding(26)
        .background(deviceBody)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Panel layout")
    }

    private var deviceBody: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(white: 0.20), Color(white: 0.13)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }

    // MARK: - LCD keys

    private var keyGrid: some View {
        Grid(horizontalSpacing: tileGap, verticalSpacing: tileGap) {
            ForEach(0..<store.profile.keyRows, id: \.self) { row in
                GridRow {
                    ForEach(0..<store.profile.keyColumns, id: \.self) { col in
                        let slot = row * store.profile.keyColumns + col + 1
                        keyTile(slot)
                    }
                }
            }
        }
    }

    private func keyTile(_ slot: Int) -> some View {
        let cfg = store.currentPage?.keys[String(slot)]
        let selected = store.selection == .key(slot)
        let active = store.activeControl == .key(slot)
        // A tap gesture rather than a Button, which would swallow the drag.
        return RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: cfg?.color, fallback: .black))
                .frame(width: tile, height: tile)
                .overlay { keyContents(cfg) }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(.white.opacity(active ? 0.30 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .opacity(dropTarget == slot ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.12), value: active)
                .contentShape(Rectangle())
                .onTapGesture { select(.key(slot)) }
                .draggable(Self.dragPrefix + String(slot))
                .dropDestination(for: String.self) { items, _ in
                    guard let item = items.first, item.hasPrefix(Self.dragPrefix),
                          let from = Int(item.dropFirst(Self.dragPrefix.count)) else { return false }
                    store.swapKeys(from, slot)
                    return true
                } isTargeted: { over in
                    if over { dropTarget = slot } else if dropTarget == slot { dropTarget = nil }
                }
                .contextMenu { controlMenu(.key(slot)) }
                .help("Key \(slot) — drag onto another key to swap")
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Key \(slot), \(cfg?.label ?? "unassigned")")
                .accessibilityAction { select(.key(slot)) }
    }

    /// Clicking a control ends any text editing, so ⌘C / ⌘V act on the control
    /// rather than on the last-focused field.
    private func select(_ control: ControlSelection) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        store.selection = control
    }

    @ViewBuilder
    private func controlMenu(_ control: ControlSelection) -> some View {
        Button("Copy") { store.copy(control) }
            .disabled(!store.hasContent(control))
        Button("Cut") { store.cut(control) }
            .disabled(!store.hasContent(control))
        Button("Paste") { store.paste(into: control) }
            .disabled(!store.canPaste(into: control))
        Divider()
        Button("Clear", role: .destructive) { store.clear(control) }
            .disabled(!store.hasContent(control))
    }

    /// Mirrors `DeckController.renderCurrentPage`: art first, title on top.
    private func keyContents(_ cfg: KeyConfig?) -> some View {
        let icon = cfg?.icon.flatMap { $0.isEmpty ? nil : NSImage(contentsOfFile: $0) }
        let symbol = cfg?.symbol.flatMap { KeySymbol($0).isValid ? $0 : nil }
        let hasArt = icon != nil || symbol != nil
        let text = cfg?.live.map(\.previewText) ?? cfg?.label ?? ""
        let label = (cfg?.showTitle ?? true) ? text : ""
        let position = cfg?.titlePosition ?? (hasArt ? .bottom : .middle)
        // Device sizes are in key pixels; the tile is drawn larger.
        let px = CGFloat(cfg?.titleSize ?? (hasArt || position != .middle ? 14 : 35)) * tile / 64
        let ink = Color(hex: cfg?.textColor, fallback: .white)
        return ZStack(alignment: position.alignment) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: tile - 8, height: tile - 8)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if let symbol {
                SymbolView(raw: symbol, size: 26, color: ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if label.isEmpty {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: px, weight: .bold))
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(hasArt ? 0.9 : 0), radius: 2)
                    .padding(5)
            }
        }
        .frame(width: tile - 8, height: tile - 8)
    }

    // MARK: - Screenless buttons

    private var buttonRow: some View {
        HStack(spacing: 22) {
            ForEach(Array(store.profile.buttons.enumerated()), id: \.offset) { i, spec in
                plainButton(i + 1, spec)
            }
        }
    }

    private func plainButton(_ n: Int, _ spec: ButtonSpec) -> some View {
        let cfg = store.currentPage?.buttons[String(n)]
        let selected = store.selection == .button(n)
        let active = store.activeControl == .button(n)
        return Button {
            select(.button(n))
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(white: 0.30), Color(white: 0.16)],
                                       center: .topLeading, startRadius: 1, endRadius: 44)
                    )
                    .frame(width: 42, height: 42)
                    .overlay { Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
                    .overlay {
                        Image(systemName: symbol(for: cfg?.action))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(cfg?.action == nil ? 0.25 : 0.85))
                    }
                    .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0) }
                    .overlay { Circle().fill(.white.opacity(active ? 0.30 : 0)) }
                    .animation(.easeOut(duration: 0.12), value: active)
                Text(spec.name)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .contextMenu { controlMenu(.button(n)) }
        .help("\(spec.name) button")
        .accessibilityLabel("\(spec.name) button")
    }

    // MARK: - Knobs

    private var knobStack: some View {
        VStack(spacing: 18) {
            if let first = store.profile.knobs.first {
                knob(1, first, diameter: 104)
            }
            HStack(spacing: 18) {
                ForEach(Array(store.profile.knobs.enumerated().dropFirst()), id: \.offset) { i, spec in
                    knob(i + 1, spec, diameter: 58)
                }
            }
        }
    }

    private func knob(_ n: Int, _ spec: KnobSpec, diameter: CGFloat) -> some View {
        let cfg = store.currentPage?.knobs[String(n)]
        let selected = store.selection == .knob(n)
        let active = store.activeControl == .knob(n)
        return Button {
            select(.knob(n))
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(colors: [Color(white: 0.34), Color(white: 0.15),
                                                     Color(white: 0.30), Color(white: 0.14)],
                                            center: .center)
                        )
                    Circle()
                        .strokeBorder(.black.opacity(0.55), lineWidth: diameter * 0.10)
                        .padding(diameter * 0.05)
                    Circle()
                        .fill(Color(white: 0.22))
                        .padding(diameter * 0.20)
                    Image(systemName: symbol(for: cfg?.action))
                        .font(.system(size: diameter * 0.22, weight: .medium))
                        .foregroundStyle(.white.opacity(cfg?.action == nil ? 0.25 : 0.85))
                }
                .frame(width: diameter, height: diameter)
                .overlay { Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0) }
                .overlay { Circle().fill(.white.opacity(active ? 0.28 : 0)) }
                .animation(.easeOut(duration: 0.12), value: active)

                Text(spec.name)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .buttonStyle(.plain)
        .contextMenu { controlMenu(.knob(n)) }
        .help("\(spec.name) knob")
        .accessibilityLabel("\(spec.name) knob")
    }
}
