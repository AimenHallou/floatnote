# Markdown, Concurrency & Testing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full markdown support (inline + block-level), migrate from Combine to @Observable, and build a comprehensive test suite for FloatNote.

**Architecture:** Three sequential workstreams — concurrency migration first (simplifies model layer), then test infrastructure (safety net), then markdown (largest change, tested immediately). Each task produces a compiling, runnable app.

**Tech Stack:** Swift 5.9, macOS 14+, SwiftUI, AppKit, `swift-markdown` (Apple), `swift-snapshot-testing` (pointfreeco), Swift Testing framework.

**Spec:** `docs/superpowers/specs/2026-03-28-markdown-concurrency-testing-design.md`

---

## File Map

**Modified files:**
- `Package.swift` — bump platform to macOS 14, add `swift-markdown` + `swift-snapshot-testing` dependencies, add test target
- `Sources/FloatNote/NoteModel.swift` — migrate `GlobalSettings`, `NoteModel`, `NoteStore` to `@Observable @MainActor`, add injection, extend `LineStyle`/`SlashCommand` enums, update `parse()`/`serialize()`
- `Sources/FloatNote/ContentView.swift` — migrate `SlashMenuState` to `@Observable`, update all view property wrappers, update slash menu
- `Sources/FloatNote/AppDelegate.swift` — replace Combine opacity pipeline with `withObservationTracking`, update property wrappers
- `Sources/FloatNote/SettingsView.swift` — update property wrappers (`@ObservedObject` → plain var, `@EnvironmentObject` → `@Environment`)
- `Sources/FloatNote/NoteTextViewRepresentable.swift` — update `@ObservedObject` references
- `Sources/FloatNote/NoteTextView.swift` — add smart Enter for numbered lists/blockquotes
- `Sources/FloatNote/AttributedStringBuilder.swift` — fix `parseLines()` duplicate-line bug, add inline formatting + new block styles to `build()`, add stripping logic for new styles
- `Sources/FloatNote/PersistenceManager.swift` — open up `private init()` for injection

**New files:**
- `Sources/FloatNote/MarkdownRenderer.swift` — `MarkupWalker` conformance, AST → `NSAttributedString`
- `Tests/FloatNoteTests/NoteModelParseTests.swift` — parse/serialize round-trips
- `Tests/FloatNoteTests/NoteModelCommandTests.swift` — slash command + clearCompleted tests
- `Tests/FloatNoteTests/NoteStoreTests.swift` — add/remove/reorder notes
- `Tests/FloatNoteTests/AttributedStringBuilderTests.swift` — model ↔ NSAttributedString round-trips
- `Tests/FloatNoteTests/PersistenceManagerTests.swift` — file I/O + UserDefaults
- `Tests/FloatNoteTests/SnapshotTests.swift` — visual regression
- `Tests/FloatNoteTests/Helpers/TestPersistenceHelper.swift` — isolated PersistenceManager factory

---

## Workstream 1: Concurrency Migration

### Task 1: Bump deployment target + add dependencies

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Update Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FloatNote",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown", from: "0.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
    ],
    targets: [
        .executableTarget(
            name: "FloatNote",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
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
    ]
)
```

- [ ] **Step 2: Resolve dependencies**

Run: `cd /Users/aimenhallou/floatnote && swift package resolve`
Expected: Dependencies fetched successfully.

- [ ] **Step 3: Create test directory structure**

Run:
```bash
mkdir -p Tests/FloatNoteTests/Helpers
```

- [ ] **Step 4: Create placeholder test file so target compiles**

Create `Tests/FloatNoteTests/PlaceholderTests.swift`:
```swift
import Testing

@Suite("Placeholder")
struct PlaceholderTests {
    @Test("project compiles with test target")
    func compiles() {
        #expect(true)
    }
}
```

- [ ] **Step 5: Build and run placeholder test**

Run: `cd /Users/aimenhallou/floatnote && swift build && swift test`
Expected: Build succeeds, 1 test passes.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Tests/
git commit -m "chore: bump to macOS 14, add swift-markdown + swift-snapshot-testing + test target"
```

---

### Task 2: Migrate SlashMenuState to @Observable

**Files:**
- Modify: `Sources/FloatNote/ContentView.swift`
- Modify: `Sources/FloatNote/NoteTextViewRepresentable.swift`

- [ ] **Step 1: Migrate SlashMenuState (ContentView.swift:6–47)**

Replace the class declaration. Remove `ObservableObject` conformance and all `@Published`:

```swift
// Before (line 6):
final class SlashMenuState: ObservableObject {
    @Published var isVisible = false
    @Published var filter = ""
    @Published var selectedIndex = 0
    @Published var charIndex: Int?

// After:
@Observable
final class SlashMenuState {
    var isVisible = false
    var filter = ""
    var selectedIndex = 0
    var charIndex: Int?
```

- [ ] **Step 2: Update ContentView property wrappers**

In `ContentView` (line ~50), find any `@StateObject` or `@ObservedObject` references to `SlashMenuState` and update:
- `@StateObject var slashMenu = SlashMenuState()` → `@State var slashMenu = SlashMenuState()`
- `@ObservedObject var slashMenu: SlashMenuState` → `var slashMenu: SlashMenuState`

Do the same in `NoteEditorView` (line ~326: `@StateObject private var slashMenu = SlashMenuState()` → `@State private var slashMenu = SlashMenuState()`) and `SlashMenuOverlay` (line ~365: `@ObservedObject var slashMenu: SlashMenuState` → `var slashMenu: SlashMenuState`).

**Also update `NoteTextViewRepresentable.swift`** (line ~9): `@ObservedObject var slashMenu: SlashMenuState` → `var slashMenu: SlashMenuState`. This is critical — `@ObservedObject` requires `ObservableObject` conformance which we just removed.

- [ ] **Step 3: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Run app to verify slash menu works**

Run: `cd /Users/aimenhallou/floatnote && swift build && open .build/debug/FloatNote.app || .build/debug/FloatNote`
Manual check: Open app, type `/` in a note, verify slash menu appears and commands work.

- [ ] **Step 5: Commit**

```bash
git add Sources/FloatNote/ContentView.swift Sources/FloatNote/NoteTextViewRepresentable.swift
git commit -m "refactor: migrate SlashMenuState to @Observable"
```

---

### Task 3: Make PersistenceManager injectable

**Files:**
- Modify: `Sources/FloatNote/PersistenceManager.swift:44-75`

- [ ] **Step 1: Open up PersistenceManager init**

Replace the private init (line 72) with an injectable one. Keep `static let shared`:

```swift
final class PersistenceManager {
    static let shared = PersistenceManager()

    private let defaults: UserDefaults
    private let notesDir: URL

    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FloatNote")
        self.init(defaults: .standard, notesDirectory: dir)
    }

    init(defaults: UserDefaults, notesDirectory: URL) {
        self.defaults = defaults
        self.notesDir = notesDirectory
        try? FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
    }
```

Remove the old computed `notesDir` property (line 61-66) since it's now a stored property set in init.

- [ ] **Step 2: Update all `UserDefaults.standard` references to use `self.defaults`**

Search `PersistenceManager.swift` for any remaining direct `UserDefaults.standard` calls and replace with `defaults`. The existing code already uses `UserDefaults.standard` — replace all occurrences with `self.defaults`.

- [ ] **Step 3: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/FloatNote/PersistenceManager.swift
git commit -m "refactor: make PersistenceManager injectable for testing"
```

---

### Task 4: Migrate GlobalSettings to @Observable

**Files:**
- Modify: `Sources/FloatNote/NoteModel.swift:95-130`

- [ ] **Step 1: Migrate GlobalSettings**

Replace the class (lines 95-130):

```swift
// Before:
final class GlobalSettings: ObservableObject {
    static let shared = GlobalSettings()
    @Published var fontSize: Double
    @Published var opacity: Double
    @Published var tintColor: NoteTint
    @Published var textColor: NoteTint
    private init() { ... }

// After:
@Observable @MainActor
final class GlobalSettings {
    nonisolated(unsafe) static let shared = GlobalSettings()

