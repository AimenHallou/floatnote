# FloatNote: Better Markdown, Concurrency Migration & Testing

**Date:** 2026-03-28
**Status:** Draft

---

## 1. Overview

Three improvements to FloatNote:

1. **Better Markdown** — Full inline formatting (bold, italic, code, links) and block-level additions (code blocks, blockquotes, numbered lists) using Apple's `swift-markdown` parser with existing custom attachments preserved.
2. **Concurrency Migration** — Incremental migration from Combine/ObservableObject to `@Observable`/`@MainActor`. Bump deployment target to macOS 14.
3. **Testing** — Comprehensive Swift Testing suite covering model correctness, `AttributedStringBuilder` round-trips, persistence I/O, and snapshot visual regression.

---

## 2. Better Markdown

### 2.1 Problem

Current markdown support is minimal: `# heading`, `• bullet`, `- [x] checkbox`, `---` divider. No inline formatting. The hand-rolled parser in `NoteModel.parse()`/`serialize()` and `AttributedStringBuilder` only handles these four line-level styles.

### 2.2 Approach: Hybrid — `swift-markdown` + Custom Attachments

Use Apple's [`swift-markdown`](https://github.com/apple/swift-markdown) package to parse standard markdown into an AST. Walk the AST to produce `NSAttributedString`. Keep existing `CheckboxAttachment`, `DividerAttachment`, and slash command system as custom extensions.

### 2.3 New Capabilities

**Inline formatting:**
- `**bold**` → `NSFont.boldSystemFont` / `.bold` trait
- `*italic*` → `.italic` trait
- `` `inline code` `` → monospace font + subtle background color
- `[link text](url)` → `NSAttributedString.Key.link` + underline + accent color

**Block-level additions:**
- Fenced code blocks (`` ``` ``) → monospace font, background fill, no spell-check
- `> blockquote` → indented paragraph style + left border (drawn via `NSLayoutManager` or a thin `NSTextAttachment`)
- `1. numbered list` → auto-incrementing prefix, same paragraph style as bullets

### 2.4 Architecture

**New dependency in `Package.swift`:**
```swift
.package(url: "https://github.com/apple/swift-markdown", from: "0.5.0")
```

**Parsing pipeline:**
```
User types markdown text
        │
        ▼
NoteModel.serialize() ──► plain markdown string (stored as .txt)
        │
        ▼
swift-markdown parses ──► Markup AST
        │
        ▼
MarkdownRenderer walks AST ──► NSMutableAttributedString
        │
        ▼
Custom pass: inject CheckboxAttachment, DividerAttachment
        │
        ▼
NoteTextView displays NSAttributedString
```

**Round-trip (display → model):**
```
NSTextStorage
        │
        ▼
AttributedStringBuilder.parseLines() ──► [NoteLine]
        │
        ▼
NoteModel.serialize() ──► plain markdown text
```

**Key files changed:**
- `Package.swift` — add `swift-markdown` dependency
- `AttributedStringBuilder.swift` — `parseLines()` rewritten to use paragraph index enumeration instead of `fullString.range(of:)` (fixes duplicate-line bug where identical paragraphs read attributes from the wrong range). Updated to detect and strip prefixes for new styles: `> ` for blockquotes, `N. ` for numbered lists. Code block lines identified by `.floatNoteLineStyle` attribute.
- `NoteModel.swift` — `LineStyle` enum extended with `.codeBlock`, `.blockquote`, `.numberedList`. `parse()`/`serialize()` updated. Code blocks use multiple `NoteLine` entries each tagged `.codeBlock` — the opening/closing `` ``` `` fences are stored in serialize format and parsed as block boundaries. `parseLines()` strips `> ` prefix for blockquotes and `N. ` prefix for numbered lists.
- `NoteTextView.swift` — `SlashCommand` extended with new block types. Smart Enter behavior for numbered lists (auto-increment) and blockquotes (continue `> ` prefix).
- `ContentView.swift` — slash menu updated with new command options.

**New file:**
- `MarkdownRenderer.swift` — Conforms to `MarkupVisitor` protocol (from `swift-markdown`). Implements `visit` methods for each AST node type, accumulating into an `NSMutableAttributedString`. Handles inline emphasis nesting, code spans, links, block containers. Delegates checkbox/divider rendering to existing attachment classes.

**Note:** `swift-markdown` provides `MarkupVisitor` (protocol with typed return values) and `MarkupWalker` (protocol with void visits). We use `MarkupWalker` since we accumulate into a mutable `NSMutableAttributedString` property rather than returning values from each visit.

### 2.5 Custom Extension Handling

`swift-markdown` supports GitHub Flavored Markdown (GFM) extensions including task list items. Strategy:

1. **Checkboxes:** Parse with `Document(parsing: text, options: [.parseBlockDirectives])` or GFM extensions. `swift-markdown` parses `- [x]`/`- [ ]` as `ListItem` nodes with a `Checkbox` child. The `MarkdownRenderer` converts these directly to `CheckboxAttachment` instances — no sentinel/placeholder system needed.
2. **Dividers:** `swift-markdown` parses `---` as a `ThematicBreak` node. The `MarkdownRenderer` converts this directly to a `DividerAttachment`.
3. **Fallback:** If `swift-markdown`'s GFM checkbox support is insufficient (e.g., doesn't distinguish checked vs unchecked), fall back to a pre-parse scan that extracts checkbox state before AST parsing.

