import SwiftUI
import AjazzKit

/// Names for the icon picker.
enum IconCatalog {
    struct SFEntry {
        let name: String
        let keywords: [String]
    }

    /// The system's own SF Symbols catalogue (what the SF Symbols app lists),
    /// minus per-language duplicates such as `character.book.closed.ja`.
    // shortcut: these plists are undocumented; if a macOS update moves them the
    // SF tab is empty and names can still be typed into the Symbol field.
    static let sf: [SFEntry] = {
        let dir = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
        let order = NSArray(contentsOf: dir.appendingPathComponent("symbol_order.plist")) as? [String] ?? []
        let search = NSDictionary(contentsOf: dir.appendingPathComponent("symbol_search.plist"))
            as? [String: [String]] ?? [:]
        let all = Set(order)
        let languages: Set<Substring> = ["ar", "bn", "el", "gu", "he", "hi", "ja", "km", "kn", "ko", "ml",
                                         "mr", "my", "or", "pa", "rtl", "ru", "si", "ta", "te", "th", "zh"]
        return order.filter { name in
            guard let dot = name.lastIndex(of: "."), languages.contains(name[name.index(after: dot)...]) else {
                return true
            }
            return !all.contains(String(name[..<dot]))
        }
        .map { SFEntry(name: $0, keywords: search[$0] ?? []) }
    }()

    /// Material names, one per glyph (the codepoints file lists aliases too).
    static let material: [String] = {
        var seen: Set<UInt32> = []
        return MaterialSymbols.codepoints.keys.sorted().filter {
            seen.insert(MaterialSymbols.codepoints[$0]!).inserted
        }
    }()
}

/// Draws a key symbol from either icon set.
struct SymbolView: View {
    let raw: String
    let size: CGFloat
    var color: Color = .primary

    var body: some View {
        switch KeySymbol(raw) {
        case .sf(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
        case .material(let name, let filled):
            // Material glyphs sit smaller in their em box than SF Symbols do.
            Text(MaterialSymbols.character(name) ?? "?")
                .font(Font(MaterialSymbols.font(size: size * 1.25, filled: filled)))
                .foregroundStyle(color)
        }
    }
}

/// Symbol name field with a live preview and a button that opens the picker.
struct SymbolField: View {
    let title: String
    @Binding var symbol: String?
    var placeholder = "play.fill"
    @State private var picking = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(title, text: Binding(
                    get: { symbol ?? "" },
                    set: { symbol = $0.isEmpty ? nil : $0 }),
                    prompt: Text(placeholder))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                preview
                Button("Choose…") { picking = true }
            }
        }
        .sheet(isPresented: $picking) { IconPicker(symbol: $symbol) }
    }

    /// The icon when the name is valid, a warning when it isn't.
    @ViewBuilder
    private var preview: some View {
        if let symbol, !symbol.isEmpty {
            if KeySymbol(symbol).isValid {
                SymbolView(raw: symbol, size: 14).frame(width: 20)
            } else {
                Image(systemName: "questionmark.diamond")
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                    .help("No icon by that name. Use Choose… to browse.")
            }
        }
    }
}

/// Searchable grid of SF Symbols and Material Symbols.
struct IconPicker: View {
    enum IconSet: String, CaseIterable {
        case sf = "SF Symbols"
        case material = "Material"
    }

    @Binding var symbol: String?
    @Environment(\.dismiss) private var dismiss
    @State private var set: IconSet
    @State private var filled: Bool
    @State private var query = ""

    init(symbol: Binding<String?>) {
        _symbol = symbol
        // Open on the set the key already uses.
        if case .material(_, let f) = KeySymbol(symbol.wrappedValue ?? "") {
            _set = State(initialValue: .material)
            _filled = State(initialValue: f)
        } else {
            _set = State(initialValue: .sf)
            _filled = State(initialValue: false)
        }
    }

    var body: some View {
        let icons = results
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("Icon set", selection: $set) {
                    ForEach(IconSet.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                if set == .material {
                    Toggle("Filled", isOn: $filled)
                }
                Spacer()
                TextField("Search", text: $query, prompt: Text("Search icons"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: 6)], spacing: 6) {
                    ForEach(icons, id: \.self) { raw in
                        Button {
                            symbol = raw
                            dismiss()
                        } label: {
                            SymbolView(raw: raw, size: 20)
                                .frame(width: 50, height: 50)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(raw == symbol ? Color.accentColor.opacity(0.3)
                                                        : Color.primary.opacity(0.05)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(displayName(raw))
                        .accessibilityLabel(displayName(raw))
                    }
                }
                .padding(2)
            }
            .overlay {
                if icons.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            HStack {
                Text("\(icons.count) icons")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove Icon") {
                    symbol = nil
                    dismiss()
                }
                .disabled(symbol == nil)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 600, height: 500)
    }

    private var results: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        switch set {
        case .sf:
            return IconCatalog.sf
                .filter { q.isEmpty || $0.name.contains(q) || $0.keywords.contains { $0.contains(q) } }
                .map(\.name)
        case .material:
            let mq = q.replacingOccurrences(of: " ", with: "_")
            return IconCatalog.material
                .filter { mq.isEmpty || $0.contains(mq) }
                .map { KeySymbol.material($0, filled: filled).raw }
        }
    }

    private func displayName(_ raw: String) -> String {
        if case .material(let name, _) = KeySymbol(raw) { return name.replacingOccurrences(of: "_", with: " ") }
        return raw
    }
}