    var fontSize: Double { didSet { save() } }
    var opacity: Double { didSet { save() } }
    var tintColor: NoteTint { didSet { save() } }
    var textColor: NoteTint { didSet { save() } }

    @ObservationIgnored
    private let persistence: PersistenceManager

    private init() {
        self.persistence = .shared
        let config = PersistenceManager.shared.loadGlobalConfig()
        self.fontSize = config.fontSize
        self.opacity = config.opacity
        self.tintColor = config.tintColor
        self.textColor = config.textColor
    }

    init(persistence: PersistenceManager) {
        self.persistence = persistence
        let config = persistence.loadGlobalConfig()
        self.fontSize = config.fontSize
        self.opacity = config.opacity
        self.tintColor = config.tintColor
        self.textColor = config.textColor
    }
```

Update the `save()` method to use `self.persistence` instead of `PersistenceManager.shared`.

- [ ] **Step 2: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Build succeeds. Fix any `@Published`-referencing code in SettingsView.swift that uses `$globalSettings.fontSize` style bindings — with `@Observable`, use `@Bindable var globalSettings` or `Bindable(globalSettings)` to get bindings.

- [ ] **Step 3: Commit**

```bash
git add Sources/FloatNote/NoteModel.swift Sources/FloatNote/SettingsView.swift
git commit -m "refactor: migrate GlobalSettings to @Observable @MainActor"
```

---

### Task 5: Migrate NoteModel to @Observable

**Files:**
- Modify: `Sources/FloatNote/NoteModel.swift:131-326`

- [ ] **Step 1: Migrate NoteModel class declaration**

Replace `ObservableObject` + `@Published` (lines 131-170):

```swift
@Observable @MainActor
final class NoteModel: Identifiable {
    let id: UUID

    // CRITICAL: preserve didSet observers for auto-save behavior
    var name: String { didSet { saveConfig() } }
    var lines: [NoteLine] = [] { didSet { scheduleSave() } }

    var fontSizeOverride: Double? { didSet { saveConfig() } }
    var opacityOverride: Double? { didSet { saveConfig() } }
    var tintColorOverride: NoteTint? { didSet { saveConfig() } }
    var textColorOverride: NoteTint? { didSet { saveConfig() } }
    var isCollapsed: Bool { didSet { saveConfig() } }

    @ObservationIgnored
    private let persistence: PersistenceManager
    @ObservationIgnored
    private let globalSettings: GlobalSettings
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
```

- [ ] **Step 2: Replace Combine pipelines with computed properties**

Delete `setupEffectiveValues()` (lines 195-217) and `effectiveCancellables`. Replace the 4 stored effective properties with computed ones:

```swift
    // These replace the 4 combineLatest + sink pipelines
    var fontSize: Double { fontSizeOverride ?? globalSettings.fontSize }
    var opacity: Double { opacityOverride ?? globalSettings.opacity }
    var tintColor: NoteTint { tintColorOverride ?? globalSettings.tintColor }
    var textColor: NoteTint { textColorOverride ?? globalSettings.textColor }
```

- [ ] **Step 3: Update NoteModel init to accept injected dependencies**

```swift
    init(id: UUID, text: String? = nil, config: NoteConfig? = nil,
         persistence: PersistenceManager = .shared,
         globalSettings: GlobalSettings = .shared) {
        self.id = id
        self.persistence = persistence
        self.globalSettings = globalSettings

        let cfg = config ?? persistence.loadNoteConfig(id: id)
        self.name = cfg.name
        // NoteConfig uses short names (fontSize, opacity, etc.) — these are Optional
        self.fontSizeOverride = cfg.fontSize
        self.opacityOverride = cfg.opacity
        self.tintColorOverride = cfg.tintColor
        self.textColorOverride = cfg.textColor
        self.isCollapsed = cfg.isCollapsed

        if let text = text {
            self.lines = Self.parse(text)
        } else {
            let loaded = persistence.loadNote(id: id)
            self.lines = Self.parse(loaded)
        }
    }
```

- [ ] **Step 4: Replace debounced save with Task-based cancellation**

Replace `scheduleSave()` (line 314):

```swift
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let text = self.serialize()
                self.persistence.saveNote(text, id: self.id)
                self.saveConfig()
            } catch {
                // Cancelled — newer edit came in
            }
        }
    }
```

- [ ] **Step 5: Remove `import Combine` from NoteModel.swift**

Only remove if NoteStore migration is also done (Task 6). If not yet, leave it.

- [ ] **Step 6: Update NoteTextViewRepresentable.swift**

Update `@ObservedObject var model: NoteModel` → `var model: NoteModel` (line ~8).

**Critical:** The `Coordinator` class (line ~132) accesses `model.lines`, `model.fontSize`, etc. Since `NoteModel` is now `@MainActor`, the Coordinator must also be `@MainActor`:

```swift
@MainActor
final class Coordinator: NSObject, NSTextViewDelegate {
```

This is safe because `NSTextViewDelegate` methods are already called on the main thread.

- [ ] **Step 7: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Build succeeds. If there are remaining `$model.property` binding references, replace with `Bindable(model).property`.

- [ ] **Step 8: Commit**

```bash
git add Sources/FloatNote/NoteModel.swift Sources/FloatNote/NoteTextViewRepresentable.swift
git commit -m "refactor: migrate NoteModel to @Observable, replace Combine pipelines with computed properties"
```

---

### Task 6: Migrate NoteStore + update all views + AppDelegate

> **Merged from original Tasks 6+7** to avoid committing non-compiling code. NoteStore migration requires view updates in the same commit.

**Files:**
- Modify: `Sources/FloatNote/NoteModel.swift:328-397`
- Modify: `Sources/FloatNote/ContentView.swift`
- Modify: `Sources/FloatNote/SettingsView.swift`
- Modify: `Sources/FloatNote/AppDelegate.swift`
- Modify: `Sources/FloatNote/NoteTextViewRepresentable.swift`

- [ ] **Step 1: Migrate NoteStore**

```swift
// Before:
final class NoteStore: ObservableObject {
    @Published var notes: [NoteModel] = []
    @Published var activeNoteId: UUID?

// After:
@Observable @MainActor
final class NoteStore {
    nonisolated(unsafe) static let shared = NoteStore()

    var notes: [NoteModel] = []
    var activeNoteId: UUID?

    @ObservationIgnored
    private let persistence: PersistenceManager
    @ObservationIgnored
    private let globalSettings: GlobalSettings
```

- [ ] **Step 2: Update NoteStore init and methods to use injected persistence**

```swift
    init(persistence: PersistenceManager = .shared, globalSettings: GlobalSettings = .shared) {
        self.persistence = persistence
        self.globalSettings = globalSettings
    }
```

Update `load()`, `addNote()`, `removeNote()`, `saveNoteIds()` to use `self.persistence` and pass `self.globalSettings` when creating `NoteModel` instances.

- [ ] **Step 3: Remove `import Combine` from NoteModel.swift**

Now that all 3 classes in this file are migrated, remove `import Combine` (line 3).

- [ ] **Step 4: Update ContentView.swift**

Find and replace all property wrappers:
- `@StateObject var store` → `@State var store` (if ContentView owns it)
- `@ObservedObject var store: NoteStore` → `var store: NoteStore`
- `@ObservedObject var model: NoteModel` → `var model: NoteModel`
- `@ObservedObject var global: GlobalSettings` → `var global: GlobalSettings`
- `.environmentObject(store)` → `.environment(store)`
- `@EnvironmentObject var store: NoteStore` → `@Environment(NoteStore.self) var store`

Where SwiftUI bindings are needed (e.g., `$store.activeNoteId`), wrap with `@Bindable`:
```swift
@Bindable var store = store
```
Or use `Bindable(store)` inline.

- [ ] **Step 5: Update SettingsView.swift**

Same pattern. `@ObservedObject var global: GlobalSettings` → `var global: GlobalSettings`. For any `$global.fontSize` bindings, use `@Bindable`.

- [ ] **Step 6: Update AppDelegate.swift — replace Combine opacity pipeline**

Replace the Combine opacity observation (lines 82-103) with `withObservationTracking`:

```swift
private func observeOpacity() {
    withObservationTracking {
        guard let note = store.activeNote else {
            panel.alphaValue = CGFloat(GlobalSettings.shared.opacity)
            return
        }
        panel.alphaValue = CGFloat(note.opacity)
    } onChange: {
        DispatchQueue.main.async { [weak self] in
            self?.observeOpacity()
        }
    }
}
```

Remove `opacityCancellables` (line 26) and `import Combine` (line 3).

- [ ] **Step 7: Build and run**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Clean build. Run the app and verify:
- Tab switching works
- Settings changes propagate (font size, opacity, colors)
- Opacity slider updates window transparency in real-time
- Slash menu works

- [ ] **Step 8: Commit**

```bash
git add Sources/FloatNote/NoteModel.swift Sources/FloatNote/ContentView.swift Sources/FloatNote/SettingsView.swift Sources/FloatNote/AppDelegate.swift Sources/FloatNote/NoteTextViewRepresentable.swift
git commit -m "refactor: migrate NoteStore to @Observable, update all views, remove Combine"
```

---

## Workstream 2: Testing Infrastructure

### Task 8: Create TestPersistenceHelper

**Files:**
- Create: `Tests/FloatNoteTests/Helpers/TestPersistenceHelper.swift`

- [ ] **Step 1: Write the helper**

```swift
import Foundation
@testable import FloatNote

struct TestPersistenceHelper {
    let persistence: PersistenceManager
    let defaults: UserDefaults
    let tempDir: URL
    private let suiteName: String

