# FloatNote

A minimal floating sticky note for macOS. Frosted glass, always on top, zero Dock footprint.

## What it is

- **Floating translucent panel** — lives above all your windows, never in the Dock
- **Autosaves** every keystroke to `~/Library/Application Support/FloatNote/note.txt`
- **Global hotkey** (⌘⇧Space by default) — show/hide from any app
- **Remembers** window position and size between launches
- **Right-click → Settings** to change the hotkey

## How to build

### Option A — Open in Xcode (recommended)

1. Clone the repo
2. Double-click `Package.swift` — Xcode opens it as a Swift Package
3. Select the `FloatNote` scheme, choose **My Mac** as destination
4. Press **⌘R** to build and run

### Option B — `swift build` from Terminal

```bash
cd floatnote
swift build -c release
# The binary lands at:
.build/release/FloatNote
# Run it:
./.build/release/FloatNote
```

> **Note:** `swift build` produces a plain binary. For a proper `.app` bundle
> (with icon, Info.plist, Dock suppression via LSUIElement), use Xcode or wrap
> the binary yourself. The LSUIElement key in `Resources/Info.plist` is embedded
> by Xcode's build system; with `swift build` you may see a Dock icon appear
> briefly until macOS processes the plist.

## First launch — grant Accessibility permission

FloatNote uses `CGEventTap` to intercept the global hotkey system-wide. This
requires **Accessibility** permission.

On first launch, if the permission isn't granted, FloatNote shows an alert and
opens **System Settings → Privacy & Security → Accessibility**. Enable FloatNote
there, and the hotkey activates automatically within 2 seconds — no restart
needed.

## Default hotkey

**⌘⇧Space** — show or hide the note from anywhere.

## Changing the hotkey

Right-click anywhere on the note → **Settings…**

Click the hotkey button, then press the new combo you want (must include ⌘ or
⌃). Press **Save**.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (for building; Swift 5.9+)

## File layout

```
floatnote/
  Package.swift
  README.md
  Sources/
    FloatNote/
      main.swift               — entry point, NSApplication bootstrap
      AppDelegate.swift        — window creation, hotkey wiring
      ContentView.swift        — SwiftUI panel UI + drag handle
      NoteModel.swift          — ObservableObject bridging text ↔ disk
      HotkeyManager.swift      — CGEventTap global hotkey
      PersistenceManager.swift — note.txt + UserDefaults
      SettingsView.swift       — settings sheet + key recorder
      Resources/
        Info.plist             — LSUIElement, bundle metadata
```

## Data location

Note text: `~/Library/Application Support/FloatNote/note.txt`  
Preferences (window frame, hotkey): `~/Library/Preferences/` (UserDefaults)
