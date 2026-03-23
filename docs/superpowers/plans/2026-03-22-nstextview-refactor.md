# NSTextView Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-line NSTextFields with a single NSTextView (TextKit 2) per note to fix height/selection/focus bugs.

**Architecture:** One NSTextView subclass per note, wrapped in NSViewRepresentable. Attributed string builder converts `[NoteLine]` to styled text with checkbox/divider attachments. Parser converts text storage back to `[NoteLine]` on each edit. Feedback loop prevented by `isUpdatingFromModel` flag.

**Tech Stack:** Swift 5.9, AppKit (NSTextView, TextKit 2, NSTextAttachmentViewProvider), SwiftUI, macOS 13+

**Spec:** `docs/superpowers/specs/2026-03-22-nstextview-refactor-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/FloatNote/NoteTextView.swift` | Create | NSTextView subclass + CheckboxAttachment + CheckboxViewProvider + DividerViewProvider |
| `Sources/FloatNote/NoteTextViewRepresentable.swift` | Create | NSViewRepresentable wrapper + Coordinator (delegate, sync, slash detection) |
| `Sources/FloatNote/AttributedStringBuilder.swift` | Create | `buildAttributedString(from:fontSize:textColor:)` + `parseLines(from:fontSize:)` |
| `Sources/FloatNote/ContentView.swift` | Modify | Delete old line types (~400 lines), update NoteEditorView body, update SlashMenuState |
| `Sources/FloatNote/NoteModel.swift` | Modify | Delete unused line mutation methods |
| `Sources/FloatNote/AppDelegate.swift` | Modify | Remove 4 notification names |

---

### Task 1: Create AttributedStringBuilder

The builder and parser are pure functions with no UI dependencies. Build these first so all later tasks can use them.

**Files:**
- Create: `Sources/FloatNote/AttributedStringBuilder.swift`

- [ ] **Step 1: Create the builder function**