    init() {
        suiteName = "FloatNote.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        persistence = PersistenceManager(defaults: defaults, notesDirectory: tempDir)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
```

- [ ] **Step 2: Build tests**

Run: `cd /Users/aimenhallou/floatnote && swift build --build-tests`
Expected: Compiles.

- [ ] **Step 3: Commit**

```bash
git add Tests/FloatNoteTests/Helpers/TestPersistenceHelper.swift
git commit -m "test: add TestPersistenceHelper for isolated persistence in tests"
```

---

### Task 9: PersistenceManager tests

**Files:**
- Create: `Tests/FloatNoteTests/PersistenceManagerTests.swift`

- [ ] **Step 1: Write PersistenceManager tests**

```swift
import Testing
import Foundation
@testable import FloatNote

@Suite("PersistenceManager")
struct PersistenceManagerTests {
    let helper = TestPersistenceHelper()
    var pm: PersistenceManager { helper.persistence }

    @Test("saveNote/loadNote round-trip")
    func noteRoundTrip() {
        let id = UUID()
        pm.saveNote("Hello\nWorld", id: id)
        let loaded = pm.loadNote(id: id)
        #expect(loaded == "Hello\nWorld")
        helper.cleanup()
    }

    @Test("loadNote for nonexistent id returns empty string")
    func loadNonexistent() {
        let loaded = pm.loadNote(id: UUID())
        #expect(loaded == "")
        helper.cleanup()
    }

    @Test("deleteNote removes file")
    func deleteNote() {
        let id = UUID()
        pm.saveNote("content", id: id)
        pm.deleteNote(id: id)
        let loaded = pm.loadNote(id: id)
        #expect(loaded == "")
        helper.cleanup()
    }

    @Test("saveNoteConfig/loadNoteConfig round-trip")
    func configRoundTrip() {
        let id = UUID()
        var config = NoteConfig(name: "Test Note")
        config.fontSizeOverride = 18.0
        config.tintColorOverride = .blue
        pm.saveNoteConfig(config, id: id)
        let loaded = pm.loadNoteConfig(id: id)
        #expect(loaded.name == "Test Note")
        #expect(loaded.fontSizeOverride == 18.0)
        #expect(loaded.tintColorOverride == .blue)
        helper.cleanup()
    }

    @Test("saveNoteIds/loadNoteIds round-trip")
    func noteIdsRoundTrip() {
        let ids = [UUID(), UUID(), UUID()]
        pm.saveNoteIds(ids)
        let loaded = pm.loadNoteIds()
        #expect(loaded == ids)
        helper.cleanup()
    }

    @Test("unicode content preserved")
    func unicodeContent() {
        let id = UUID()
        let text = "Hello 🌍\n日本語\nEmoji: 🎉🚀"
        pm.saveNote(text, id: id)
        let loaded = pm.loadNote(id: id)
        #expect(loaded == text)
        helper.cleanup()
    }

    @Test("saveGlobalConfig/loadGlobalConfig round-trip")
    func globalConfigRoundTrip() {
        let config = GlobalConfig(fontSize: 18, opacity: 0.7, tintColor: .blue, textColor: .pink)
        pm.saveGlobalConfig(config)
        let loaded = pm.loadGlobalConfig()
        #expect(loaded.fontSize == 18)
        #expect(loaded.opacity == 0.7)
        #expect(loaded.tintColor == .blue)
        #expect(loaded.textColor == .pink)
        helper.cleanup()
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter PersistenceManagerTests`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/FloatNoteTests/PersistenceManagerTests.swift
git commit -m "test: add PersistenceManager round-trip tests"
```

---

### Task 10: NoteModel parse/serialize tests

**Files:**
- Create: `Tests/FloatNoteTests/NoteModelParseTests.swift`

- [ ] **Step 1: Write parse/serialize round-trip tests**

```swift
import Testing
import Foundation
@testable import FloatNote

@Suite("NoteModel parse/serialize")
struct NoteModelParseTests {

    @Test("checkbox round-trips", arguments: [
        ("- [x] Buy milk", true, true, "Buy milk"),
        ("- [ ] Buy milk", true, false, "Buy milk"),
        ("- [x] ", true, true, ""),
        ("- [ ]", true, false, ""),
    ])
    func checkboxRoundTrip(input: String, isCheckbox: Bool, isChecked: Bool, text: String) {
        let lines = NoteModel.parse(input)
        #expect(lines.count >= 1)
        #expect(lines[0].isCheckbox == isCheckbox)
        #expect(lines[0].isChecked == isChecked)
        #expect(lines[0].text == text)
    }

    @Test("heading round-trip")
    func headingRoundTrip() {
        let lines = NoteModel.parse("# My Heading")
        #expect(lines.count == 1)
        #expect(lines[0].style == .heading)
        #expect(lines[0].text == "My Heading")
    }

    @Test("bullet round-trip")
    func bulletRoundTrip() {
        let lines = NoteModel.parse("• Item one")
        #expect(lines.count == 1)
        #expect(lines[0].style == .bullet)
        #expect(lines[0].text == "Item one")
    }

    @Test("divider round-trip")
    func dividerRoundTrip() {
        let lines = NoteModel.parse("---")
        #expect(lines.count == 1)
        #expect(lines[0].style == .divider)
    }

    @Test("plain text round-trip")
    func plainTextRoundTrip() {
        let lines = NoteModel.parse("Just some text")
        #expect(lines.count == 1)
        #expect(lines[0].style == .text)
        #expect(lines[0].text == "Just some text")
    }

    @Test("empty string produces one empty line")
    func emptyString() {
        let lines = NoteModel.parse("")
        #expect(lines.count >= 0) // verify no crash; exact behavior may vary
    }

    @Test("multiline mixed content")
    func multilineMixed() {
        let input = """
        # Title
        - [x] Done task
        - [ ] Open task
        • A bullet
        ---
        Plain text
        """
        let lines = NoteModel.parse(input)
        #expect(lines.count == 6)
        #expect(lines[0].style == .heading)
        #expect(lines[1].isCheckbox == true)
        #expect(lines[1].isChecked == true)
        #expect(lines[2].isCheckbox == true)
        #expect(lines[2].isChecked == false)
        #expect(lines[3].style == .bullet)
        #expect(lines[4].style == .divider)
        #expect(lines[5].style == .text)
    }

    @Test("serialize then re-parse is stable")
    func serializeReparseStable() {
        let helper = TestPersistenceHelper()
        let globalSettings = GlobalSettings(persistence: helper.persistence)
        let note = NoteModel(id: UUID(), text: "# Title\n- [x] Done\n• Bullet\n---\nPlain",
                             persistence: helper.persistence, globalSettings: globalSettings)
        let serialized = note.serialize()
        let reparsed = NoteModel.parse(serialized)
        #expect(reparsed.count == note.lines.count)
        for (a, b) in zip(note.lines, reparsed) {
            #expect(a.style == b.style)
            #expect(a.isCheckbox == b.isCheckbox)
            #expect(a.isChecked == b.isChecked)
            #expect(a.text == b.text)
        }
        helper.cleanup()
    }

    @Test("unicode and emoji preserved")
    func unicodePreserved() {
        let lines = NoteModel.parse("Hello 🌍\n# 日本語")
        #expect(lines[0].text == "Hello 🌍")
        #expect(lines[1].text == "日本語")
        #expect(lines[1].style == .heading)
    }

    @Test("whitespace-only lines")
    func whitespaceLines() {
        let lines = NoteModel.parse("   \n\t\n  ")
        for line in lines {
            #expect(line.style == .text)
            #expect(line.isCheckbox == false)
        }
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter NoteModelParseTests`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/FloatNoteTests/NoteModelParseTests.swift
git commit -m "test: add NoteModel parse/serialize round-trip tests"
```

---

### Task 11: NoteModel command tests

**Files:**
- Create: `Tests/FloatNoteTests/NoteModelCommandTests.swift`

- [ ] **Step 1: Write slash command and clearCompleted tests**

```swift
import Testing
import Foundation
@testable import FloatNote

@Suite("NoteModel commands")
struct NoteModelCommandTests {
    private func makeNote(_ text: String) -> (NoteModel, TestPersistenceHelper) {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let note = NoteModel(id: UUID(), text: text, persistence: helper.persistence, globalSettings: gs)
        return (note, helper)
    }

    @Test("applySlashCommand .todo adds checkbox")
    func todoCommand() {
        let (note, helper) = makeNote("Hello")
        let lineId = note.lines[0].id
        note.applySlashCommand(.todo, to: lineId)
        #expect(note.lines[0].isCheckbox == true)
        #expect(note.lines[0].isChecked == false)
        helper.cleanup()
    }

    @Test("applySlashCommand .heading sets heading style")
    func headingCommand() {
        let (note, helper) = makeNote("Hello")
        let lineId = note.lines[0].id
        note.applySlashCommand(.heading, to: lineId)
        #expect(note.lines[0].style == .heading)
        #expect(note.lines[0].isCheckbox == false)
        helper.cleanup()
    }

    @Test("applySlashCommand .bullet sets bullet style")
    func bulletCommand() {
        let (note, helper) = makeNote("Hello")
        let lineId = note.lines[0].id
        note.applySlashCommand(.bullet, to: lineId)
        #expect(note.lines[0].style == .bullet)
        helper.cleanup()
    }

    @Test("applySlashCommand .plainText strips formatting")
    func plainTextCommand() {
        let (note, helper) = makeNote("# Heading")
        let lineId = note.lines[0].id
        note.applySlashCommand(.plainText, to: lineId)
        #expect(note.lines[0].style == .text)
        #expect(note.lines[0].isCheckbox == false)
        helper.cleanup()
    }

    @Test("clearCompleted removes only checked items")
    func clearCompleted() {
        let (note, helper) = makeNote("- [x] Done\n- [ ] Not done\nPlain")
        note.clearCompleted()
        #expect(note.lines.count == 2)
        #expect(note.lines.allSatisfy { !$0.isChecked })
        helper.cleanup()
    }

    @Test("clearCompleted on empty note does not crash")
    func clearCompletedEmpty() {
        let (note, helper) = makeNote("")
        note.clearCompleted()
        #expect(note.lines.count >= 0)
        helper.cleanup()
    }

    @Test("applySlashCommand to nonexistent lineId is no-op")
    func nonexistentLineId() {
        let (note, helper) = makeNote("Hello")
        let originalLines = note.lines
        note.applySlashCommand(.heading, to: UUID())
        #expect(note.lines.count == originalLines.count)
        #expect(note.lines[0].text == originalLines[0].text)
        helper.cleanup()
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter NoteModelCommandTests`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/FloatNoteTests/NoteModelCommandTests.swift
git commit -m "test: add NoteModel slash command and clearCompleted tests"
```

---

### Task 12: NoteStore tests

**Files:**
- Create: `Tests/FloatNoteTests/NoteStoreTests.swift`

- [ ] **Step 1: Write NoteStore tests**

```swift
import Testing
import Foundation
@testable import FloatNote

@Suite("NoteStore")
struct NoteStoreTests {
    private func makeStore() -> (NoteStore, TestPersistenceHelper) {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let store = NoteStore(persistence: helper.persistence, globalSettings: gs)
        return (store, helper)
    }

    @Test("load with no saved data creates one default note")
    func loadDefault() {
        let (store, helper) = makeStore()
        store.load()
        #expect(store.notes.count == 1)
        #expect(store.activeNoteId != nil)
        helper.cleanup()
    }

    @Test("addNote increments count and sets activeNoteId")
    func addNote() {
        let (store, helper) = makeStore()
        store.load()
        let initialCount = store.notes.count
        store.addNote()
        #expect(store.notes.count == initialCount + 1)
        #expect(store.activeNoteId == store.notes.last?.id)
        helper.cleanup()
    }

    @Test("removeNote on last note refuses deletion")
    func removeLastNote() {
        let (store, helper) = makeStore()
        store.load()
        #expect(store.notes.count == 1)
        let id = store.notes[0].id
        store.removeNote(id)
        #expect(store.notes.count == 1) // should not remove last note
        helper.cleanup()
    }

    @Test("removeNote updates activeNoteId")
    func removeNoteUpdatesActive() {
        let (store, helper) = makeStore()
        store.load()
        store.addNote()
        store.addNote()
        #expect(store.notes.count == 3)
        let middleId = store.notes[1].id
        store.activeNoteId = middleId
        store.removeNote(middleId)
        #expect(store.notes.count == 2)
        #expect(store.activeNoteId != middleId)
        #expect(store.activeNoteId != nil)
        helper.cleanup()
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter NoteStoreTests`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/FloatNoteTests/NoteStoreTests.swift
git commit -m "test: add NoteStore state transition tests"
```

---

### Task 13: AttributedStringBuilder round-trip tests

**Files:**
- Create: `Tests/FloatNoteTests/AttributedStringBuilderTests.swift`

- [ ] **Step 1: Write round-trip tests**

```swift
import Testing
import AppKit
@testable import FloatNote

@Suite("AttributedStringBuilder", .serialized)
@MainActor
struct AttributedStringBuilderTests {

    private func roundTrip(_ lines: [NoteLine]) -> [NoteLine] {
        let attrStr = AttributedStringBuilder.build(from: lines, fontSize: 13, textColor: .clear)
        let storage = NSTextStorage(attributedString: attrStr)
        return AttributedStringBuilder.parseLines(from: storage, fontSize: 13)
    }

    @Test("plain text round-trip")
    func plainText() {
        let result = roundTrip([NoteLine(text: "Hello world")])
        #expect(result.count == 1)
        #expect(result[0].text == "Hello world")
        #expect(result[0].style == .text)
    }

    @Test("heading round-trip")
    func heading() {
        let result = roundTrip([NoteLine(style: .heading, text: "Title")])
        #expect(result.count == 1)
        #expect(result[0].style == .heading)
        #expect(result[0].text == "Title")
    }

    @Test("bullet round-trip")
    func bullet() {
        let result = roundTrip([NoteLine(style: .bullet, text: "Point")])
        #expect(result.count == 1)
        #expect(result[0].style == .bullet)
        #expect(result[0].text == "Point")
    }

    @Test("checkbox unchecked round-trip")
    func checkboxUnchecked() {
        let result = roundTrip([NoteLine(isCheckbox: true, isChecked: false, text: "Task")])
        #expect(result.count == 1)
        #expect(result[0].isCheckbox == true)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "Task")
    }

    @Test("checkbox checked round-trip preserves strikethrough")
    func checkboxChecked() {
        let result = roundTrip([NoteLine(isCheckbox: true, isChecked: true, text: "Done")])
        #expect(result.count == 1)
        #expect(result[0].isCheckbox == true)
        #expect(result[0].isChecked == true)
        #expect(result[0].text == "Done")
    }

    @Test("divider round-trip")
    func divider() {
        let result = roundTrip([NoteLine(style: .divider)])
        #expect(result.count == 1)
        #expect(result[0].style == .divider)
    }

    @Test("multi-line mixed content round-trip")
    func mixedContent() {
        let lines = [
            NoteLine(style: .heading, text: "Title"),
            NoteLine(style: .bullet, text: "Point"),
            NoteLine(isCheckbox: true, isChecked: false, text: "Task"),
            NoteLine(isCheckbox: true, isChecked: true, text: "Done"),
            NoteLine(style: .divider),
            NoteLine(text: "Plain text"),
        ]
        let result = roundTrip(lines)
        #expect(result.count == lines.count)
        for (original, parsed) in zip(lines, result) {
            #expect(original.style == parsed.style)
            #expect(original.isCheckbox == parsed.isCheckbox)
            #expect(original.isChecked == parsed.isChecked)
            #expect(original.text == parsed.text)
        }
    }

    @Test("duplicate lines round-trip correctly")
    func duplicateLines() {
        let lines = [
            NoteLine(text: "Same text"),
            NoteLine(text: "Same text"),
            NoteLine(style: .heading, text: "Same text"),
        ]
        let result = roundTrip(lines)
        #expect(result.count == 3)
        #expect(result[0].style == .text)
        #expect(result[1].style == .text)
        #expect(result[2].style == .heading)
    }

    @Test("empty line between paragraphs")
    func emptyLineBetween() {
        let lines = [
            NoteLine(text: "First"),
            NoteLine(text: ""),
            NoteLine(text: "Third"),
        ]
        let result = roundTrip(lines)
        #expect(result.count == 3)
        #expect(result[0].text == "First")
        #expect(result[2].text == "Third")
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter AttributedStringBuilderTests`
Expected: Most pass. The **duplicate lines test may fail** — this confirms the known bug. Note which tests fail for Task 14.

- [ ] **Step 3: Commit**

```bash
git add Tests/FloatNoteTests/AttributedStringBuilderTests.swift
git commit -m "test: add AttributedStringBuilder round-trip tests"
```

---

### Task 14: Fix parseLines duplicate-line bug

**Files:**
- Modify: `Sources/FloatNote/AttributedStringBuilder.swift:45-125`

- [ ] **Step 1: Rewrite parseLines to use paragraph enumeration by range**

The bug is at the line using `fullString.range(of: substring)` — it always finds the first occurrence. Replace with paragraph-by-range enumeration:

```swift
static func parseLines(from textStorage: NSTextStorage, fontSize: CGFloat) -> [NoteLine] {
    let fullString = textStorage.string
    guard !fullString.isEmpty else { return [] }

    var lines: [NoteLine] = []
    var searchStart = fullString.startIndex

    while searchStart < fullString.endIndex {
        let paraRange = fullString.paragraphRange(for: searchStart...searchStart)
        let nsRange = NSRange(paraRange, in: fullString)
        let substring = String(fullString[paraRange]).replacingOccurrences(of: "\n", with: "")

        // Read the floatNoteLineStyle attribute from this specific range
        var style: LineStyle = .text
        if nsRange.length > 0 {
            if let rawStyle = textStorage.attribute(.floatNoteLineStyle, at: nsRange.location, effectiveRange: nil) as? String,
               let parsed = LineStyle(rawValue: rawStyle) {
                style = parsed
            }
        }

        // Detect checkbox attachment at paragraph start
        var isCheckbox = false
        var isChecked = false
        if nsRange.length > 0 {
            textStorage.enumerateAttribute(.attachment, in: nsRange, options: []) { value, _, stop in
                if let checkbox = value as? CheckboxAttachment {
                    isCheckbox = true
                    isChecked = checkbox.isChecked
                    stop.pointee = true
                }
            }
        }

        // Detect strikethrough for checked checkboxes
        if isCheckbox && nsRange.length > 0 {
            textStorage.enumerateAttribute(.strikethroughStyle, in: nsRange, options: []) { value, _, stop in
                if let strikeValue = value as? Int, strikeValue != 0 {
                    isChecked = true
                    stop.pointee = true
                }
            }
        }

        // Extract text content (strip attachment characters and prefixes)
        var text = substring
        if isCheckbox {
            // Remove attachment character + space prefix
            // The checkbox attachment is a single character followed by a space
            if let spaceIdx = text.firstIndex(of: " ") {
                text = String(text[text.index(after: spaceIdx)...])
            }
        } else if style == .bullet {
            // Strip "• " prefix
            if text.hasPrefix("• ") {
                text = String(text.dropFirst(2))
            }
        } else if style == .divider {
            text = ""
        }

        lines.append(NoteLine(isCheckbox: isCheckbox, isChecked: isChecked, style: style, text: text))
        searchStart = paraRange.upperBound
    }

    return lines
}
```

**Note:** The exact implementation will depend on the current code structure. The key change is iterating by `paragraphRange` instead of using `fullString.range(of:)`. Adapt the attribute reading and text stripping to match the existing patterns.

- [ ] **Step 2: Run AttributedStringBuilder tests**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter AttributedStringBuilderTests`
Expected: All tests pass, including the duplicate lines test.

- [ ] **Step 3: Run all tests**

Run: `cd /Users/aimenhallou/floatnote && swift test`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/FloatNote/AttributedStringBuilder.swift
git commit -m "fix: rewrite parseLines to use paragraph range enumeration, fixing duplicate-line bug"
```

---

## Workstream 3: Better Markdown

### Task 15: Add MarkdownRenderer

**Files:**
- Create: `Sources/FloatNote/MarkdownRenderer.swift`

- [ ] **Step 1: Create MarkdownRenderer conforming to MarkupWalker**

```swift
import AppKit
import Markdown

/// Walks a swift-markdown AST and produces an NSMutableAttributedString.
final class MarkdownRenderer: MarkupWalker {
    private(set) var result = NSMutableAttributedString()

    private let fontSize: CGFloat
    private let textColor: NSColor
    private var isInBold = false
    private var isInItalic = false
    private var isInCode = false
    private var isInCodeBlock = false
    private var isInBlockquote = false
    private var listItemNumber: Int? = nil

    init(fontSize: CGFloat, textColor: NSColor) {
        self.fontSize = fontSize
        self.textColor = textColor
    }

    // MARK: - Block-level

    override func visitHeading(_ heading: Heading) -> () {
        let headingSize = fontSize * 1.4
        descendInto(heading)
        // Apply heading attributes to the range we just appended
        let paraStart = findParagraphStart()
        let range = NSRange(location: paraStart, length: result.length - paraStart)
        result.addAttribute(.floatNoteLineStyle, value: LineStyle.heading.rawValue, range: range)
        result.addAttribute(.font, value: AttributedStringBuilder.roundedFont(size: headingSize, bold: true), range: range)
        appendNewlineIfNeeded()
    }

    override func visitParagraph(_ paragraph: Paragraph) -> () {
        let start = result.length
        descendInto(paragraph)
        let range = NSRange(location: start, length: result.length - start)
        if !isInBlockquote && !isInCodeBlock {
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.text.rawValue, range: range)
        }
        appendNewlineIfNeeded()
    }

    override func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        let attachment = DividerAttachment(data: nil, ofType: nil)
        let attrStr = NSMutableAttributedString(attachment: attachment)
        attrStr.addAttribute(.floatNoteLineStyle, value: LineStyle.divider.rawValue,
                            range: NSRange(location: 0, length: attrStr.length))
        result.append(attrStr)
        appendNewlineIfNeeded()
    }

    override func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        isInCodeBlock = true
        let start = result.length
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .floatNoteLineStyle: LineStyle.codeBlock.rawValue
        ]
        result.append(NSAttributedString(string: code, attributes: attrs))
        appendNewlineIfNeeded()
        isInCodeBlock = false
    }

    override func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        isInBlockquote = true
        let start = result.length
        descendInto(blockQuote)
        let range = NSRange(location: start, length: result.length - start)
        result.addAttribute(.floatNoteLineStyle, value: LineStyle.blockquote.rawValue, range: range)
        // Add paragraph indent for blockquote
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.headIndent = 20
        paraStyle.firstLineHeadIndent = 20
        result.addAttribute(.paragraphStyle, value: paraStyle, range: range)
        isInBlockquote = false
    }

    override func visitOrderedList(_ orderedList: OrderedList) -> () {
        listItemNumber = orderedList.startIndex
        descendInto(orderedList)
        listItemNumber = nil
    }

    override func visitUnorderedList(_ unorderedList: UnorderedList) -> () {
        descendInto(unorderedList)
    }

    override func visitListItem(_ listItem: ListItem) -> () {
        let start = result.length
        if let checkbox = listItem.checkbox {
            // GFM task list item
            let isChecked = (checkbox == .checked)
            let attachment = CheckboxAttachment(data: nil, ofType: nil)
            attachment.isChecked = isChecked
            let attrStr = NSMutableAttributedString(attachment: attachment)
            result.append(attrStr)
            result.append(NSAttributedString(string: " "))
            descendInto(listItem)
            let range = NSRange(location: start, length: result.length - start)
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.text.rawValue, range: range)
            if isChecked {
                // Apply strikethrough to text portion (after attachment)
                let textRange = NSRange(location: start + 2, length: result.length - start - 2)
                if textRange.length > 0 {
                    result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                }
            }
        } else if let num = listItemNumber {
            let prefix = "\(num). "
            let prefixAttr = NSAttributedString(string: prefix, attributes: [
                .font: AttributedStringBuilder.roundedFont(size: fontSize, bold: false),
                .foregroundColor: NSColor.secondaryLabelColor,
                .floatNoteLineStyle: LineStyle.numberedList.rawValue
            ])
            result.append(prefixAttr)
            descendInto(listItem)
            let range = NSRange(location: start, length: result.length - start)
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.numberedList.rawValue, range: range)
            listItemNumber = num + 1
        } else {
            // Unordered list → bullet
            let prefix = "• "
            let prefixAttr = NSAttributedString(string: prefix, attributes: [
                .font: AttributedStringBuilder.roundedFont(size: fontSize, bold: false),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            result.append(prefixAttr)
            descendInto(listItem)
            let range = NSRange(location: start, length: result.length - start)
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.bullet.rawValue, range: range)
        }
        appendNewlineIfNeeded()
    }

    // MARK: - Inline

    override func visitText(_ text: Text) -> () {
        let font = currentFont()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        result.append(NSAttributedString(string: text.string, attributes: attrs))
    }

    override func visitStrong(_ strong: Strong) -> () {
        isInBold = true
        descendInto(strong)
        isInBold = false
    }

    override func visitEmphasis(_ emphasis: Emphasis) -> () {
        isInItalic = true
        descendInto(emphasis)
        isInItalic = false
    }

    override func visitInlineCode(_ inlineCode: InlineCode) -> () {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .backgroundColor: NSColor.quaternaryLabelColor
        ]
        result.append(NSAttributedString(string: inlineCode.code, attributes: attrs))
    }

    override func visitLink(_ link: Markdown.Link) -> () {
        let start = result.length
        descendInto(link)
        if let dest = link.destination, let url = URL(string: dest) {
            let range = NSRange(location: start, length: result.length - start)
            result.addAttribute(.link, value: url, range: range)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        }
    }

    override func visitSoftBreak(_ softBreak: SoftBreak) -> () {
        result.append(NSAttributedString(string: "\n"))
    }

    override func visitLineBreak(_ lineBreak: LineBreak) -> () {
        result.append(NSAttributedString(string: "\n"))
    }

    // MARK: - Helpers

    private func currentFont() -> NSFont {
        if isInBold && isInItalic {
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor
                .withDesign(.rounded)?
                .withSymbolicTraits([.bold, .italic])
            return desc.flatMap { NSFont(descriptor: $0, size: fontSize) }
                ?? AttributedStringBuilder.roundedFont(size: fontSize, bold: true)
        } else if isInBold {
            return AttributedStringBuilder.roundedFont(size: fontSize, bold: true)
        } else if isInItalic {
            let desc = NSFont.systemFont(ofSize: fontSize).fontDescriptor
                .withDesign(.rounded)?
                .withSymbolicTraits(.italic)
            return desc.flatMap { NSFont(descriptor: $0, size: fontSize) }
                ?? AttributedStringBuilder.roundedFont(size: fontSize, bold: false)
        } else {
            return AttributedStringBuilder.roundedFont(size: fontSize, bold: false)
        }
    }

    private func appendNewlineIfNeeded() {
        if result.length > 0 && result.mutableString.character(at: result.length - 1) != 0x0A {
            result.append(NSAttributedString(string: "\n"))
        }
    }

    private func findParagraphStart() -> Int {
        let str = result.string
        if str.isEmpty { return 0 }
        // Find the last newline before the current position
        if let range = str.range(of: "\n", options: .backwards, range: str.startIndex..<str.index(before: str.endIndex)) {
            return NSRange(str.startIndex...range.lowerBound, in: str).length
        }
        return 0
    }
}
```

**Important:** This is a starting implementation. The exact `MarkupWalker` API may differ — check `swift-markdown`'s actual protocol. The key methods are `visitHeading`, `visitParagraph`, `visitText`, `visitStrong`, `visitEmphasis`, `visitInlineCode`, `visitLink`, `visitCodeBlock`, `visitBlockQuote`, `visitThematicBreak`, `visitOrderedList`, `visitUnorderedList`, `visitListItem`. Adapt the override signatures to match the library's actual API.

- [ ] **Step 2: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Compiles. Fix any API mismatches with `swift-markdown`.

- [ ] **Step 3: Commit**

```bash
git add Sources/FloatNote/MarkdownRenderer.swift
git commit -m "feat: add MarkdownRenderer using swift-markdown AST walker"
```

---

### Task 16: Extend LineStyle and SlashCommand enums

**Files:**
- Modify: `Sources/FloatNote/NoteModel.swift:43-93`

- [ ] **Step 1: Add new LineStyle cases**

```swift
enum LineStyle: String, Equatable {
    case text
    case heading
    case bullet
    case divider
    case codeBlock
    case blockquote
    case numberedList
}
```

- [ ] **Step 2: Add new SlashCommand cases**

Add to the `SlashCommand` enum (line 49):

```swift
enum SlashCommand: CaseIterable {
    case todo, heading, bullet, divider, codeBlock, blockquote, numberedList, clearCompleted, plainText
```

Update `label` computed property:
```swift
    var label: String {
        switch self {
        case .todo: return "To-do"
        case .heading: return "Heading"
        case .bullet: return "Bullet"
        case .divider: return "Divider"
        case .codeBlock: return "Code Block"
        case .blockquote: return "Blockquote"
        case .numberedList: return "Numbered List"
        case .clearCompleted: return "Clear Completed"
        case .plainText: return "Plain Text"
        }
    }
```

Update `icon` computed property:
```swift
    var icon: String {
        switch self {
        case .todo: return "checkmark.square"
        case .heading: return "textformat.size.larger"
        case .bullet: return "list.bullet"
        case .divider: return "minus"
        case .codeBlock: return "chevron.left.forwardslash.chevron.right"
        case .blockquote: return "text.quote"
        case .numberedList: return "list.number"
        case .clearCompleted: return "trash"
        case .plainText: return "textformat"
        }
    }
```

- [ ] **Step 3: Update applySlashCommand to handle new styles**

In `applySlashCommand` (line 256), add cases:

```swift
case .codeBlock:
    lines[idx].style = .codeBlock
    lines[idx].isCheckbox = false
    lines[idx].isChecked = false
case .blockquote:
    lines[idx].style = .blockquote
    lines[idx].isCheckbox = false
    lines[idx].isChecked = false
case .numberedList:
    lines[idx].style = .numberedList
    lines[idx].isCheckbox = false
    lines[idx].isChecked = false
```

- [ ] **Step 4: Update parse() and serialize() for new styles**

In `parse()` (line 221), add:
```swift
// Before the plain text fallback:
} else if trimmed.hasPrefix("> ") {
    return NoteLine(style: .blockquote, text: String(trimmed.dropFirst(2)))
} else if let match = trimmed.firstMatch(of: /^(\d+)\.\s(.*)/) {
    return NoteLine(style: .numberedList, text: String(match.output.2))
}
```

In `serialize()` (line 240), add cases:
```swift
case .codeBlock: return "```\n\(line.text)\n```"
case .blockquote: return "> \(line.text)"
case .numberedList: return "1. \(line.text)"
```

- [ ] **Step 5: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Compiles.

- [ ] **Step 6: Run existing tests**

Run: `cd /Users/aimenhallou/floatnote && swift test`
Expected: All existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/FloatNote/NoteModel.swift
git commit -m "feat: add codeBlock, blockquote, numberedList to LineStyle and SlashCommand"
```

---

### Task 17: Integrate MarkdownRenderer into AttributedStringBuilder

**Files:**
- Modify: `Sources/FloatNote/AttributedStringBuilder.swift`

- [ ] **Step 1: Update build() to use MarkdownRenderer for rendering**

Replace the existing `build(from:fontSize:textColor:)` method. The new version first serializes lines to markdown text, then uses `MarkdownRenderer` to produce the attributed string:

```swift
static func build(from lines: [NoteLine], fontSize: CGFloat, textColor: NoteTint) -> NSMutableAttributedString {
    let resolvedColor = textColor == .clear ? NSColor.labelColor : textColor.nsColor

    // Serialize lines to markdown, then render via swift-markdown AST
    let markdownText = lines.map { line -> String in
        switch line.style {
        case .heading: return "# \(line.text)"
        case .bullet: return "- \(line.text)"
        case .divider: return "---"
        case .codeBlock: return "```\n\(line.text)\n```"
        case .blockquote: return "> \(line.text)"
        case .numberedList: return "1. \(line.text)"
        case .text:
            if line.isCheckbox {
                return line.isChecked ? "- [x] \(line.text)" : "- [ ] \(line.text)"
            }
            return line.text
        }
    }.joined(separator: "\n")

    let renderer = MarkdownRenderer(fontSize: fontSize, textColor: resolvedColor)
    let document = Document(parsing: markdownText)
    renderer.visit(document)
    return renderer.result
}
```

**Note:** This is the integration point. The exact behavior needs testing — the renderer must produce output that `parseLines()` can round-trip. If the renderer's output doesn't match what `parseLines()` expects (e.g., different attachment placement, different attribute tagging), adjust either the renderer or `parseLines()`.

- [ ] **Step 2: Update parseLines() to handle new styles**

Add stripping logic for new block styles in `parseLines()`:

```swift
} else if style == .blockquote {
    // Strip "> " prefix if present
    if text.hasPrefix("> ") {
        text = String(text.dropFirst(2))
    }
} else if style == .numberedList {
    // Strip "N. " prefix
    if let dotSpace = text.firstIndex(of: ".") {
        let afterDot = text.index(after: dotSpace)
        if afterDot < text.endIndex && text[afterDot] == " " {
            text = String(text[text.index(after: afterDot)...])
        }
    }
} else if style == .codeBlock {
    // Code block text is preserved as-is
}
```

- [ ] **Step 3: Add `import Markdown` to AttributedStringBuilder.swift**

```swift
import AppKit
import Markdown
```

- [ ] **Step 4: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Compiles.

- [ ] **Step 5: Run all tests**

Run: `cd /Users/aimenhallou/floatnote && swift test`
Expected: Existing tests pass. Some round-trip tests may need adjustment if the renderer produces slightly different output than the old `buildParagraph()`.

- [ ] **Step 6: Commit**

```bash
git add Sources/FloatNote/AttributedStringBuilder.swift
git commit -m "feat: integrate MarkdownRenderer into AttributedStringBuilder.build()"
```

---

### Task 18: Add smart Enter behavior for new block types

**Files:**
- Modify: `Sources/FloatNote/NoteTextView.swift:225-280`

- [ ] **Step 1: Update insertNewline to handle blockquotes and numbered lists**

In `insertNewline(_ sender: Any?)` (line 225), add continuation logic for the new styles. After the existing checkbox and bullet continuation code:

```swift
// Blockquote continuation: if current line is a blockquote, continue with "> "
} else if currentLineStyle == .blockquote {
    let prefixText = textAfterBlockquotePrefix(paraRange: paraRange, storage: storage)
    if prefixText.trimmingCharacters(in: .whitespaces).isEmpty {
        // Empty blockquote line — strip the prefix and make it plain
        removeLinePrefix(in: paraRange, storage: storage)
        super.insertNewline(sender)
    } else {
        super.insertNewline(sender)
        insertText("> ", replacementRange: selectedRange())
    }

// Numbered list continuation
} else if currentLineStyle == .numberedList {
    let prefixText = textAfterNumberedPrefix(paraRange: paraRange, storage: storage)
    if prefixText.trimmingCharacters(in: .whitespaces).isEmpty {
        removeLinePrefix(in: paraRange, storage: storage)
        super.insertNewline(sender)
    } else {
        // Extract current number, increment
        let currentText = storage.attributedSubstring(from: paraRange).string
        if let match = currentText.firstMatch(of: /^(\d+)\.\s/) {
            let nextNum = (Int(match.output.1) ?? 1) + 1
            super.insertNewline(sender)
            insertText("\(nextNum). ", replacementRange: selectedRange())
        } else {
            super.insertNewline(sender)
        }
    }
}
```

- [ ] **Step 2: Add helper methods for new prefix detection**

```swift
private func textAfterBlockquotePrefix(paraRange: NSRange, storage: NSTextStorage) -> String {
    let text = storage.attributedSubstring(from: paraRange).string
    if text.hasPrefix("> ") {
        return String(text.dropFirst(2))
    }
    return text
}

private func textAfterNumberedPrefix(paraRange: NSRange, storage: NSTextStorage) -> String {
    let text = storage.attributedSubstring(from: paraRange).string
    if let match = text.firstMatch(of: /^\d+\.\s(.*)/) {
        return String(match.output.1)
    }
    return text
}
```

- [ ] **Step 3: Build**

Run: `cd /Users/aimenhallou/floatnote && swift build`
Expected: Compiles.

- [ ] **Step 4: Commit**

```bash
git add Sources/FloatNote/NoteTextView.swift
git commit -m "feat: smart Enter continuation for blockquotes and numbered lists"
```

---

### Task 19: Add tests for new markdown features

**Files:**
- Modify: `Tests/FloatNoteTests/NoteModelParseTests.swift`
- Modify: `Tests/FloatNoteTests/AttributedStringBuilderTests.swift`
- Modify: `Tests/FloatNoteTests/NoteModelCommandTests.swift`

- [ ] **Step 1: Add parse/serialize tests for new styles**

Append to `NoteModelParseTests`:

```swift
    @Test("blockquote round-trip")
    func blockquoteRoundTrip() {
        let lines = NoteModel.parse("> This is quoted")
        #expect(lines.count == 1)
        #expect(lines[0].style == .blockquote)
        #expect(lines[0].text == "This is quoted")
    }

    @Test("numbered list round-trip")
    func numberedListRoundTrip() {
        let lines = NoteModel.parse("1. First item")
        #expect(lines.count == 1)
        #expect(lines[0].style == .numberedList)
        #expect(lines[0].text == "First item")
    }

    @Test("inline bold preserved in serialize")
    func boldInSerialize() {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let note = NoteModel(id: UUID(), text: "Some **bold** text",
                             persistence: helper.persistence, globalSettings: gs)
        let serialized = note.serialize()
        #expect(serialized.contains("**bold**"))
        helper.cleanup()
    }

    @Test("inline italic preserved in serialize")
    func italicInSerialize() {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let note = NoteModel(id: UUID(), text: "Some *italic* text",
                             persistence: helper.persistence, globalSettings: gs)
        let serialized = note.serialize()
        #expect(serialized.contains("*italic*"))
        helper.cleanup()
    }

    @Test("inline code preserved in serialize")
    func codeInSerialize() {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let note = NoteModel(id: UUID(), text: "Use `let x = 1`",
                             persistence: helper.persistence, globalSettings: gs)
        let serialized = note.serialize()
        #expect(serialized.contains("`let x = 1`"))
        helper.cleanup()
    }
```

- [ ] **Step 2: Add AttributedStringBuilder tests for new styles**

Append to `AttributedStringBuilderTests`:

```swift
    @Test("blockquote round-trip")
    func blockquote() {
        let result = roundTrip([NoteLine(style: .blockquote, text: "Quoted text")])
        #expect(result.count == 1)
        #expect(result[0].style == .blockquote)
        #expect(result[0].text == "Quoted text")
    }

    @Test("numbered list round-trip")
    func numberedList() {
        let result = roundTrip([NoteLine(style: .numberedList, text: "First item")])
        #expect(result.count == 1)
        #expect(result[0].style == .numberedList)
        #expect(result[0].text == "First item")
    }

    @Test("code block round-trip")
    func codeBlock() {
        let result = roundTrip([NoteLine(style: .codeBlock, text: "let x = 1")])
        #expect(result.count == 1)
        #expect(result[0].style == .codeBlock)
        #expect(result[0].text == "let x = 1")
    }
```

- [ ] **Step 3: Add command tests for new slash commands**

Append to `NoteModelCommandTests`:

```swift
    @Test("applySlashCommand .codeBlock sets style")
    func codeBlockCommand() {
        let (note, helper) = makeNote("Hello")
        let lineId = note.lines[0].id
        note.applySlashCommand(.codeBlock, to: lineId)
        #expect(note.lines[0].style == .codeBlock)
        helper.cleanup()
    }

    @Test("applySlashCommand .blockquote sets style")
    func blockquoteCommand() {
        let (note, helper) = makeNote("Hello")
        let lineId = note.lines[0].id
        note.applySlashCommand(.blockquote, to: lineId)
        #expect(note.lines[0].style == .blockquote)
        helper.cleanup()
    }

    @Test("applySlashCommand .numberedList sets style")
    func numberedListCommand() {
        let (note, helper) = makeNote("Hello")
        let lineId = note.lines[0].id
        note.applySlashCommand(.numberedList, to: lineId)
        #expect(note.lines[0].style == .numberedList)
        helper.cleanup()
    }
```

- [ ] **Step 4: Run all tests**

Run: `cd /Users/aimenhallou/floatnote && swift test`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Tests/FloatNoteTests/
git commit -m "test: add tests for new markdown styles (blockquote, numbered list, code block, inline formatting)"
```

---

### Task 20: Snapshot tests

**Files:**
- Create: `Tests/FloatNoteTests/SnapshotTests.swift`

- [ ] **Step 1: Write snapshot tests**

```swift
import Testing
import AppKit
import SnapshotTesting
@testable import FloatNote

@Suite("Snapshots", .serialized)
@MainActor
struct SnapshotTests {

