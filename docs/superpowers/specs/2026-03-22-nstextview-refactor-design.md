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
- **Feedback prevention**: `isUpdatingFromModel` flag on Coordinator. Set to `true` before ANY model-driven text storage mutation (full rebuilds, checkbox toggles, slash command applications). Checked in `textDidChange` to skip re-parsing. Reset to `false` after mutation completes.

NoteModel remains the source of truth. `parse()`/`serialize()` for disk persistence unchanged.

### New Components

**`NoteTextView`** — NSTextView subclass
- TextKit 2 setup (NSTextLayoutManager, NSTextContentStorage, NSTextContainer)
- Transparent background, no border
- Exposes `baseFontSize` and `baseTextColor` for per-note styling
- Overrides `keyDown` for slash menu key interception
- Reference to a `SlashMenuState` to check visibility when intercepting keys

**`NoteTextViewRepresentable`** — NSViewRepresentable
- Wraps NoteTextView
- Coordinator acts as NSTextViewDelegate
- `makeNSView`: builds attributed string from `model.lines`, sets on text storage
- `updateNSView`: Coordinator stores previous `fontSize`, `textColor`, `tintColor`, and a `modelLineHash` (hash of `model.lines`). On each call, compares current values to stored. If changed AND the change did not originate from typing (i.e., `isUpdatingFromModel` is false), rebuilds the attributed string. This prevents loops: typing → textDidChange → model.lines update → @Published fires → updateNSView called → sees isUpdatingFromModel=true or lineHash matches → skips rebuild.

**`CheckboxAttachment`** — NSTextAttachment subclass
- Stores `lineIndex: Int` and `isChecked: Bool`

**`CheckboxViewProvider`** — NSTextAttachmentViewProvider subclass
- Returns NSButton with checkbox style, sized to font
- Button click path: set `isUpdatingFromModel = true`, toggle strikethrough/color on the text range of that line directly in textStorage (local mutation, no full rebuild), update the `isChecked` property on the attachment, then sync `model.lines[lineIndex].isChecked`, set `isUpdatingFromModel = false`. This avoids a full rebuild for a simple toggle.

**`DividerViewProvider`** — NSTextAttachmentViewProvider subclass
- Returns a thin NSView (1pt height, gray, full width)
- Divider attachment occupies its own paragraph (`\u{FFFC}\n`). To prevent editing into the divider, override `textView(_:shouldChangeTextIn:replacementString:)` in the delegate — if the affected range overlaps a divider attachment range and the replacement is not empty (i.e., not a delete), reject the change. For cursor navigation, no special handling needed — arrow keys naturally move past single characters.

### Attributed String Builder

`func buildAttributedString(from lines: [NoteLine], fontSize: CGFloat, textColor: NoteTint) -> NSAttributedString`

Note: `NoteTint.clear` means "use system label color" (`NSColor.labelColor`). The builder resolves this via `textColor.nsColor` which already handles this convention.

Per line type:
- **Plain text**: Rounded font at `fontSize`, resolved text color
- **Checkbox**: CheckboxAttachment + space + text. If checked: strikethrough + secondary color
- **Heading**: Bold rounded font at `fontSize * 1.4`
- **Bullet**: `•` character (secondary color) + space + text
- **Divider**: DividerAttachment (full line)

Each line terminated by `\n`.

### Text → Model Parser

On `textDidChange`, enumerate paragraphs in text storage:
1. Starts with checkbox attachment (`\u{FFFC}` + CheckboxAttachment in attributes) → `isCheckbox = true`, read `isChecked` from attachment
2. Starts with divider attachment → `style = .divider`
3. Has heading font size (> baseFontSize * 1.2) → `style = .heading`
4. Starts with `•` → `style = .bullet`, strip prefix
5. Otherwise → `style = .text`

Strip attachment characters (`\u{FFFC}`) from text content. Rebuild `model.lines` from scratch (new UUIDs — line identity not needed since ForEach is gone).

### Keyboard Behavior

- **Enter on checkbox line with text**: Insert new checkbox line (insert checkbox attachment + newline into text storage)
- **Enter on empty checkbox line**: Convert to plain text (remove checkbox attachment from current line)
- **Enter on bullet line with text**: Insert new bullet line
- **Enter on empty bullet line**: Convert to plain text
- **Backspace at start of checkbox/bullet**: Remove prefix, convert to plain text
- **Cmd+A**: Native select all (works across lines automatically)
- **Undo/Redo**: Native NSTextView support

### Slash Commands

**SlashMenuState changes:**
- Replace `lineId: UUID?` with `charIndex: Int?` (the location of `/` in the text storage)
- `show(charIndex:)` replaces `show(lineId:)`
- `hide()` unchanged
- `filteredCommands`, `selectedCommand`, `moveUp`, `moveDown`, `updateFilter` unchanged