```swift
// Sources/FloatNote/AttributedStringBuilder.swift
import AppKit

// MARK: - Custom attribute key for line style detection
extension NSAttributedString.Key {
    static let floatNoteLineStyle = NSAttributedString.Key("floatNoteLineStyle")
    static let floatNoteCheckbox = NSAttributedString.Key("floatNoteCheckbox")
}

enum AttributedStringBuilder {

    static func build(from lines: [NoteLine], fontSize: CGFloat, textColor: NoteTint) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let color = textColor.nsColor
        let baseFont = roundedFont(size: fontSize, bold: false)
        let headingFont = roundedFont(size: fontSize * 1.4, bold: true)

        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1

            if line.style == .divider {
                let attachment = DividerAttachment()
                let str = NSMutableAttributedString(attachment: attachment)
                str.addAttribute(.floatNoteLineStyle, value: LineStyle.divider.rawValue, range: NSRange(location: 0, length: str.length))
                if !isLast { str.append(NSAttributedString(string: "\n")) }
                result.append(str)
                continue
            }

            let paraStr = NSMutableAttributedString()

            if line.isCheckbox {
                let attachment = CheckboxAttachment()
                attachment.isChecked = line.isChecked
                attachment.lineIndex = index
                let attachStr = NSAttributedString(attachment: attachment)
                paraStr.append(attachStr)
                paraStr.append(NSAttributedString(string: " "))
            } else if line.style == .bullet {
                let bullet = NSAttributedString(string: "• ", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.secondaryLabelColor
                ])
                paraStr.append(bullet)
            }

            let textFont = line.style == .heading ? headingFont : baseFont
            let textColor: NSColor = (line.isCheckbox && line.isChecked) ? .secondaryLabelColor : color
            var textAttrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: textColor
            ]
            if line.isCheckbox && line.isChecked {
                textAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            paraStr.append(NSAttributedString(string: line.text, attributes: textAttrs))

            // Tag the paragraph with its style for parsing
            let styleTag = line.isCheckbox ? "checkbox" : line.style.rawValue
            paraStr.addAttribute(.floatNoteLineStyle, value: styleTag, range: NSRange(location: 0, length: paraStr.length))

            if !isLast { paraStr.append(NSAttributedString(string: "\n")) }
            result.append(paraStr)
        }

        return result
    }

    // MARK: - Parser (text storage → [NoteLine])

    static func parseLines(from textStorage: NSTextStorage, fontSize: CGFloat) -> [NoteLine] {
        let string = textStorage.string as NSString
        var lines: [NoteLine] = []

        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { _, range, _, _ in
            let paraAttrs = textStorage.attributes(at: range.location, effectiveRange: nil)

            // Check for divider
            if let style = paraAttrs[.floatNoteLineStyle] as? String, style == LineStyle.divider.rawValue {
                lines.append(NoteLine(style: .divider))
                return
            }

            // Check for checkbox attachment
            if let style = paraAttrs[.floatNoteLineStyle] as? String, style == "checkbox" {
                var isChecked = false
                textStorage.enumerateAttribute(.attachment, in: range, options: []) { value, _, _ in
                    if let checkbox = value as? CheckboxAttachment {
                        isChecked = checkbox.isChecked
                    }
                }
                // Extract text after attachment + space
                let text = extractText(from: textStorage, range: range)
                lines.append(NoteLine(isCheckbox: true, isChecked: isChecked, text: text))
                return
            }

            // Check for heading by font size
            if let font = paraAttrs[.font] as? NSFont, font.pointSize > fontSize * 1.2 {
                let text = extractText(from: textStorage, range: range)
                lines.append(NoteLine(style: .heading, text: text))
                return
            }

            // Check for bullet
            let paraText = string.substring(with: range)
            if paraText.hasPrefix("• ") {
                let text = String(paraText.dropFirst(2))
                lines.append(NoteLine(style: .bullet, text: text))
                return
            }

            // Plain text
            let text = extractText(from: textStorage, range: range)
            lines.append(NoteLine(text: text))
        }

        if lines.isEmpty { lines.append(NoteLine()) }
        return lines
    }

    // MARK: - Helpers

    static func roundedFont(size: CGFloat, bold: Bool) -> NSFont {
        let base = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: desc, size: size) ?? base
        }
        return base
    }

    private static func extractText(from storage: NSTextStorage, range: NSRange) -> String {
        var text = ""
        let string = storage.string as NSString
        // Walk character by character, skip attachment chars
        for i in range.location..<NSMaxRange(range) {
            let char = string.character(at: i)
            if char == 0xFFFC { continue } // attachment replacement char
            text.append(Character(UnicodeScalar(char)!))
        }
        // Strip leading space after attachment
        if text.hasPrefix(" ") && range.length > 0 {
            let firstAttrs = storage.attributes(at: range.location, effectiveRange: nil)
            if firstAttrs[.attachment] != nil {
                text = String(text.dropFirst())
            }
        }
        return text
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED (may have warnings from other files, that's fine)

- [ ] **Step 3: Commit**

```bash
git add Sources/FloatNote/AttributedStringBuilder.swift
git commit -m "feat: attributed string builder and parser for NSTextView refactor"
```

---

### Task 2: Create NoteTextView (NSTextView subclass)

The text view subclass with TextKit 2 setup, transparent appearance, and key interception for slash menu.

**Files:**
- Create: `Sources/FloatNote/NoteTextView.swift`

- [ ] **Step 1: Create NoteTextView with attachments**

```swift
// Sources/FloatNote/NoteTextView.swift
import AppKit

// MARK: - CheckboxAttachment

final class CheckboxAttachment: NSTextAttachment {
    var isChecked: Bool = false
    var lineIndex: Int = 0

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        let size = lineFrag.height * 0.75
        let yOffset = (lineFrag.height - size) / 2 - 2
        return CGRect(x: 0, y: yOffset, width: size, height: size)
    }
}

// MARK: - CheckboxViewProvider

