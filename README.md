# FloatNote

A minimal, always-on-top sticky note app for macOS. FloatNote sits on your desktop as a translucent floating panel — perfect for quick notes, checklists, and todos that you need to keep visible while you work.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Always floating** — stays on top of all windows across every Space
- **Tabbed notes** — multiple notes in one window, switch instantly between them
- **Todos** — paste a list and it auto-converts to checkboxes, or toggle any line into a todo
- **Frosted glass UI** — translucent material background that blends with your desktop
- **Per-note customization** — font size, opacity, note color, and text color per tab
- **Global defaults** — set defaults that apply to all notes, override individually per tab
- **Drag from anywhere** — grab any edge or padding area to reposition the window
- **Text wrapping** — long lines wrap naturally, pushing content below them down
- **Select all** — press `Cmd+A` twice to select across all lines, then `Cmd+C` to copy everything
- **Multi-line paste** — paste a block of text and each line becomes a todo item
- **Rename tabs** — double-click a tab name to rename it inline
- **Tab colors** — right-click a tab to quickly change its color
- **Menu bar icon** — show/hide, new tab, settings from the status bar
- **Keyboard shortcuts** — `Cmd+/Cmd-` for font size, standard edit shortcuts
- **Global hotkey** — `Cmd+Shift+Space` to show/hide from any app (requires Accessibility permission)
- **Persistent** — notes auto-save to disk, window position remembered between launches
- **Zero Dock footprint** — runs as a menu bar app, no Dock icon

## Build

Requires macOS 13+ and Swift 5.9+.

```bash
git clone https://github.com/AimenHallou/floatnote.git
cd floatnote
swift build
```

Run the built binary:

```bash
.build/debug/FloatNote
```

Or copy into the `.app` bundle and launch:

```bash
cp .build/debug/FloatNote FloatNote.app/Contents/MacOS/FloatNote
open FloatNote.app
```

You can also open `Package.swift` in Xcode and hit `Cmd+R`.

## First Launch

FloatNote uses `CGEventTap` for the global hotkey, which requires **Accessibility** permission. On first launch you'll be prompted to enable it in **System Settings → Privacy & Security → Accessibility**.

## Project Structure

```
Sources/FloatNote/
├── main.swift               # App entry point
├── AppDelegate.swift        # Window/panel setup, menu bar, hotkey
├── ContentView.swift        # Tab bar, note editor, line text fields
├── NoteModel.swift          # Data models, global settings, note store
├── PersistenceManager.swift # UserDefaults + file persistence
├── SettingsView.swift       # Settings popover (global + per-note)
├── HotkeyManager.swift      # System-wide hotkey via CGEventTap
└── Resources/
    └── Info.plist           # LSUIElement, bundle metadata
```

## How It Works

FloatNote runs as a menu bar app (`LSUIElement`) with no Dock icon. It creates an `NSPanel` with floating level that stays above all windows. The panel uses `isMovableByWindowBackground` so dragging from any non-interactive area repositions the window.

Each note is a list of lines — plain text or checkboxes. Notes are stored as plain text files in `~/Library/Application Support/FloatNote/`, with settings (colors, opacity, font size) in UserDefaults. Everything auto-saves with a 300ms debounce.

Settings support two levels: **global defaults** that apply to all notes, and **per-note overrides** that take priority. The settings popover shows tabs for every note so you can configure each one without switching.

## Data Location

- Note text: `~/Library/Application Support/FloatNote/<uuid>.txt`
- Settings: `~/Library/Preferences/` (UserDefaults)

## License

MIT