### 2.6 Persistence Format

No change. Notes are still stored as plain `.txt` files containing markdown text. The richer rendering is purely a display concern — the source format is standard markdown plus the existing `- [x]`/`- [ ]` convention (which is GitHub-flavored markdown anyway).

### 2.7 Scope Exclusions

- No image embedding (future work)
- No tables (complexity vs. value for a sticky note app)
- No LaTeX/math rendering (future work)
- No syntax highlighting inside code blocks (just monospace + background)

---

## 3. Concurrency Migration

### 3.1 Problem

The app uses Combine (`ObservableObject`, `@Published`, `combineLatest`, `sink`) for reactive state. This works but is verbose — 9 subscriptions across the codebase, mostly for merging per-note overrides with global settings. Modern Swift offers `@Observable` which eliminates most of this boilerplate.

### 3.2 Approach: Incremental Migration

**Deployment target bump:** macOS 13 → macOS 14 (Ventura is <5% market share, out of Apple's security support).

**Migrate 4 classes:**

| Class | Current | After |
|-------|---------|-------|
| `GlobalSettings` | `ObservableObject` + 4 `@Published` | `@Observable @MainActor` |
| `NoteModel` | `ObservableObject` + 7 `@Published` + 4 `combineLatest`/`sink` chains | `@Observable @MainActor`, computed properties replace pipelines |
| `NoteStore` | `ObservableObject` + 2 `@Published` | `@Observable @MainActor` |
| `SlashMenuState` | `ObservableObject` + 4 `@Published` | `@Observable @MainActor` |

**Combine elimination in `NoteModel`:**

The 4 `combineLatest` + `sink` pipelines that merge per-note overrides with global settings become computed properties:

```swift
// Before (Combine)
globalSettings.$fontSize.combineLatest($fontSizeOverride)
    .sink { global, override in self.effectiveFontSize = override ?? global }
    .store(in: &effectiveCancellables)

// After (@Observable)
var effectiveFontSize: Double {
    fontSizeOverride ?? globalSettings.fontSize
}
```

SwiftUI automatically tracks reads of both `fontSizeOverride` and `globalSettings.fontSize`, so views re-render when either changes. No subscription needed.

**Combine elimination in `AppDelegate`:**

The opacity `combineLatest` pipeline that updates `panel.alphaValue` uses `withObservationTracking` with recursive re-registration:

```swift
func observeOpacity() {
    withObservationTracking {
        panel.alphaValue = CGFloat(store.activeNote?.effectiveOpacity ?? 0.85)
    } onChange: {
        DispatchQueue.main.async { [weak self] in
            self?.observeOpacity()  // must re-register — fires only once per change
        }
    }
}
```

**Important:** `withObservationTracking`'s `onChange` closure fires exactly once, then tracking stops. The recursive call to `observeOpacity()` re-registers the observation. Missing this creates a "one update then silence" bug.

**SwiftUI view property wrapper updates:**
- `@StateObject` → `@State`
- `@ObservedObject` → plain `let`/`var`
- `.environmentObject()` → `.environment()`
- `@EnvironmentObject` → `@Environment(Type.self)`

**Left alone:**
- `HotkeyManager` — C callback via `CGEvent.tapCreate`, no benefit from async migration
- `PersistenceManager` — singleton with no Combine usage

### 3.3 Migration Order

1. `SlashMenuState` — trivial, 4 properties, no Combine pipelines, low risk warmup
2. `GlobalSettings` — open up `private init()` to accept injected `UserDefaults` for testability (add `init(defaults:)` while keeping `static let shared` using default `UserDefaults.standard`)
3. `NoteModel` — largest change, computed properties replace 4 pipelines + remove `effectiveCancellables`. Accept injected `GlobalSettings` instance instead of hard-coding `GlobalSettings.shared` (line 196). This validates the computed-property approach before touching the container.
4. `NoteStore` — depends on `NoteModel`, straightforward now that `NoteModel` is migrated
5. `AppDelegate` opacity pipeline — replace with `withObservationTracking` recursive pattern
6. Update all SwiftUI views to new property wrappers
7. Remove `import Combine` from `NoteModel.swift` and `AppDelegate.swift`

### 3.4 Known Tradeoff: Main-Thread File I/O

`NoteModel.init` calls `PersistenceManager.shared.loadNote(id:)` and `loadNoteConfig(id:)` synchronously. Once `NoteModel` is `@MainActor`, these run on the main thread. This is the existing behavior (already on main thread in practice), but `@MainActor` makes it explicit. For a notes app with small text files, this is acceptable. If notes grow large, file reads can be moved to `Task.detached` in the future.

---

## 4. Testing

### 4.1 Problem

Zero tests exist. No test infrastructure. Bugs in parse/serialize, attributed string round-trips, checkbox behavior, and persistence can go undetected.

### 4.2 Approach: Swift Testing + Injectable Persistence + Snapshots

**Framework:** Swift Testing (`@Test`, `@Suite`, `#expect`, `#require`). Parameterized tests for exhaustive edge case coverage.

**Snapshot library:** `swift-snapshot-testing` (pointfreeco) for visual regression of rendered `NSAttributedString`.

### 4.3 Package.swift Changes

```swift
// swift-tools-version: 5.9
let package = Package(
    name: "FloatNote",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FloatNote",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            path: "Sources/FloatNote",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "FloatNoteTests",
            dependencies: [
                "FloatNote",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests/FloatNoteTests"
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", from: "0.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ]
)
```

### 4.4 Prerequisite: Injectable Persistence

`PersistenceManager` must accept injected `UserDefaults` + directory so tests don't touch real user data.

```swift
final class PersistenceManager {
    static let shared = PersistenceManager()

    private let defaults: UserDefaults
    private let notesDirectory: URL

    convenience init() {
        self.init(defaults: .standard, notesDirectory: /* existing logic */)
    }

    init(defaults: UserDefaults, notesDirectory: URL) {
        self.defaults = defaults
        self.notesDirectory = notesDirectory
    }
}
```

`NoteModel`, `NoteStore`, `GlobalSettings` accept optional `persistence` parameter (defaults to `.shared`). `GlobalSettings` opens its `private init()` to accept injected `UserDefaults` (see section 3.3 step 2). `NoteModel` accepts an injected `GlobalSettings` instance instead of hard-coding `GlobalSettings.shared`.

**Injection strategy:** Constructor injection only — no protocol/mock needed for `PersistenceManager`. Tests use a real `PersistenceManager` with an isolated `UserDefaults(suiteName:)` and a temp directory. This gives real I/O behavior in an isolated environment that gets cleaned up after tests. A `TestPersistenceHelper` provides factory methods for creating isolated instances.

### 4.5 Test Suite Structure

```
Tests/FloatNoteTests/
├── NoteModelParseTests.swift      — parse/serialize round-trips
├── NoteModelCommandTests.swift    — slash commands, clearCompleted
├── NoteStoreTests.swift           — add/remove/reorder notes
├── AttributedStringBuilderTests.swift — model ↔ NSAttributedString round-trips
├── PersistenceManagerTests.swift  — file I/O + UserDefaults with isolated env
├── SnapshotTests.swift            — visual regression for rendered notes
└── Helpers/
    └── TestPersistenceHelper.swift — factory for isolated PersistenceManager (temp dir + unique UserDefaults suite)
```

### 4.6 Test Coverage Plan

**NoteModelParseTests — "todos work, no weird outputs":**

| Test | What it catches |
|------|----------------|
| `- [x] text` → parse → serialize → re-parse = identical | Checkbox data loss |
| `- [ ] text` unchecked round-trip | False positive checked state |
| `# Heading` round-trip | Style loss |
| `• Bullet` round-trip | Prefix corruption |
| `---` divider round-trip | Divider treated as text |
| Empty string | Crash on empty input |
| Single newline | Off-by-one |
| 100+ lines | Performance, no truncation |
| Lines with only whitespace | Spurious style detection |
| `**bold**` and `*italic*` round-trip | New inline formatting |
| `` `code` `` round-trip | Backtick escaping |
| Nested `**bold *and italic***` | Nesting correctness |
| `> blockquote` round-trip | New block style |
| Fenced code block round-trip | Multi-line block preservation |
| `1. numbered list` round-trip | Numbering preservation |
| Mixed: heading + checkbox + bold text | Combined feature interaction |
| Unicode / emoji in text | Encoding correctness |
| `- [x]` with no text after | Edge case: empty checkbox |

All implemented as parameterized `@Test(arguments:)` where possible.

**NoteModelCommandTests:**

| Test | What it catches |
|------|----------------|
| `applySlashCommand(.todo, to: lineId)` adds checkbox | Command application |
| `applySlashCommand(.heading, to: lineId)` on checkbox line removes checkbox | Style conflict |
| `applySlashCommand(.plainText, to: lineId)` strips all formatting | Reset behavior |
| `clearCompleted` removes only checked items | Over/under deletion |
| `clearCompleted` on empty note | Crash on empty |
| Apply command to nonexistent lineId | Graceful no-op |

**NoteStoreTests:**

| Test | What it catches |
|------|----------------|
| `addNote` increments count, sets activeNoteId | Basic state |
| `removeNote` on last note refuses | Data loss prevention |
| `removeNote` updates activeNoteId to neighbor | Active note consistency |
| `load` with no saved data creates default note | First-launch |

**AttributedStringBuilderTests (main thread, `@MainActor`):**

| Test | What it catches |
|------|----------------|
| `build()` → `parseLines()` round-trip for every `LineStyle` | Render/parse mismatch |
| Checkbox attachment present in built string | Attachment creation |
| Strikethrough applied to checked checkbox text | Visual correctness |
| Bold/italic attributes present for inline markdown | New formatting renders |
| Code span gets monospace font | Font assignment |
| Duplicate lines round-trip correctly | Regression test for fixed `parseLines` duplicate-text bug |
| Empty line between paragraphs | Paragraph boundary handling |

**PersistenceManagerTests (isolated temp dir + UserDefaults suite):**

| Test | What it catches |
|------|----------------|
| `saveNote` / `loadNote` round-trip | File I/O correctness |
| `saveNoteConfig` / `loadNoteConfig` round-trip | Codable encoding |
| `deleteNote` removes file and config | Cleanup completeness |
| Load nonexistent note returns empty string | Graceful fallback |
| Save with unicode content | Encoding |
| Concurrent saves don't corrupt | Thread safety |

**SnapshotTests (`@MainActor`, `.serialized`):**

| Test | What it catches |
|------|----------------|
| Heading renders at 1.4× size, bold | Typography regression |
| Checkbox renders with SF Symbol | Attachment visual |
| Divider renders full-width line | Divider visual |
| Code block renders with background | New feature visual |
| Blockquote renders with indent + border | New feature visual |
| Mixed note with all styles | Integration visual |

**Snapshot environment note:** Text rendering varies across macOS versions and display scales. Snapshots are validated locally only — CI runs unit tests but skips snapshot comparisons. Reference images are committed to git but treated as advisory. If snapshot tests are later added to CI, pin to a specific macOS runner version and use `precision: 0.99` tolerance to absorb minor font rendering differences.

---

## 5. Implementation Order

The three workstreams have dependencies:

```
1. Concurrency migration (no deps, enables cleaner test code)
        │
        ▼
2. Testing infrastructure (injectable persistence, test target, MockPersistence)
        │
        ▼
3. Better markdown (swift-markdown integration, new MarkdownRenderer)
        │
        ▼
4. Tests for new markdown features (extend existing test suite)
```

**Rationale:** Concurrency first because it simplifies the model layer that tests and markdown both depend on. Testing infrastructure second so markdown work is immediately testable. Markdown last because it's the largest change and benefits from both the cleaner model and the test safety net.

---

## 6. Dependencies Added

| Package | Version | Purpose |
|---------|---------|---------|
| `swift-markdown` | 0.5.0+ | Markdown AST parsing |
| `swift-snapshot-testing` | 1.17.0+ | Visual regression testing |

---

## 7. Scope Exclusions

- No image embedding
- No table support
- No LaTeX/math rendering
- No syntax highlighting in code blocks (just monospace)
- No XCTest — Swift Testing only
- No full Combine removal from `HotkeyManager`
- No `async/await` for file I/O (simple `Task.detached` if needed, not a full actor)