final class CheckboxViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        let button = NSButton(frame: .zero)
        button.setButtonType(.switch)
        button.title = ""
        button.bezelStyle = .regularSquare
        button.isBordered = false

        if let attachment = self.textAttachment as? CheckboxAttachment {
            button.state = attachment.isChecked ? .on : .off
        }

        button.target = self
        button.action = #selector(checkboxToggled(_:))
        self.view = button
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        guard let attachment = self.textAttachment as? CheckboxAttachment else { return }
        attachment.isChecked = sender.state == .on

        // Notify the text view to sync model
        if let textView = self.textLayoutManager?.textViewportLayoutController
            .delegate as? NoteTextView {
            // Fallback: post notification
        }
        NotificationCenter.default.post(
            name: .floatNoteCheckboxToggled, object: nil,
            userInfo: ["lineIndex": attachment.lineIndex, "isChecked": attachment.isChecked]
        )
    }
}

// MARK: - DividerAttachment

final class DividerAttachment: NSTextAttachment {
    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: CGRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        let width = textContainer?.size.width ?? 200
        return CGRect(x: 0, y: lineFrag.height / 2 - 0.5, width: width - 20, height: 1)
    }

    override func image(forBounds imageBounds: CGRect, textContainer: NSTextContainer?, characterIndex charIndex: Int) -> NSImage? {
        let image = NSImage(size: imageBounds.size)
        image.lockFocus()
        NSColor.separatorColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: imageBounds.width, height: 1)).fill()
        image.unlockFocus()
        return image
    }
}

// MARK: - NoteTextView

final class NoteTextView: NSTextView {

    var slashMenu: SlashMenuState?
    var onCheckboxToggle: ((Int, Bool) -> Void)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        drawsBackground = false
        isRichText = true
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        textContainerInset = NSSize(width: 10, height: 8)
    }

    override func keyDown(with event: NSEvent) {
        // Slash menu key interception
        if let sm = slashMenu, sm.isVisible {
            switch event.keyCode {
            case 125: // Down arrow
                sm.moveDown(); return
            case 126: // Up arrow
                sm.moveUp(); return
            case 36: // Enter
                if let cmd = sm.selectedCommand {
                    NotificationCenter.default.post(
                        name: .floatNoteSlashCommandSelected, object: nil,
                        userInfo: ["command": cmd]
                    )
                }
                return
            case 53: // Escape
                sm.hide()
                // Remove the slash text
                deleteSlashText()
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    func deleteSlashText() {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let cursorPos = selectedRange().location
        // Find the "/" before cursor in current paragraph
        let paraRange = string.paragraphRange(for: NSRange(location: cursorPos, length: 0))
        let paraText = string.substring(with: paraRange)
        if let slashIdx = paraText.lastIndex(of: "/") {
            let offset = paraText.distance(from: paraText.startIndex, to: slashIdx)
            let deleteRange = NSRange(location: paraRange.location + offset, length: cursorPos - (paraRange.location + offset))
            if deleteRange.length > 0 {
                replaceCharacters(in: deleteRange, with: "")
            }
        }
    }

    // Handle Enter key for checkbox/bullet continuation
    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage else { super.insertNewline(sender); return }
        let string = storage.string as NSString
        let cursorPos = selectedRange().location
        let paraRange = string.paragraphRange(for: NSRange(location: min(cursorPos, string.length - 1), length: 0))

        // Check current paragraph style tag
        if paraRange.location < storage.length {
            let attrs = storage.attributes(at: paraRange.location, effectiveRange: nil)
            let style = attrs[.floatNoteLineStyle] as? String

            if style == "checkbox" {
                let paraText = extractParaText(storage: storage, range: paraRange)
                if paraText.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Empty checkbox → convert to plain text (remove attachment)
                    removeLinePrefix(in: paraRange, storage: storage)
                    return
                }
                // Insert new checkbox line
                super.insertNewline(sender)
                insertCheckbox()
                return
            }

            let paraStr = string.substring(with: paraRange)
            if paraStr.hasPrefix("• ") {
                let textAfterBullet = String(paraStr.dropFirst(2)).trimmingCharacters(in: .newlines)
                if textAfterBullet.isEmpty {
                    // Empty bullet → convert to plain text
                    let bulletRange = NSRange(location: paraRange.location, length: 2)
                    replaceCharacters(in: bulletRange, with: "")
                    return
                }
                // Insert new bullet line
                super.insertNewline(sender)
                insertText("• ", replacementRange: selectedRange())
                return
            }
        }

        super.insertNewline(sender)
    }

    private func insertCheckbox() {
        guard let storage = textStorage else { return }
        let attachment = CheckboxAttachment()
        attachment.isChecked = false
        let attachStr = NSMutableAttributedString(attachment: attachment)
        attachStr.append(NSAttributedString(string: " "))
        attachStr.addAttribute(.floatNoteLineStyle, value: "checkbox", range: NSRange(location: 0, length: attachStr.length))
        let pos = selectedRange().location
        storage.insert(attachStr, at: pos)
        setSelectedRange(NSRange(location: pos + attachStr.length, length: 0))
    }

    private func removeLinePrefix(in paraRange: NSRange, storage: NSTextStorage) {
        // Remove attachment + space at start of paragraph
        var removeLen = 0
        let string = storage.string as NSString
        for i in paraRange.location..<min(paraRange.location + 3, NSMaxRange(paraRange)) {
            let ch = string.character(at: i)
            if ch == 0xFFFC || ch == 0x20 { removeLen += 1 } else { break }
        }
        if removeLen > 0 {
            let removeRange = NSRange(location: paraRange.location, length: removeLen)
            storage.deleteCharacters(in: removeRange)
            // Remove the style tag
            let newParaRange = string.paragraphRange(for: NSRange(location: paraRange.location, length: 0))
            if newParaRange.length > 0 {
                storage.removeAttribute(.floatNoteLineStyle, range: newParaRange)
            }
        }
    }

    private func extractParaText(storage: NSTextStorage, range: NSRange) -> String {
        let string = storage.string as NSString
        var text = ""
        for i in range.location..<NSMaxRange(range) {
            let ch = string.character(at: i)
            if ch == 0xFFFC || ch == 0x0A { continue }
            text.append(Character(UnicodeScalar(ch)!))
        }
        // Strip leading space after attachment
        if text.hasPrefix(" ") { text = String(text.dropFirst()) }
        return text
    }
}