**SlashMenuOverlay changes:**
- The overlay is no longer positioned via `.overlay(alignment:)` on a line row (there are no line rows)
- Instead, `NoteTextViewRepresentable` exposes a `@Binding var slashMenuPosition: CGPoint?` that the Coordinator sets using `firstRect(forCharacterRange:actualRange:)` converted to the SwiftUI view's coordinate space via `convert(_:to:)` on the NSTextView
- `NoteEditorView` hosts the `SlashMenuOverlay` in a `ZStack` overlay positioned at `slashMenuPosition` using `.position()` or `.offset()`

**Detection**: In `textDidChange`, check if the current paragraph (paragraph containing the insertion point) contains `/`. If found and slash menu not visible, call `slashMenu.show(charIndex:)` and set `slashMenuPosition`. Update filter on subsequent changes. If `/` is removed, call `slashMenu.hide()`.

**Key interception**: `NoteTextView.keyDown(with:)` checks `slashMenu.isVisible`. If visible, arrow up/down calls `slashMenu.moveUp()/moveDown()`, Enter selects the command, Escape dismisses. Otherwise, calls `super.keyDown(with:)`.

**Applying**: Remove `/` + filter text from text storage, apply command to model at the paragraph index, rebuild attributed string with cursor restored.

### Per-Note Font Size and Colors

- `model.fontSize` and `model.textColor` (Combine-driven @Published) feed into `updateNSView`
- Coordinator stores previous `fontSize` and `textColor` values
- On change detected in `updateNSView`, full attributed string rebuild with new values
- `typingAttributes` set to match so new text inherits the correct style

### NoteEditorView Layout

```swift
var body: some View {
    ZStack(alignment: .topLeading) {
        // Tint overlay
        if model.tintColor != .clear { ... }

        // The single text view
        NoteTextViewRepresentable(model: model, slashMenu: slashMenu, slashMenuPosition: $slashMenuPosition)

        // Slash menu overlay (positioned at cursor)
        if slashMenu.isVisible, let pos = slashMenuPosition {
            SlashMenuOverlay(slashMenu: slashMenu) { command in ... }
                .offset(x: pos.x, y: pos.y)
        }
    }
}
```

## What Gets Deleted

**ContentView.swift** (~400 lines):
- `WrappingTextField` (NSTextField subclass)
- `LineTextFieldRepresentable` (NSViewRepresentable + Coordinator)
- `LineTextField` (SwiftUI wrapper)
- Manual selection system: `selectedLineIds`, `installCopyMonitor`, `selectRange`, `exitSelection`, `copySelectedLines`
- `focusedLineId`, all focus/selection notification handlers and `.onReceive` blocks

**AppDelegate.swift** (4 notification names removed, 1 kept):
- Delete: `floatNoteFocusLine`, `floatNoteLineFocused`, `floatNoteSelectAllLines`, `floatNoteShiftClickLine`
- Keep: `floatNoteOpenSettings` (still used by menu bar → ContentView)

**NoteModel.swift** (methods deleted vs kept):
- Delete: `insertLine(after:checkbox:)`, `deleteLine(_:)`, `toggleLineType(_:)`, `pasteLines(_:at:appendToExisting:)`
- Keep: `toggleCheckbox(_:)` (called by CheckboxViewProvider), `applySlashCommand(_:to:)`, `clearCompleted()`, `clearAll()`, `parse()`, `serialize()`

## What Stays the Same

- ContentView outer shell (ZStack, background, tab bar, settings popover)
- NoteEditorView structure (body becomes NoteTextViewRepresentable + slash menu overlay in ZStack)
- TabBar, TabItemView, RenameField, TabClickHandler
- NoteModel, NoteStore, GlobalSettings, PersistenceManager (core logic unchanged)
- SettingsView and all sub-views
- HotkeyManager
- SlashCommand enum, SlashMenuOverlay view (rendering unchanged, positioning changed)

## Risks

- **TextKit 2 edge cases**: Known bugs with very long lines. Not relevant for a notes app with wrapping short paragraphs.
- **Cursor preservation**: When slash commands or checkbox toggles rebuild/mutate the attributed string, cursor position must be saved and restored. Save `selectedRange` before mutation, restore (clamped to new length) after.
- **Attachment character counting**: `\u{FFFC}` counts as 1 character in string length. Parser must strip these when extracting text content.
- **Feedback loops**: The `isUpdatingFromModel` flag must be set consistently on ALL paths that mutate text storage programmatically (full rebuild, checkbox toggle, slash command apply). Missing it on any path causes an infinite loop.
