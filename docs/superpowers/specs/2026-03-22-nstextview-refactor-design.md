# FloatNote: NSTextView Refactor Design

## Problem

FloatNote uses one NSTextField per line. This causes:
- Height calculation bugs (text jumps on focus changes)
- No native cross-line mouse selection
- Font size conflicts during re-renders between per-note overrides and global defaults
- ~400 lines of workaround code for selection, height, focus management

## Solution

Replace per-line NSTextFields with a single NSTextView (TextKit 2) per note.

## Architecture

### Data Flow

```
NoteModel.lines ──build──▶ NSAttributedString ──set──▶ NSTextView.textStorage
                                                              │
User types ◀──parse──── textStorage content ◀────────── textDidChange
```

- **Model → View**: Builder function converts `[NoteLine]` into one `NSAttributedString` with attachments and styles
- **View → Model**: On every keystroke, parse text storage back into `[NoteLine]` and set `model.lines`
- **Feedback prevention**: `isUpdatingFromModel` flag on Coordinator prevents re-parsing during model-driven updates

NoteModel remains the source of truth. `parse()`/`serialize()` for disk persistence unchanged.

### New Components

**`NoteTextView`** — NSTextView subclass
- TextKit 2 setup (NSTextLayoutManager, NSTextContentStorage, NSTextContainer)
- Transparent background, no border
- Exposes `baseFontSize` and `baseTextColor` for per-note styling
- Overrides `keyDown` for slash menu key interception

**`NoteTextViewRepresentable`** — NSViewRepresentable
- Wraps NoteTextView
- Coordinator acts as NSTextViewDelegate
- `makeNSView`: builds attributed string from `model.lines`, sets on text storage
- `updateNSView`: rebuilds only on external model changes (slash commands, font/color changes, clearAll)

**`CheckboxAttachment`** — NSTextAttachment subclass
- Stores `lineIndex` and `isChecked` state

**`CheckboxViewProvider`** — NSTextAttachmentViewProvider subclass
- Returns NSButton with checkbox style, sized to font
- Button click toggles `isChecked` on the model, re-applies strikethrough on that line's text range

**`DividerViewProvider`** — NSTextAttachmentViewProvider subclass
- Returns a thin NSView (1pt height, gray, full width)
- Non-editable, cursor skips over it

### Attributed String Builder

`func buildAttributedString(from lines: [NoteLine], fontSize: CGFloat, textColor: NoteTint) -> NSAttributedString`

Per line type:
- **Plain text**: Rounded font at `fontSize`, text color from note settings
- **Checkbox**: CheckboxAttachment + space + text. If checked: strikethrough + secondary color
- **Heading**: Bold rounded font at `fontSize * 1.4`
- **Bullet**: `•` character (secondary color) + space + text
- **Divider**: DividerAttachment (full line)

Each line terminated by `\n`.

### Text → Model Parser

On `textDidChange`, enumerate paragraphs in text storage:
1. Starts with checkbox attachment → `isCheckbox = true`, read `isChecked` from attachment
2. Starts with divider attachment → `style = .divider`
3. Has heading font attributes → `style = .heading`
4. Starts with `•` → `style = .bullet`, strip prefix
5. Otherwise → `style = .text`

Strip attachment characters (`\u{FFFC}`) from text content. Rebuild `model.lines` from scratch (new UUIDs — line identity not needed since ForEach is gone).

### Keyboard Behavior

- **Enter on checkbox line with text**: Insert new checkbox line
- **Enter on empty checkbox line**: Convert to plain text
- **Enter on bullet line with text**: Insert new bullet line
- **Enter on empty bullet line**: Convert to plain text
- **Backspace at start of checkbox/bullet**: Remove prefix, convert to plain text
- **Cmd+A**: Native select all (works across lines automatically)
- **Undo/Redo**: Native NSTextView support

### Slash Commands

- **Detection**: In `textDidChange`, check if current paragraph contains `/`
- **Positioning**: `firstRect(forCharacterRange:)` → screen coordinates → SwiftUI overlay anchor
- **Key interception**: Override `keyDown` in NoteTextView when slash menu is visible (arrow keys, Enter, Escape)
- **Applying**: Remove `/` text, apply command to model, rebuild attributed string
- **SlashMenuState**: Tracks character index instead of line UUID. `SlashMenuOverlay` view unchanged.

### Per-Note Font Size and Colors

- `model.fontSize` and `model.textColor` (Combine-driven @Published) feed into `updateNSView`
- Coordinator stores previous values; on change, rebuilds full attributed string
- `typingAttributes` set to match so new text inherits the correct style

## What Gets Deleted

**ContentView.swift** (~400 lines):
- `WrappingTextField` (NSTextField subclass)
- `LineTextFieldRepresentable` (NSViewRepresentable + Coordinator)
- `LineTextField` (SwiftUI wrapper)
- Manual selection system: `selectedLineIds`, `installCopyMonitor`, `selectRange`, `exitSelection`, `copySelectedLines`
- `focusedLineId`, focus notification handlers

**AppDelegate.swift** (4 notifications):
- `floatNoteFocusLine`, `floatNoteLineFocused`, `floatNoteSelectAllLines`, `floatNoteShiftClickLine`

**NoteModel.swift** (unused methods):
- `insertLine(after:checkbox:)`, `deleteLine(_:)`, `toggleLineType(_:)`, `pasteLines(_:at:appendToExisting:)`

## What Stays the Same

- ContentView outer shell (ZStack, background, tab bar, settings popover)
- NoteEditorView structure (body becomes NoteTextViewRepresentable + slash menu overlay)
- TabBar, TabItemView, RenameField, TabClickHandler
- NoteModel, NoteStore, GlobalSettings, PersistenceManager
- SettingsView and all sub-views
- HotkeyManager
- Slash command enum and menu overlay UI

## Risks

- **TextKit 2 edge cases**: Known bugs with very long lines. Not relevant for a notes app with wrapping short paragraphs.
- **Cursor preservation**: When slash commands rebuild the attributed string, cursor position must be saved and restored. Save paragraph-relative offset before rebuild, restore after.
- **Attachment character counting**: `\u{FFFC}` counts as 1 character in string length. Parser must handle this when extracting text content.