// MARK: - Notification names for text view communication

extension Notification.Name {
    static let floatNoteCheckboxToggled = Notification.Name("floatnote.checkboxToggled")
    static let floatNoteSlashCommandSelected = Notification.Name("floatnote.slashCommandSelected")
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/FloatNote/NoteTextView.swift
git commit -m "feat: NoteTextView subclass with checkbox/divider attachments"
```

---

### Task 3: Create NoteTextViewRepresentable

The SwiftUI wrapper with Coordinator that handles the two-way sync between NoteModel and NSTextView.

**Files:**
- Create: `Sources/FloatNote/NoteTextViewRepresentable.swift`

- [ ] **Step 1: Create the representable with coordinator**

```swift
// Sources/FloatNote/NoteTextViewRepresentable.swift
import SwiftUI
import AppKit

struct NoteTextViewRepresentable: NSViewRepresentable {

    @ObservedObject var model: NoteModel
    @ObservedObject var slashMenu: SlashMenuState
    @Binding var slashMenuPosition: CGPoint?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = NoteTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.slashMenu = slashMenu

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Initial content
        let attrStr = AttributedStringBuilder.build(
            from: model.lines,
            fontSize: model.fontSize,
            textColor: model.textColor
        )
        textView.textStorage?.setAttributedString(attrStr)
        textView.typingAttributes = Self.typingAttributes(fontSize: model.fontSize, textColor: model.textColor)

        // Store initial state
        context.coordinator.lastFontSize = model.fontSize
        context.coordinator.lastTextColor = model.textColor
        context.coordinator.lastLineCount = model.lines.count

        // Observe checkbox toggles
        context.coordinator.startObserving()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self

        guard let textView = coord.textView else { return }
        textView.slashMenu = slashMenu

        // Skip if we're in a typing-driven update
        if coord.isUpdatingFromModel { return }

