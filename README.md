# FloatNote

A minimal floating sticky note for macOS. Translucent, always on top, lives in your menu bar.

## Features

- Always-on-top floating window across all Spaces
- Tabbed notes with per-tab colors
- Todo checkboxes — paste a list to auto-create todos
- Frosted glass background with customizable opacity
- Per-note and global settings for font size, opacity, colors
- Global hotkey (`Cmd+Shift+Space`) to show/hide
- Auto-saves everything, remembers window position
- No Dock icon

## Build

```bash
swift build
open FloatNote.app  # after copying: cp .build/debug/FloatNote FloatNote.app/Contents/MacOS/FloatNote
```

Or open `Package.swift` in Xcode and hit `Cmd+R`.

Requires macOS 13+ and Swift 5.9+.

## Data

- Notes: `~/Library/Application Support/FloatNote/`
- Settings: UserDefaults (`~/Library/Preferences/`)

## License

MIT
