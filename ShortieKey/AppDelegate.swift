import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private var accessibilityWarningItem: NSMenuItem?
    private var preferencesWindowController: PreferencesWindowController?
    let windowManager = WindowManager()
    let hotkeyManager = HotkeyManager()
    // Captured just before the menu opens — this is the app we want to act on
    private var targetApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle",
                                   accessibilityDescription: "ShortieKey")
        }

        let menu = NSMenu()

        // Window actions with right-aligned shortcut labels
        let actions: [(String, String, Selector)] = [
            ("← Snap Left",   "⌥⌘←",  #selector(testSnapLeft)),
            ("→ Snap Right",  "⌥⌘→",  #selector(testSnapRight)),
            ("↑ Snap Top",    "⌥⌘T",  #selector(testSnapTop)),
            ("↓ Snap Bottom", "⌥⌘B",  #selector(testSnapBottom)),
            ("⛶ Fullscreen",  "⌥⌘↑",  #selector(testSnapFullscreen)),
            ("↩ Restore",     "⌥⌘↓",  #selector(testRestoreWindow)),
            ("▶ Next Screen", "⌃⌥⌘→", #selector(testNextScreen)),
            ("◀ Prev Screen", "⌃⌥⌘←", #selector(testPrevScreen)),
        ]
        for (label, shortcut, sel) in actions {
            let item = NSMenuItem(title: "", action: sel, keyEquivalent: "")
            item.target = self
            item.attributedTitle = makeMenuTitle(label: label, shortcut: shortcut)
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(preferencesItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "About ShortieKey",
            action: #selector(openAbout),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit ShortieKey",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        menu.delegate = self
        statusItem?.menu = menu

        hotkeyManager.onAction = { [weak self] action in
            guard let self = self else { return }
            // For hotkeys, capture the frontmost app at fire time — the user is
            // actively using it and ShortieKey is not taking focus.
            let frontApp = NSWorkspace.shared.frontmostApplication
            switch action {
            case .snapLeft:             self.windowManager.snapLeft(for: frontApp)
            case .snapRight:            self.windowManager.snapRight(for: frontApp)
            case .snapTop:              self.windowManager.snapTop(for: frontApp)
            case .snapBottom:           self.windowManager.snapBottom(for: frontApp)
            case .snapFullscreen:       self.windowManager.snapFullscreen(for: frontApp)
            case .restoreWindow:        self.windowManager.restoreWindow(for: frontApp)
            case .moveToNextScreen:     self.windowManager.moveToNextScreen(for: frontApp)
            case .moveToPreviousScreen: self.windowManager.moveToPreviousScreen(for: frontApp)
            }
        }
        hotkeyManager.registerAll(bindings: hotkeyManager.loadBindings())

        // Register as a login item on first launch (makes the checkbox default to on).
        // Only do this when notRegistered — if the user has previously unchecked the
        // box the status will be .notFound and we must leave it alone.
        if SMAppService.mainApp.status == .notRegistered {
            try? SMAppService.mainApp.register()
        }

        checkAccessibilityPermission(prompt: true)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // MARK: - Accessibility Permission

    private func checkAccessibilityPermission(prompt: Bool = false) {
        let trusted: Bool
        if prompt {
            trusted = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            )
        } else {
            trusted = AXIsProcessTrusted()
        }
        if trusted {
            removeAccessibilityWarning()
        } else {
            showAccessibilityWarning()
        }
    }

    private func showAccessibilityWarning() {
        guard let menu = statusItem?.menu, accessibilityWarningItem == nil else { return }

        let warningItem = NSMenuItem(
            title: "⚠️ Accessibility access required",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        warningItem.target = self
        menu.insertItem(warningItem, at: 0)
        accessibilityWarningItem = warningItem
    }

    private func removeAccessibilityWarning() {
        guard let menu = statusItem?.menu, let item = accessibilityWarningItem else { return }
        menu.removeItem(item)
        accessibilityWarningItem = nil
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    @objc private func appDidActivate(_ notification: Notification) {
        // No-op — permission is checked on every menu open instead
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Capture the frontmost app NOW, before the menu click shifts focus
        targetApp = NSWorkspace.shared.frontmostApplication
        // Re-check permission each time — warning clears automatically once granted
        checkAccessibilityPermission()
    }

    // MARK: - Menu Helpers

    private func makeMenuTitle(label: String, shortcut: String) -> NSAttributedString {
        let menuWidth: CGFloat = 220
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: menuWidth)]
        style.defaultTabInterval = menuWidth

        let font = NSFont.menuFont(ofSize: 0)
        let str = NSMutableAttributedString()
        str.append(NSAttributedString(
            string: label,
            attributes: [.font: font, .paragraphStyle: style]
        ))
        str.append(NSAttributedString(
            string: "\t\(shortcut)",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: style]
        ))
        return str
    }

    // MARK: - Actions

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(hotkeyManager: hotkeyManager)
        }
        preferencesWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        let alert = NSAlert()
        alert.messageText = "ShortieKey"
        alert.informativeText = """
            A lightweight macOS window manager.
            Snap and move windows with keyboard shortcuts.

            Version 0.1.0

            Built by IBM Bob 🤖
            github.com/weatherbadger/shortiekey
            """
        alert.addButton(withTitle: "View on GitHub")
        alert.addButton(withTitle: "Close")
        alert.icon = NSApp.applicationIconImage

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://github.com/weatherbadger/shortiekey")!)
        }
    }

    // MARK: - Test Actions (Sub-Task 3)

    @objc private func testSnapLeft()       { windowManager.snapLeft(for: targetApp) }
    @objc private func testSnapRight()      { windowManager.snapRight(for: targetApp) }
    @objc private func testSnapTop()        { windowManager.snapTop(for: targetApp) }
    @objc private func testSnapBottom()     { windowManager.snapBottom(for: targetApp) }
    @objc private func testSnapFullscreen() { windowManager.snapFullscreen(for: targetApp) }
    @objc private func testRestoreWindow()  { windowManager.restoreWindow(for: targetApp) }
    @objc private func testNextScreen()     { windowManager.moveToNextScreen(for: targetApp) }
    @objc private func testPrevScreen()     { windowManager.moveToPreviousScreen(for: targetApp) }
}