        // Check if font/color changed (settings change)
        let fontChanged = model.fontSize != coord.lastFontSize
        let colorChanged = model.textColor != coord.lastTextColor

        if fontChanged || colorChanged {
            coord.isUpdatingFromModel = true
            let savedRange = textView.selectedRange()
            let attrStr = AttributedStringBuilder.build(
                from: model.lines,
                fontSize: model.fontSize,
                textColor: model.textColor
            )
            textView.textStorage?.setAttributedString(attrStr)
            textView.typingAttributes = Self.typingAttributes(fontSize: model.fontSize, textColor: model.textColor)
            let clampedRange = NSRange(
                location: min(savedRange.location, textView.string.count),
                length: 0
            )
            textView.setSelectedRange(clampedRange)
            coord.lastFontSize = model.fontSize
            coord.lastTextColor = model.textColor
            coord.lastLineCount = model.lines.count
            coord.isUpdatingFromModel = false
            return
        }

        // Check if model was changed externally (slash command, clearAll, etc.)
        let lineCountChanged = model.lines.count != coord.lastLineCount
        let isTyping = coord.isTypingUpdate

        if lineCountChanged && !isTyping {
            coord.isUpdatingFromModel = true
            let savedRange = textView.selectedRange()
            let attrStr = AttributedStringBuilder.build(
                from: model.lines,
                fontSize: model.fontSize,
                textColor: model.textColor
            )
            textView.textStorage?.setAttributedString(attrStr)
            textView.typingAttributes = Self.typingAttributes(fontSize: model.fontSize, textColor: model.textColor)
            let clampedRange = NSRange(
                location: min(savedRange.location, textView.string.count),
                length: 0
            )
            textView.setSelectedRange(clampedRange)
            coord.lastLineCount = model.lines.count
            coord.isUpdatingFromModel = false
        }
    }

