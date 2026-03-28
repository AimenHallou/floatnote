import AppKit
import SwiftUI

// MARK: - NoteTextViewRepresentable

struct NoteTextViewRepresentable: NSViewRepresentable {

    var model: NoteModel
    var slashMenu: SlashMenuState
    @Binding var slashMenuPosition: CGPoint?

    // MARK: makeNSView

    func makeNSView(context: Context) -> NSScrollView {
        let textContainer = NSTextContainer()
        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        let textView = NoteTextView(frame: .zero, textContainer: textContainer)
        textView.slashMenu = slashMenu
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        // Build attributed string and set it
        let attrString = AttributedStringBuilder.build(
            from: model.lines,
            fontSize: CGFloat(model.fontSize),
            textColor: model.textColor
        )
        textView.textStorage?.setAttributedString(attrString)

        // Set typing attributes and base font/color for new text
        textView.typingAttributes = defaultTypingAttributes()
        textView.baseFontSize = CGFloat(model.fontSize)
        textView.baseTextColor = model.textColor.nsColor

        // Store coordinator reference to the text view
        context.coordinator.textView = textView
        context.coordinator.previousFontSize = model.fontSize
        context.coordinator.previousTextColor = model.textColor
        context.coordinator.previousContentHash = contentHash(model.lines)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        // Observe checkbox toggle notifications
        context.coordinator.startObserving()

        // Auto-focus the text view
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    // MARK: updateNSView

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }

        // Skip if this update was triggered by typing (textDidChange set the flag)
        if coordinator.isUpdatingFromModel { return }

        let fontChanged = model.fontSize != coordinator.previousFontSize
        let colorChanged = model.textColor != coordinator.previousTextColor
        let currentHash = contentHash(model.lines)
        let externalModelChange = currentHash != coordinator.previousContentHash

        guard fontChanged || colorChanged || externalModelChange else { return }

        coordinator.isUpdatingFromModel = true
        defer { coordinator.isUpdatingFromModel = false }

        let attrString = AttributedStringBuilder.build(
            from: model.lines,
            fontSize: CGFloat(model.fontSize),
            textColor: model.textColor
        )
        textView.textStorage?.setAttributedString(attrString)
        textView.typingAttributes = defaultTypingAttributes()
        textView.baseFontSize = CGFloat(model.fontSize)
        textView.baseTextColor = model.textColor.nsColor

