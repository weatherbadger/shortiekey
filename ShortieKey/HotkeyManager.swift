import Carbon
import AppKit

// All supported window actions, matching the WindowManager API.
enum HotkeyAction: String, CaseIterable {
    case snapLeft, snapRight, snapTop, snapBottom, snapFullscreen, restoreWindow
    case moveToNextScreen, moveToPreviousScreen
}

// A single key binding expressed as Carbon key code + Carbon modifier flags.
struct HotkeyBinding {
    let keyCode: UInt32
    let modifiers: UInt32
}

class HotkeyManager {

    // AppDelegate sets this; fired on the main queue when a hotkey is pressed.
    var onAction: ((HotkeyAction) -> Void)?

    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    // Static lookup table used by the C-style Carbon callback.
    static var actionMap: [UInt32: HotkeyAction] = [:]
    static weak var shared: HotkeyManager?

    // Default bindings.
    // ⌥⌘←   = snap left half
    // ⌥⌘→   = snap right half
    // ⌥⌘T   = snap top half
    // ⌥⌘B   = snap bottom half
    // ⌥⌘↑   = fullscreen
    // ⌥⌘↓   = restore to previous size
    // ⌃⌥⌘→  = move to next monitor
    // ⌃⌥⌘←  = move to previous monitor
    static let defaultBindings: [HotkeyAction: HotkeyBinding] = [
        .snapLeft:             HotkeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(optionKey | cmdKey)),
        .snapRight:            HotkeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | cmdKey)),
        .snapTop:              HotkeyBinding(keyCode: UInt32(kVK_ANSI_T),     modifiers: UInt32(optionKey | cmdKey)),
        .snapBottom:           HotkeyBinding(keyCode: UInt32(kVK_ANSI_B),     modifiers: UInt32(optionKey | cmdKey)),
        .snapFullscreen:       HotkeyBinding(keyCode: UInt32(kVK_UpArrow),    modifiers: UInt32(optionKey | cmdKey)),
        .restoreWindow:        HotkeyBinding(keyCode: UInt32(kVK_DownArrow),  modifiers: UInt32(optionKey | cmdKey)),
        .moveToNextScreen:     HotkeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(optionKey | cmdKey | controlKey)),
        .moveToPreviousScreen: HotkeyBinding(keyCode: UInt32(kVK_LeftArrow),  modifiers: UInt32(optionKey | cmdKey | controlKey)),
    ]

    // Register all hotkeys. Unregisters any previously registered ones first.
    func registerAll(bindings: [HotkeyAction: HotkeyBinding] = defaultBindings) {
        unregisterAll()
        HotkeyManager.shared = self

        // Install a single Carbon event handler that handles all hotkey presses.
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                if let action = HotkeyManager.actionMap[hotkeyID.id],
                   let manager = HotkeyManager.shared {
                    DispatchQueue.main.async { manager.onAction?(action) }
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            &eventHandler
        )

        // Register each individual hotkey and record it in the action map.
        for (index, (action, binding)) in bindings.enumerated() {
            let hotkeyID = EventHotKeyID(signature: OSType(0x534B5900), id: UInt32(index)) // 'SKY\0'
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.keyCode,
                binding.modifiers,
                hotkeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let ref = hotKeyRef {
                hotKeyRefs[action] = ref
                HotkeyManager.actionMap[UInt32(index)] = action
            } else {
                print("ShortieKey: failed to register hotkey for \(action) (status \(status))")
            }
        }
    }

    // Unregister all currently registered hotkeys and remove the event handler.
    func unregisterAll() {
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        HotkeyManager.actionMap.removeAll()
        if let handler = eventHandler { RemoveEventHandler(handler) }
        eventHandler = nil
    }

    // MARK: - Persistence

    // Save bindings to UserDefaults.
    func saveBindings(_ bindings: [HotkeyAction: HotkeyBinding]) {
        var dict: [String: [String: Int]] = [:]
        for (action, binding) in bindings {
            dict[action.rawValue] = ["keyCode": Int(binding.keyCode), "modifiers": Int(binding.modifiers)]
        }
        UserDefaults.standard.set(dict, forKey: "shortiekeyBindings")
    }

    // Load bindings from UserDefaults, falling back to defaults for any missing action.
    func loadBindings() -> [HotkeyAction: HotkeyBinding] {
        guard let dict = UserDefaults.standard.dictionary(forKey: "shortiekeyBindings") as? [String: [String: Int]] else {
            return HotkeyManager.defaultBindings
        }
        var bindings = HotkeyManager.defaultBindings
        for action in HotkeyAction.allCases {
            if let entry = dict[action.rawValue],
               let keyCode = entry["keyCode"],
               let modifiers = entry["modifiers"] {
                bindings[action] = HotkeyBinding(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
            }
        }
        return bindings
    }
}
