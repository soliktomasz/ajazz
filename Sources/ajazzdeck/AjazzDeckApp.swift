import AppKit
import SwiftUI
import AjazzKit

/// Menu-bar host plus configuration window.
///
/// The app runs as an accessory (no Dock icon) while only the menu bar item is
/// showing, and promotes itself to a regular app while the configuration window
/// is open so that window and menu commands behave normally.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem!
    private var store: ConfigStore!
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one instance may drive the panel. A second copy would open the
        // same HID interface and both would react to every control, which looks
        // like erratic or missing actions.
        if let bundleID = Bundle.main.bundleIdentifier {
            let mine = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != mine }
            if let existing = others.first {
                existing.activate(options: [.activateAllWindows])
                NSApp.terminate(nil)
                return
            }
        }

        // Before the store exists: its controller paints the panel straight away.
        // The .app carries the font; the source tree covers `swift run`.
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("MaterialSymbols")
        if !(bundled.map(MaterialSymbols.load) ?? false) {
            MaterialSymbols.load(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Resources/MaterialSymbols").standardized)
        }

        store = ConfigStore()
        buildMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x2.fill",
                                           accessibilityDescription: "Ajazz Deck")
        statusItem.menu = buildStatusMenu()

        // Keep the status menu in step with connection and page changes.
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AjazzDeckStateChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.menu = self?.buildStatusMenu() }
        }

        showConfigWindow()

        if !store.hasAccessibilityPermission {
            store.requestAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.controller.stop()
    }

    /// Reopening from the Dock or Finder brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showConfigWindow()
        return true
    }

    // MARK: - Configuration window

    @objc func showConfigWindow() {
        if let window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = ConfigWindowView(store: store)
        let controller = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: controller)
        w.title = "Ajazz Deck"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 1020, height: 640))
        w.minSize = NSSize(width: 820, height: 520)
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.toolbarStyle = .unified
        window = w

        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Drop back to a menu-bar-only app when the window closes.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Status menu

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(
            title: store.isConnected ? "Connected — \(store.controller.currentPageName)"
                                     : "Panel not found",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Configure…", action: #selector(showConfigWindow),
                              keyEquivalent: ",")
        open.target = self
        menu.addItem(open)

        if !store.config.pages.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Pages", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (i, page) in store.config.pages.enumerated() {
                let item = NSMenuItem(title: "  \(page.name)", action: #selector(choosePage(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.tag = i
                item.state = (i == store.controller.pageIndex) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let repaint = NSMenuItem(title: "Repaint Panel", action: #selector(repaintPanel),
                                 keyEquivalent: "")
        repaint.target = self
        menu.addItem(repaint)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ajazz Deck",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func choosePage(_ sender: NSMenuItem) {
        store.sidebar = .page(sender.tag)
        store.controller.selectPage(sender.tag)
        statusItem.menu = buildStatusMenu()
    }

    @objc private func repaintPanel() { store.repaint() }

    // MARK: - Control clipboard
    //
    // Edit ▸ Cut/Copy/Paste go to the first responder. A focused text field
    // handles them itself; otherwise they fall through the responder chain to
    // here, as the window's delegate, and act on the selected control.

    /// The selected control, when the canvas is showing.
    private var selectedControl: ControlSelection? {
        guard case .page = store.sidebar else { return nil }
        return store.selection
    }

    @objc func copy(_ sender: Any?) { selectedControl.map(store.copy) }
    @objc func cut(_ sender: Any?) { selectedControl.map(store.cut) }
    @objc func paste(_ sender: Any?) { selectedControl.map { store.paste(into: $0) } }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return selectedControl.map(store.hasContent) ?? false
        case #selector(paste(_:)):
            return selectedControl.map { store.canPaste(into: $0) } ?? false
        default:
            return true
        }
    }

    // MARK: - Main menu
    //
    // Built by hand because there is no nib. Without a standard Edit menu the
    // text fields in the inspector would have no Cut/Copy/Paste/Select All.

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Ajazz Deck",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Configure…",
                                       action: #selector(showConfigWindow), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Ajazz Deck",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Ajazz Deck",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

@main
struct AjazzDeckApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication holds its delegate weakly.
        withExtendedLifetime(delegate) {
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