        coordinator.previousFontSize = model.fontSize
        coordinator.previousTextColor = model.textColor
        coordinator.previousContentHash = currentHash
    }

    // MARK: Coordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, slashMenu: slashMenu, slashMenuPosition: $slashMenuPosition)
    }

    // MARK: - Helpers

    private func defaultTypingAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: AttributedStringBuilder.roundedFont(size: CGFloat(model.fontSize), bold: false),
            .foregroundColor: model.textColor.nsColor,
            .floatNoteLineStyle: LineStyle.text.rawValue
        ]
    }

    private func contentHash(_ lines: [NoteLine]) -> Int {
        var hasher = Hasher()
        for line in lines {
            hasher.combine(line.text)
            hasher.combine(line.isCheckbox)
            hasher.combine(line.isChecked)
            hasher.combine(line.style.rawValue)
        }
        return hasher.finalize()
    }

    // MARK: - Coordinator Class

    final class Coordinator: NSObject, NSTextViewDelegate {

        weak var textView: NoteTextView?
        let model: NoteModel
        let slashMenu: SlashMenuState
        var slashMenuPosition: Binding<CGPoint?>

        var isUpdatingFromModel = false
        var previousFontSize: Double = 13
        var previousTextColor: NoteTint = .clear
        var previousContentHash: Int = 0

        private var checkboxObserver: Any?
        private var slashCommandObserver: Any?

        init(model: NoteModel, slashMenu: SlashMenuState, slashMenuPosition: Binding<CGPoint?>) {
            self.model = model
            self.slashMenu = slashMenu
            self.slashMenuPosition = slashMenuPosition
        }

        deinit {
            if let obs = checkboxObserver { NotificationCenter.default.removeObserver(obs) }
            if let obs = slashCommandObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func startObserving() {
            checkboxObserver = NotificationCenter.default.addObserver(
                forName: .floatNoteCheckboxToggled,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleCheckboxToggled(notification)
            }

            slashCommandObserver = NotificationCenter.default.addObserver(
                forName: .floatNoteSlashCommandSelected,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleSlashCommandSelected(notification)
            }
        }

        // MARK: - NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingFromModel,
                  let textView = textView,
                  let storage = textView.textStorage else { return }

            // Parse lines back from text storage
            let newLines = AttributedStringBuilder.parseLines(
                from: storage,
                fontSize: CGFloat(model.fontSize)
            )

            // Set flag BEFORE updating model to prevent updateNSView from rebuilding
            isUpdatingFromModel = true
            model.lines = newLines
            previousContentHash = hashLines(newLines)
            // Defer resetting the flag so the SwiftUI update cycle sees it
            DispatchQueue.main.async { [weak self] in
                self?.isUpdatingFromModel = false
            }

            // Slash detection
            detectSlash(in: textView)
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let storage = textView.textStorage else { return true }

            // Block typing INTO a divider (but allow deleting through it)
            if let replacement = replacementString, !replacement.isEmpty,
               affectedCharRange.location < storage.length {
                let attrs = storage.attributes(at: affectedCharRange.location, effectiveRange: nil)
                if attrs[.attachment] is DividerAttachment {
                    return false
                }
            }

            return true
        }

        // MARK: - Slash Detection

        private func detectSlash(in textView: NSTextView) {
            guard let storage = textView.textStorage,
                  let selectedRange = textView.selectedRanges.first as? NSRange else {
                slashMenu.hide()
                slashMenuPosition.wrappedValue = nil
                return
            }

            let cursorPos = selectedRange.location
            let fullString = storage.string as NSString
            let paraRange = fullString.paragraphRange(for: NSRange(location: cursorPos, length: 0))
            let searchRange = NSRange(location: paraRange.location, length: cursorPos - paraRange.location)
            let slashRange = fullString.range(of: "/", options: .backwards, range: searchRange)

            if slashRange.location != NSNotFound {
                // Extract filter text after "/"
                let afterSlashStart = slashRange.location + 1
                let filterLength = cursorPos - afterSlashStart
                let filterText: String
                if filterLength > 0 {
                    filterText = fullString.substring(with: NSRange(location: afterSlashStart, length: filterLength))
                } else {
                    filterText = ""
                }

                if !slashMenu.isVisible {
                    slashMenu.show(charIndex: slashRange.location)
                }
                slashMenu.filter = filterText
                slashMenu.selectedIndex = 0

                // Calculate position for overlay
                if let layoutManager = textView.layoutManager,
                   let textContainer = textView.textContainer {
                    let glyphRange = layoutManager.glyphRange(
                        forCharacterRange: NSRange(location: slashRange.location, length: 1),
                        actualCharacterRange: nil
                    )
                    let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    // glyphRect is in text container coords; add inset to get text view coords
                    let x = glyphRect.minX + textView.textContainerInset.width
                    // Flip Y: text container Y is top-down, add line height for below-cursor
                    let y = glyphRect.maxY + textView.textContainerInset.height + 4
                    // Subtract scroll position
                    let scrollOffset = textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
                    let point = CGPoint(x: x, y: y - scrollOffset)
                    slashMenuPosition.wrappedValue = point
                }
            } else {
                if slashMenu.isVisible {
                    slashMenu.hide()
                }
                slashMenuPosition.wrappedValue = nil
            }
        }

        // MARK: - Checkbox Toggle

        private func handleCheckboxToggled(_ notification: Notification) {
            guard let index = notification.userInfo?["lineIndex"] as? Int,
                  let isChecked = notification.userInfo?["isChecked"] as? Bool,
                  model.lines.indices.contains(index) else { return }

            model.lines[index].isChecked = isChecked

            // Apply strikethrough locally in text storage
            guard let textView = textView,
                  let storage = textView.textStorage else { return }

            isUpdatingFromModel = true
            defer { isUpdatingFromModel = false }

            let fullString = storage.string as NSString
            let fullRange = NSRange(location: 0, length: storage.length)

            // Find the paragraph for this line index
            var paraIndex = 0
            fullString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { _, range, _, stop in
                if paraIndex == index {
                    let textRange = NSRange(location: range.location, length: range.length)
                    if isChecked {
                        storage.addAttributes([
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: NSColor.secondaryLabelColor,
                            .foregroundColor: NSColor.secondaryLabelColor
                        ], range: textRange)
                    } else {
                        storage.removeAttribute(.strikethroughStyle, range: textRange)
                        storage.removeAttribute(.strikethroughColor, range: textRange)
                        storage.addAttribute(.foregroundColor, value: self.model.textColor.nsColor, range: textRange)
                    }
                    stop.pointee = true
                }
                paraIndex += 1
            }

            previousContentHash = hashLines(model.lines)
        }

        // MARK: - Slash Command Selected

        private func handleSlashCommandSelected(_ notification: Notification) {
            guard let command = notification.userInfo?["command"] as? SlashCommand,
                  let textView = textView,
                  let storage = textView.textStorage,
                  let selectedRange = textView.selectedRanges.first as? NSRange else { return }

            let cursorPos = selectedRange.location
            let fullString = storage.string as NSString
            let paraRange = fullString.paragraphRange(for: NSRange(location: cursorPos, length: 0))
            let searchRange = NSRange(location: paraRange.location, length: cursorPos - paraRange.location)
            let slashRange = fullString.range(of: "/", options: .backwards, range: searchRange)

            // Remove slash text
            if slashRange.location != NSNotFound {
                textView.deleteSlashText()
            }

            // Find which line index cursor is in, apply command to model
            let updatedCursor = (textView.selectedRanges.first as? NSRange)?.location ?? cursorPos
            let updatedString = storage.string as NSString
            let updatedParaRange = updatedString.paragraphRange(for: NSRange(location: updatedCursor, length: 0))

            var lineIndex = 0
            var currentOffset = 0
            let storageString = storage.string
            for (i, _) in model.lines.enumerated() {
                if currentOffset >= updatedParaRange.location {
                    lineIndex = i
                    break
                }
                // Advance by paragraph
                let paraString = updatedString.paragraphRange(
                    for: NSRange(location: currentOffset, length: 0)
                )
                currentOffset = paraString.location + paraString.length
                if i == model.lines.count - 1 {
                    lineIndex = i
                }
            }
            _ = storageString // suppress unused warning

            // Apply command to model
            if model.lines.indices.contains(lineIndex) {
                let lineId = model.lines[lineIndex].id
                model.applySlashCommand(command, to: lineId)
            }

            slashMenu.hide()
            slashMenuPosition.wrappedValue = nil

            // Rebuild attributed string
            isUpdatingFromModel = true
            defer { isUpdatingFromModel = false }

            let attrString = AttributedStringBuilder.build(
                from: model.lines,
                fontSize: CGFloat(model.fontSize),
                textColor: model.textColor
            )
            storage.setAttributedString(attrString)
            textView.typingAttributes = [
                .font: AttributedStringBuilder.roundedFont(size: CGFloat(model.fontSize), bold: false),
                .foregroundColor: model.textColor.nsColor,
                .floatNoteLineStyle: LineStyle.text.rawValue
            ]

            previousContentHash = hashLines(model.lines)
        }

        // MARK: - Hash Helper

        private func hashLines(_ lines: [NoteLine]) -> Int {
            var hasher = Hasher()
            for line in lines {
                hasher.combine(line.text)
                hasher.combine(line.isCheckbox)
                hasher.combine(line.isChecked)
                hasher.combine(line.style.rawValue)
            }
            return hasher.finalize()
        }
    }
}