    static func typingAttributes(fontSize: CGFloat, textColor: NoteTint) -> [NSAttributedString.Key: Any] {
        [
            .font: AttributedStringBuilder.roundedFont(size: fontSize, bold: false),
            .foregroundColor: textColor.nsColor
        ]
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: NoteTextViewRepresentable
        weak var textView: NoteTextView?
        var isUpdatingFromModel = false
        var isTypingUpdate = false
        var lastFontSize: Double = 13
        var lastTextColor: NoteTint = .clear
        var lastLineCount: Int = 0
        private var checkboxObserver: Any?
        private var slashCommandObserver: Any?

        init(parent: NoteTextViewRepresentable) {
            self.parent = parent
        }

        func startObserving() {
            checkboxObserver = NotificationCenter.default.addObserver(
                forName: .floatNoteCheckboxToggled, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self,
                      let lineIndex = notification.userInfo?["lineIndex"] as? Int,
                      let isChecked = notification.userInfo?["isChecked"] as? Bool else { return }
                self.handleCheckboxToggle(lineIndex: lineIndex, isChecked: isChecked)
            }

            slashCommandObserver = NotificationCenter.default.addObserver(
                forName: .floatNoteSlashCommandSelected, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self,
                      let command = notification.userInfo?["command"] as? SlashCommand else { return }
                self.handleSlashCommand(command)
            }
        }

        deinit {
            if let o = checkboxObserver { NotificationCenter.default.removeObserver(o) }
            if let o = slashCommandObserver { NotificationCenter.default.removeObserver(o) }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromModel, let textView else { return }
            guard let storage = textView.textStorage else { return }

            isTypingUpdate = true

            // Parse text storage back into model lines
            let newLines = AttributedStringBuilder.parseLines(from: storage, fontSize: parent.model.fontSize)
            parent.model.lines = newLines
            lastLineCount = newLines.count

            // Slash menu detection
            detectSlashCommand(in: textView)

            isTypingUpdate = false
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            // Prevent editing into divider attachments
            guard let storage = textView.textStorage else { return true }
            if range.location < storage.length {
                let attrs = storage.attributes(at: range.location, effectiveRange: nil)
                if let style = attrs[.floatNoteLineStyle] as? String,
                   style == LineStyle.divider.rawValue,
                   let text, !text.isEmpty {
                    return false
                }
            }
            return true
        }

        // MARK: - Checkbox Toggle

        private func handleCheckboxToggle(lineIndex: Int, isChecked: Bool) {
            guard lineIndex < parent.model.lines.count else { return }
            isUpdatingFromModel = true
            parent.model.lines[lineIndex].isChecked = isChecked

            // Update strikethrough locally in text storage
            guard let textView, let storage = textView.textStorage else {
                isUpdatingFromModel = false
                return
            }

            let string = storage.string as NSString
            var paraIndex = 0
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { _, range, _, stop in
                if paraIndex == lineIndex {
                    // Apply or remove strikethrough on text portion (skip attachment)
                    var textStart = range.location
                    for i in range.location..<NSMaxRange(range) {
                        if string.character(at: i) != 0xFFFC && string.character(at: i) != 0x20 {
                            textStart = i
                            break
                        }
                        textStart = i + 1
                    }
                    let textRange = NSRange(location: textStart, length: NSMaxRange(range) - textStart)
                    if textRange.length > 0 {
                        if isChecked {
                            storage.addAttributes([
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                .foregroundColor: NSColor.secondaryLabelColor
                            ], range: textRange)
                        } else {
                            storage.removeAttribute(.strikethroughStyle, range: textRange)
                            storage.addAttribute(.foregroundColor, value: self.parent.model.textColor.nsColor, range: textRange)
                        }
                    }
                    stop.pointee = true
                    return
                }
                paraIndex += 1
            }

            isUpdatingFromModel = false
        }

        // MARK: - Slash Commands

        private func detectSlashCommand(in textView: NoteTextView) {
            let string = textView.string as NSString
            let cursorPos = textView.selectedRange().location
            guard cursorPos > 0, cursorPos <= string.length else {
                parent.slashMenu.hide()
                return
            }

            let paraRange = string.paragraphRange(for: NSRange(location: cursorPos - 1, length: 0))
            let paraText = string.substring(with: paraRange)

            if let slashIdx = paraText.lastIndex(of: "/") {
                let filter = String(paraText[paraText.index(after: slashIdx)...]).trimmingCharacters(in: .newlines)
                if !parent.slashMenu.isVisible {
                    let charPos = paraRange.location + paraText.distance(from: paraText.startIndex, to: slashIdx)
                    parent.slashMenu.show(charIndex: charPos)
                }
                parent.slashMenu.updateFilter("/" + filter)

                // Calculate position for overlay
                let glyphRange = NSRange(location: paraRange.location + paraText.distance(from: paraText.startIndex, to: slashIdx), length: 1)
                let rect = textView.firstRect(forCharacterRange: glyphRange, actualRange: nil)
                if let window = textView.window {
                    let viewRect = window.convertFromScreen(rect)
                    let localPoint = textView.convert(viewRect.origin, from: nil)
                    DispatchQueue.main.async {
                        self.parent.slashMenuPosition = CGPoint(x: localPoint.x, y: localPoint.y + 20)
                    }
                }
            } else if parent.slashMenu.isVisible {
                parent.slashMenu.hide()
            }
        }

        private func handleSlashCommand(_ command: SlashCommand) {
            guard let textView, let storage = textView.textStorage else { return }

            // Find which paragraph the slash is in
            let string = storage.string as NSString
            guard let charIndex = parent.slashMenu.charIndex else { return }

            let paraRange = string.paragraphRange(for: NSRange(location: charIndex, length: 0))
            var paraIndex = 0
            var foundIndex = 0
            string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byParagraphs) { _, range, _, stop in
                if range.location == paraRange.location {
                    foundIndex = paraIndex
                    stop.pointee = true
                    return
                }
                paraIndex += 1
            }

            parent.slashMenu.hide()

            // Remove slash text from the paragraph
            isUpdatingFromModel = true
            textView.deleteSlashText()

            // Apply the command
            let newLines = AttributedStringBuilder.parseLines(from: storage, fontSize: parent.model.fontSize)
            parent.model.lines = newLines
            if foundIndex < parent.model.lines.count {
                parent.model.applySlashCommand(command, to: parent.model.lines[foundIndex].id)
            }
            lastLineCount = parent.model.lines.count

            // Rebuild
            let savedPos = textView.selectedRange().location
            let attrStr = AttributedStringBuilder.build(
                from: parent.model.lines,
                fontSize: parent.model.fontSize,
                textColor: parent.model.textColor
            )
            storage.setAttributedString(attrStr)
            textView.typingAttributes = NoteTextViewRepresentable.typingAttributes(
                fontSize: parent.model.fontSize,
                textColor: parent.model.textColor
            )
            textView.setSelectedRange(NSRange(location: min(savedPos, storage.length), length: 0))
            isUpdatingFromModel = false
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED (SlashMenuState changes needed — will fail until Task 4)

- [ ] **Step 3: Commit**

```bash
git add Sources/FloatNote/NoteTextViewRepresentable.swift
git commit -m "feat: NoteTextViewRepresentable with two-way sync and slash commands"
```

---

### Task 4: Update SlashMenuState and NoteEditorView

Replace the old line-based editor with the new NSTextView. Update SlashMenuState to use character index.

**Files:**
- Modify: `Sources/FloatNote/ContentView.swift`

- [ ] **Step 1: Update SlashMenuState**

Replace the `lineId: UUID?` property with `charIndex: Int?`. Update `show()` signature:

```swift
// In SlashMenuState class, replace:
//   @Published var lineId: UUID?
// with:
    @Published var charIndex: Int?

// Replace show(lineId:) with:
    func show(charIndex: Int) {
        self.charIndex = charIndex
        self.filter = ""
        self.selectedIndex = 0
        self.isVisible = true
    }

// Update hide():
    func hide() {
        isVisible = false
        filter = ""
        selectedIndex = 0
        charIndex = nil
    }
```

- [ ] **Step 2: Replace NoteEditorView body**

Delete the entire body of NoteEditorView (the ForEach, selection system, focus handling, etc.) and replace with:

```swift
struct NoteEditorView: View {
    @ObservedObject var model: NoteModel
    @ObservedObject private var global = GlobalSettings.shared
    @StateObject private var slashMenu = SlashMenuState()
    let isWindowHovering: Bool
    @State private var slashMenuPosition: CGPoint?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Tint overlay
            if model.tintColor != .clear {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.tintColor.color.opacity(0.12))
                    .allowsHitTesting(false)
            }

            // Single text view
            NoteTextViewRepresentable(
                model: model,
                slashMenu: slashMenu,
                slashMenuPosition: $slashMenuPosition
            )

            // Slash menu overlay
            if slashMenu.isVisible, let pos = slashMenuPosition {
                SlashMenuOverlay(slashMenu: slashMenu) { command in
                    NotificationCenter.default.post(
                        name: .floatNoteSlashCommandSelected, object: nil,
                        userInfo: ["command": command]
                    )
                }
                .offset(x: pos.x, y: pos.y)
            }
        }
    }
}
```

- [ ] **Step 3: Delete old types from ContentView.swift**

Remove these types entirely:
- `WrappingTextField` class
- `LineTextFieldRepresentable` struct and its Coordinator
- `LineTextField` struct

Remove these methods/properties from NoteEditorView:
- `focusedLineId`, `selectedLineIds`, `keyMonitor`
- `enterSelectAll()`, `selectAllLines()`, `selectRange(to:)`, `installCopyMonitor()`, `exitSelection()`, `copySelectedLines()`
- `postFocus(lineId:cursorAtEnd:)`
- `checkboxAction()`
- All `.onReceive` handlers for `floatNoteLineFocused`, `floatNoteSelectAllLines`, `floatNoteShiftClickLine`
- `.onChange(of: model.lines)` handler

Keep these in ContentView.swift:
- `SlashMenuState` (updated)
- `SlashMenuOverlay`
- `ContentView`
- `TabBar`, `TabItemView`, `RenameField`, `TabClickHandler`
- `HoverHighlight`, `pointerOnHover()`

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run the app and test basic editing**

```bash
pkill -x FloatNote 2>/dev/null; sleep 0.3
cp .build/debug/FloatNote FloatNote.app/Contents/MacOS/FloatNote
open FloatNote.app
```

Test: type text, press Enter to create new lines, basic editing works, text wraps, mouse selection across lines works.

- [ ] **Step 6: Commit**

```bash
git add Sources/FloatNote/ContentView.swift
git commit -m "feat: replace per-line editors with single NSTextView"
```

---

### Task 5: Clean up NoteModel and AppDelegate

Remove dead code from the model and notification names.

**Files:**
- Modify: `Sources/FloatNote/NoteModel.swift`
- Modify: `Sources/FloatNote/AppDelegate.swift`

- [ ] **Step 1: Remove unused notification names from AppDelegate**

Remove from the `Notification.Name` extension:
- `floatNoteFocusLine`
- `floatNoteLineFocused`
- `floatNoteSelectAllLines`
- `floatNoteShiftClickLine`

Keep: `floatNoteOpenSettings`

- [ ] **Step 2: Remove unused methods from NoteModel**

Delete these methods:
- `insertLine(after:checkbox:)`
- `deleteLine(_:)`
- `toggleLineType(_:)`
- `pasteLines(_:at:appendToExisting:)`

Keep: `toggleCheckbox(_:)`, `applySlashCommand(_:to:)`, `clearCompleted()`, `clearAll()`, `parse()`, `serialize()`

- [ ] **Step 3: Build and test**

Run: `swift build 2>&1`
Expected: BUILD SUCCEEDED with no warnings about unused code

```bash
pkill -x FloatNote 2>/dev/null; sleep 0.3
cp .build/debug/FloatNote FloatNote.app/Contents/MacOS/FloatNote
open FloatNote.app
```

Test: everything still works — editing, checkboxes, slash commands, tab switching, settings.

- [ ] **Step 4: Commit**

```bash
git add Sources/FloatNote/NoteModel.swift Sources/FloatNote/AppDelegate.swift
git commit -m "chore: remove dead code from NoteModel and AppDelegate"
```

---

### Task 6: Integration testing and polish

Full manual test of all features. Fix any issues found.

**Files:**
- May modify any file based on issues found

- [ ] **Step 1: Test checklist**

Build and launch the app. Test each item:

1. **Basic editing**: Type text, delete text, cursor movement
2. **Text wrapping**: Long lines wrap correctly
3. **Mouse selection**: Click and drag across multiple lines — text highlights
4. **Copy/paste**: Select text, Cmd+C, Cmd+V in another app
5. **Multi-line paste**: Paste a block of text into the note
6. **Slash commands**: Type `/`, filter works, arrow keys navigate, Enter selects, Escape dismisses
7. **Todo**: `/todo` creates checkbox, click checkbox toggles it, checked items get strikethrough
8. **Heading**: `/heading` makes text bold and larger
9. **Bullet**: `/bullet` adds bullet prefix, Enter continues bullet, empty bullet + Enter reverts
10. **Divider**: `/divider` inserts horizontal line
11. **Clear completed**: `/clear completed` removes checked todos
12. **Enter on empty checkbox**: Converts to plain text
13. **Backspace at start of checkbox**: Removes checkbox
14. **Tab switching**: Switch tabs, content is correct, font sizes preserved
15. **Per-note settings**: Change font size/opacity/color in settings, updates live
16. **Global settings**: Change global defaults, notes without overrides update
17. **Undo/redo**: Cmd+Z and Cmd+Shift+Z work
18. **Window drag**: Dragging from edges/padding still repositions window

- [ ] **Step 2: Fix any issues found**

Address bugs found during testing. Each fix should be a separate small commit.

- [ ] **Step 3: Final commit and push**

```bash
git add -A
git commit -m "feat: complete NSTextView refactor — single text view per note"
git push origin master
```
