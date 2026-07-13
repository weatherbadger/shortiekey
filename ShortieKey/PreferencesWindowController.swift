import AppKit
import Carbon

// MARK: - KeyCaptureField

/// An NSTextField subclass that captures the next key combination typed by the user.
/// While in "recording" mode it shows "Press keys…" and consumes the key event.
class KeyCaptureField: NSTextField {

    /// Called when a valid key combination is captured. Arguments: (keyCode, carbonModifiers).
    var onCapture: ((UInt32, UInt32) -> Void)?

    private var isRecording = false

    // Key codes that are modifier-only — we ignore these as standalone presses.
    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_Function), UInt16(kVK_CapsLock),
    ]

    func startRecording() {
        isRecording = true
        stringValue = "Press keys…"
        window?.makeFirstResponder(self)
    }

    func stopRecording() {
        isRecording = false
    }

    // Accept first-responder so we receive key events.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        // Ignore bare modifier keystrokes.
        if KeyCaptureField.modifierKeyCodes.contains(event.keyCode) { return }

        let cocoaMods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let carbonMods = carbonModifiers(from: cocoaMods)
        let keyCode = UInt32(event.keyCode)

        // Build display string and update the field.
        stringValue = modifierString(from: cocoaMods) + keyString(from: event)

        isRecording = false
        onCapture?(keyCode, carbonMods)
    }

    // Swallow flagsChanged so modifier-only presses don't bubble.
    override func flagsChanged(with event: NSEvent) {}

    // MARK: - Helpers

    private func modifierString(from flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option)  { s += "⌥" }
        if flags.contains(.command) { s += "⌘" }
        if flags.contains(.shift)   { s += "⇧" }
        return s
    }

    private func keyString(from event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        case kVK_Return:     return "↩"
        case kVK_Tab:        return "⇥"
        case kVK_Space:      return "Space"
        case kVK_Delete:     return "⌫"
        case kVK_Escape:     return "⎋"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option)  { mods |= UInt32(optionKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
        return mods
    }
}

// MARK: - PreferencesWindowController

class PreferencesWindowController: NSWindowController,
                                   NSTableViewDataSource,
                                   NSTableViewDelegate {

    private let hotkeyManager: HotkeyManager

    // Display order for the table rows.
    private let actionOrder: [HotkeyAction] = [
        .snapLeft, .snapRight, .snapTop, .snapBottom,
        .snapFullscreen, .restoreWindow,
        .moveToNextScreen, .moveToPreviousScreen,
    ]

    private let displayNames: [String: String] = [
        "snapLeft":             "Snap Left",
        "snapRight":            "Snap Right",
        "snapTop":              "Snap Top",
        "snapBottom":           "Snap Bottom",
        "snapFullscreen":       "Fullscreen",
        "restoreWindow":        "Restore",
        "moveToNextScreen":     "Next Screen",
        "moveToPreviousScreen": "Previous Screen",
    ]

    // Working copy of bindings — edited in-place as the user records shortcuts.
    private var currentBindings: [HotkeyAction: HotkeyBinding] = [:]

    // One KeyCaptureField per row, keyed by row index.
    private var captureFields: [Int: KeyCaptureField] = [:]

    private var tableView: NSTableView!

    // MARK: - Init

    init(hotkeyManager: HotkeyManager) {
        self.hotkeyManager = hotkeyManager
        self.currentBindings = hotkeyManager.loadBindings()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ShortieKey Preferences"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    // MARK: - UI Construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        // --- Scroll view + table ---
        let scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing

        let actionCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionCol.title = "Action"
        actionCol.width = 200
        actionCol.isEditable = false
        tableView.addTableColumn(actionCol)

        let shortcutCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutCol.title = "Shortcut"
        shortcutCol.width = 160
        shortcutCol.isEditable = false
        tableView.addTableColumn(shortcutCol)

        scrollView.documentView = tableView

        // --- Buttons ---
        let restoreButton = NSButton(
            title: "Restore Defaults",
            target: self,
            action: #selector(restoreDefaults)
        )
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.bezelStyle = .rounded
        contentView.addSubview(restoreButton)

        let saveButton = NSButton(
            title: "Save",
            target: self,
            action: #selector(saveAndClose)
        )
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        // --- Layout ---
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -12),

            restoreButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            restoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            saveButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int { actionOrder.count }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let action = actionOrder[row]

        if tableColumn?.identifier.rawValue == "action" {
            let cell = NSTextField(labelWithString: displayNames[action.rawValue] ?? action.rawValue)
            cell.identifier = NSUserInterfaceItemIdentifier("actionCell")
            return cell
        }

        if tableColumn?.identifier.rawValue == "shortcut" {
            // Re-use or create the capture field for this row.
            if let existing = captureFields[row] { return existing }

            let field = KeyCaptureField()
            field.identifier = NSUserInterfaceItemIdentifier("shortcutCell-\(row)")
            field.isEditable = false
            field.isSelectable = false
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            field.stringValue = shortcutString(for: action)

            field.onCapture = { [weak self] keyCode, modifiers in
                guard let self = self else { return }
                self.currentBindings[action] = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)
                field.stopRecording()
            }

            // Single-click → enter recording mode.
            let clickGesture = NSClickGestureRecognizer(target: self,
                                                        action: #selector(fieldClicked(_:)))
            clickGesture.numberOfClicksRequired = 1
            field.addGestureRecognizer(clickGesture)
            // Tag the field so we can identify which row was clicked.
            field.tag = row

            captureFields[row] = field
            return field
        }

        return nil
    }

    // MARK: - Actions

    @objc private func fieldClicked(_ gesture: NSClickGestureRecognizer) {
        guard let field = gesture.view as? KeyCaptureField else { return }
        field.startRecording()
    }

    @objc private func restoreDefaults() {
        currentBindings = HotkeyManager.defaultBindings
        // Rebuild capture fields with fresh default strings.
        captureFields.removeAll()
        tableView.reloadData()
    }

    @objc private func saveAndClose() {
        hotkeyManager.saveBindings(currentBindings)
        hotkeyManager.unregisterAll()
        hotkeyManager.registerAll(bindings: currentBindings)
        window?.close()
    }

    // MARK: - Helpers

    /// Converts a stored binding back to a human-readable shortcut string.
    private func shortcutString(for action: HotkeyAction) -> String {
        guard let binding = currentBindings[action] else { return "" }
        return carbonModifierString(binding.modifiers) + carbonKeyString(binding.keyCode)
    }

    private func carbonModifierString(_ modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        if modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        return s
    }

    private func carbonKeyString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_LeftArrow:  return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow:    return "↑"
        case kVK_DownArrow:  return "↓"
        case kVK_Return:     return "↩"
        case kVK_Tab:        return "⇥"
        case kVK_Space:      return "Space"
        case kVK_Delete:     return "⌫"
        case kVK_Escape:     return "⎋"
        default:
            // Translate key code to character via UCKeyTranslate.
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var charCount = 0
            if let keyboard = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
               let layoutData = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData) {
                let dataRef = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
                let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef),
                                                   to: UnsafePointer<UCKeyboardLayout>.self)
                UCKeyTranslate(keyboardLayout,
                               UInt16(keyCode),
                               UInt16(kUCKeyActionDisplay),
                               0,
                               UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit),
                               &deadKeyState,
                               4,
                               &charCount,
                               &chars)
            }
            let slice = Array(chars.prefix(charCount))
            let str = String(utf16CodeUnits: slice, count: charCount)
            return str.isEmpty ? "?" : str.uppercased()
        }
    }
}
