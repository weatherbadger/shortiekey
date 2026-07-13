# ShortieKey

[![GitHub release](https://img.shields.io/github/v/release/weatherbadger/shortiekey)](https://github.com/weatherbadger/shortiekey/releases/latest)

> Download the latest release: [ShortieKey-v0.1.0.zip](https://github.com/weatherbadger/shortiekey/releases/latest)

A lightweight macOS menu bar window manager — a modern replacement for Spectacle. (https://github.com/eczarny/spectacle)

ShortieKey runs silently in the menu bar (no Dock icon), registers system-wide keyboard shortcuts, and snaps/resizes windows using the native macOS Accessibility API.

---

## Features

- Snap windows to left/right halves, top/bottom halves, or fullscreen
- Restore windows to their previous size
- Move windows between monitors
- Fully configurable keyboard shortcuts via Preferences
- Runs silently in the menu bar — no Dock icon

---

## Requirements

- macOS 15 Sequoia or later
- Xcode 15+ (to build from source)
- Accessibility permission (prompted on first launch)

---

## Default Shortcuts

| Action | Shortcut |
|---|---|
| Snap Left | ⌥⌘← |
| Snap Right | ⌥⌘→ |
| Snap Top | ⌥⌘T |
| Snap Bottom | ⌥⌘B |
| Fullscreen | ⌥⌘↑ |
| Restore | ⌥⌘↓ |
| Next Screen | ⌃⌥⌘→ |
| Prev Screen | ⌃⌥⌘← |

---

## Building & Installing

1. Clone the repo:
   ```bash
   git clone https://github.com/weatherbadger/shortiekey.git
   cd shortiekey
   ```
2. Open `ShortieKey.xcodeproj` in Xcode.
3. Press **⌘R** to build and run.
4. Grant Accessibility permission when prompted — ShortieKey cannot move windows without it.

> **Tip:** To have ShortieKey launch at login, add it in  
> **System Settings → General → Login Items**.

---

## Customising Shortcuts

Click the menu bar icon → **Preferences…** to rebind any shortcut. Click a shortcut field and press the new key combination. Changes take effect immediately and are persisted across launches.

---

## Project Structure

```
ShortieKey/
├── AppDelegate.swift               # App lifecycle, menu bar status item
├── WindowManager.swift             # AXUIElement window snapping logic
├── HotkeyManager.swift             # Carbon global hotkey registration
├── PreferencesWindowController.swift  # Preferences UI + UserDefaults persistence
├── Info.plist                      # LSUIElement = YES (no Dock icon)
└── Assets.xcassets/                # App icon + menu bar icon
```

---

## Built With

Built with ❤️ by [IBM Bob](https://github.com/weatherbadger) using Swift and the macOS Accessibility API.