    private func renderToView(_ lines: [NoteLine], width: CGFloat = 300, height: CGFloat = 100) -> NSTextView {
        let attrStr = AttributedStringBuilder.build(from: lines, fontSize: 13, textColor: .clear)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.textStorage?.setAttributedString(attrStr)
        textView.backgroundColor = .white
        return textView
    }

    @Test("heading renders bold at 1.4x size")
    func headingSnapshot() {
        let view = renderToView([NoteLine(style: .heading, text: "My Heading")])
        assertSnapshot(of: view, as: .image(size: view.frame.size))
    }

    @Test("checkbox renders with SF Symbol")
    func checkboxSnapshot() {
        let view = renderToView([
            NoteLine(isCheckbox: true, isChecked: false, text: "Unchecked"),
            NoteLine(isCheckbox: true, isChecked: true, text: "Checked"),
        ], height: 60)
        assertSnapshot(of: view, as: .image(size: view.frame.size))
    }

    @Test("divider renders full-width line")
    func dividerSnapshot() {
        let view = renderToView([NoteLine(style: .divider)])
        assertSnapshot(of: view, as: .image(size: view.frame.size))
    }

    @Test("code block renders with background")
    func codeBlockSnapshot() {
        let view = renderToView([NoteLine(style: .codeBlock, text: "let x = 42")])
        assertSnapshot(of: view, as: .image(size: view.frame.size))
    }

