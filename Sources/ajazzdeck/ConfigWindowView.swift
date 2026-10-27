import SwiftUI
import ServiceManagement
import AjazzKit

/// The configuration window: pages in the sidebar, a replica of the panel in
/// the middle, and an inspector for the selected control.
struct ConfigWindowView: View {
    @ObservedObject var store: ConfigStore
    @State private var showInspector = true
    @State private var renamingPage: Int?
    @State private var renameText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            Group {
                switch store.sidebar {
                case .page:    pageDetail
                case .general: GeneralSettingsView(store: store)
                }
            }
            .frame(minWidth: 520, minHeight: 420)
            .inspector(isPresented: Binding(
                get: { showInspector && isPageSelected },
                set: { showInspector = $0 })) {
                InspectorView(store: store)
            }
            .toolbar { toolbarContent }
        }
        .navigationTitle("Ajazz Deck")
        .navigationSubtitle(subtitle)
        .sheet(isPresented: Binding(
            get: { renamingPage != nil },
            set: { if !$0 { renamingPage = nil } })) {
            renameSheet
        }
    }

    private var subtitle: String {
        store.isConnected ? "\(store.profile.model) · Connected" : "Panel not found"
    }

    private var isPageSelected: Bool {
        if case .page = store.sidebar { return true }
        return false
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $store.sidebar) {
            Section("Pages") {
                ForEach(Array(store.config.pages.enumerated()), id: \.offset) { index, page in
                    Label(page.name, systemImage: "square.grid.3x2")
                        .tag(SidebarItem.page(index))
                        .contextMenu {
                            Button("Rename…") { beginRename(index) }
                            Button("Duplicate") { store.duplicatePage(index) }
                            Divider()
                            Button("Delete", role: .destructive) { store.removePage(index) }
                                .disabled(store.config.pages.count <= 1)
                        }
                }
            }
            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.general)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 2) {
                Button { store.addPage() } label: { Image(systemName: "plus") }
                    .help("Add a page")

                Button {
                    if case .page(let i) = store.sidebar { store.removePage(i) }
                } label: { Image(systemName: "minus") }
                    .help("Delete the selected page")
                    .disabled(!isPageSelected || store.config.pages.count <= 1)

                Button {
                    if case .page(let i) = store.sidebar { beginRename(i) }
                } label: { Image(systemName: "pencil") }
                    .help("Rename the selected page")
                    .disabled(!isPageSelected)

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private func beginRename(_ index: Int) {
        guard store.config.pages.indices.contains(index) else { return }
        renameText = store.config.pages[index].name
        renamingPage = index
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Page")
                .font(.headline)
            TextField("Name", text: $renameText)
                .frame(width: 260)
                .onSubmit { commitRename() }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { renamingPage = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { commitRename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func commitRename() {
        if let i = renamingPage { store.renamePage(i, to: renameText) }
        renamingPage = nil
    }

    // MARK: - Detail

    private var pageDetail: some View {
        VStack(spacing: 18) {
            if !store.hasAccessibilityPermission {
                permissionBanner
            }
            Spacer(minLength: 0)
            DeviceCanvasView(store: store)
            PageAppsRow(store: store)
            if store.selection == nil {
                Text("Select a control to change what it does.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Shown when macOS is refusing to let us post synthetic input, which
    /// disables keystroke, media, volume, brightness and scroll actions.
    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission needed")
                    .font(.callout.weight(.semibold))
                Text("Keystroke, media, volume, brightness and scroll actions will not fire. Opening apps, URLs and switching pages still work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings…") {
                store.requestAccessibility()
                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(u)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Menu {
                Slider(value: Binding(
                    get: { Double(store.config.brightness) },
                    set: { store.config.brightness = Int($0) }),
                    in: 0...100, step: 1) {
                    Text("Panel Backlight")
                }
                .frame(width: 200)
            } label: {
                Label("Backlight", systemImage: "sun.max")
            }
            .help("Panel backlight brightness")
        }

        ToolbarItem {
            Button {
                store.repaint()
            } label: {
                Label("Repaint", systemImage: "arrow.clockwise")
            }
            .help("Redraw every key on the panel")
            .disabled(!store.isConnected)
        }

        // The inspector only exists for a page, so only offer the toggle there.
        if isPageSelected {
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the inspector")
            }
        }
    }
}

/// Apps that bring the selected page up automatically while they are in front.
private struct PageAppsRow: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        let i = store.pageIndex
        let apps = store.config.pages.indices.contains(i) ? store.config.pages[i].apps : []
        // shortcut: one row, overflows with many apps; wrap it if that becomes common.
        HStack(spacing: 8) {
            Text("Switch to this page in:")
                .foregroundStyle(.secondary)
            ForEach(apps, id: \.self) { id in
                HStack(spacing: 4) {
                    Text(Self.name(of: id))
                    Button {
                        store.config.pages[i].apps.removeAll { $0 == id }
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .help("Stop switching to this page for \(Self.name(of: id))")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
            }
            Button(apps.isEmpty ? "Add App…" : "Add…") { addApp(to: i) }
        }
        .font(.callout)
    }

    private static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func addApp(to page: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier,
              store.config.pages.indices.contains(page) else { return }
        // An app links to one page, so the first match can't silently shadow another.
        for p in store.config.pages.indices { store.config.pages[p].apps.removeAll { $0 == id } }
        store.config.pages[page].apps.append(id)
    }
}

/// Device-wide settings and diagnostics.
struct GeneralSettingsView: View {
    @ObservedObject var store: ConfigStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmReset = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Panel") {
                LabeledContent("Backlight") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(store.config.brightness) },
                            set: { store.config.brightness = Int($0) }),
                            in: 0...100, step: 1)
                        Text("\(store.config.brightness)%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }

                LabeledContent("Hold delay") {
                    HStack {
                        Slider(value: $store.config.longPressSeconds, in: 0.2...2.0, step: 0.1)
                        Text("\(store.config.longPressSeconds, specifier: "%.1f") s")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Text("How long a control must be held before its “When Held” action fires.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Turn screens off after", selection: Binding(
                    get: { store.config.idleMinutes ?? 0 },
                    set: { store.config.idleMinutes = $0 == 0 ? nil : $0 })) {
                    Text("Never").tag(0)
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                Text("Any touch wakes the panel without running that control's action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    HStack(spacing: 8) {
                        Image(systemName: store.hasAccessibilityPermission
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(store.hasAccessibilityPermission ? .green : .orange)
                        Text(store.hasAccessibilityPermission ? "Granted" : "Not granted")
                        if !store.hasAccessibilityPermission {
                            Button("Open Settings…") { openAccessibility() }
                        }
                    }
                }
                Text("Required for keystrokes, media keys, volume and scrolling. Opening apps and URLs works without it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("If actions stop working after rebuilding the app, remove Ajazz Deck from the Accessibility list and add it again — macOS ties the permission to the exact binary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wanted in
                        do {
                            if wanted { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            NSLog("ajazzdeck: login item change failed: \(error)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Device") {
                LabeledContent("Model", value: store.profile.model)
                LabeledContent("Status", value: store.isConnected ? "Connected" : "Not found")
                if let fw = store.firmware {
                    LabeledContent("Firmware", value: fw)
                }
                if let sn = store.serialNumber {
                    LabeledContent("Serial", value: sn)
                }
                LabeledContent("Controls",
                               value: "6 keys · \(store.profile.buttons.count) buttons · \(store.profile.knobs.count) knobs")
            }

            Section("Configuration") {
                LabeledContent("File") {
                    Text(DeckConfig.defaultURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([DeckConfig.defaultURL])
                    }
                    Button("Open in Editor") {
                        NSWorkspace.shared.open(DeckConfig.defaultURL)
                    }
                    Spacer()
                    Button("Import…") { importConfig() }
                    Button("Export…") { exportConfig() }
                    Button("Reset to Defaults…", role: .destructive) { confirmReset = true }
                }
                Text("Edits made outside the app are picked up automatically. Importing keeps the replaced setup in config.before-import.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("Couldn't import that file", isPresented: Binding(
            get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog("Reset all pages to the defaults?",
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.resetToDefaults() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current pages and assignments will be replaced. This cannot be undone.")
        }
    }

    private func openAccessibility() {
        store.requestAccessibility()
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ajazzdeck-profile.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.config.save(to: url) } catch { importError = error.localizedDescription }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importConfig(from: url) } catch { importError = error.localizedDescription }
    }
}