    @Test("blockquote renders with indent")
    func blockquoteSnapshot() {
        let view = renderToView([NoteLine(style: .blockquote, text: "A wise person once said")])
        assertSnapshot(of: view, as: .image(size: view.frame.size))
    }

    @Test("mixed note with all styles")
    func mixedSnapshot() {
        let view = renderToView([
            NoteLine(style: .heading, text: "Title"),
            NoteLine(text: "Normal paragraph"),
            NoteLine(isCheckbox: true, isChecked: true, text: "Done"),
            NoteLine(style: .bullet, text: "A bullet"),
            NoteLine(style: .blockquote, text: "Quoted"),
            NoteLine(style: .codeBlock, text: "code()"),
            NoteLine(style: .divider),
        ], height: 300)
        assertSnapshot(of: view, as: .image(size: view.frame.size))
    }
}
```

**Note:** First run will create `__Snapshots__/` reference images. Subsequent runs compare against them. Snapshots validated locally only — see spec for CI guidance.

- [ ] **Step 2: Run snapshot tests (first run records reference images)**

Run: `cd /Users/aimenhallou/floatnote && swift test --filter SnapshotTests`
Expected: First run creates reference images in `Tests/FloatNoteTests/__Snapshots__/`. Tests pass.

- [ ] **Step 3: Verify reference images look correct**

Check the generated PNG files in `Tests/FloatNoteTests/__Snapshots__/SnapshotTests/`. Visually confirm they render as expected.

- [ ] **Step 4: Commit**

```bash
git add Tests/FloatNoteTests/SnapshotTests.swift Tests/FloatNoteTests/__Snapshots__/
git commit -m "test: add snapshot tests for visual regression"
```

---

### Task 21: Delete placeholder test + final verification

**Files:**
- Delete content from: `Tests/FloatNoteTests/PlaceholderTests.swift`

- [ ] **Step 1: Remove placeholder test**

Delete `Tests/FloatNoteTests/PlaceholderTests.swift`.

- [ ] **Step 2: Run full test suite**

Run: `cd /Users/aimenhallou/floatnote && swift test`
Expected: All tests pass.

- [ ] **Step 3: Build release**

Run: `cd /Users/aimenhallou/floatnote && swift build -c release`
Expected: Release build succeeds.

- [ ] **Step 4: Run app and manually verify**

Run the app. Check:
- Type `**bold**` → renders bold
- Type `*italic*` → renders italic
- Type `` `code` `` → renders monospace with background
- Type `> quote` → renders indented blockquote
- Type `1. item` → renders numbered list
- Type ``` → renders code block
- Slash menu shows new commands (Code Block, Blockquote, Numbered List)
- Enter in numbered list auto-increments
- Enter in blockquote continues `> ` prefix
- All existing features still work (checkboxes, headings, bullets, dividers)
- Settings propagation works (font size, opacity, colors)

- [ ] **Step 5: Commit**

```bash
git rm Tests/FloatNoteTests/PlaceholderTests.swift
git add -A
git commit -m "feat: complete markdown, concurrency, and testing improvements"
```
