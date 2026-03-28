import AppKit

// MARK: - Notification Names (NoteTextView additions)

extension Notification.Name {
    /// Posted when a checkbox attachment is toggled.
    /// userInfo: ["lineIndex": Int, "isChecked": Bool]
    static let floatNoteCheckboxToggled = Notification.Name("floatnote.checkboxToggled")

    /// Posted when Enter is pressed while the slash menu is visible.
    /// userInfo: ["command": SlashCommand]
    static let floatNoteSlashCommandSelected = Notification.Name("floatnote.slashCommandSelected")
}

// MARK: - CheckboxAttachment

final class CheckboxAttachment: NSTextAttachment {
    var isChecked: Bool = false {
        didSet { updateImage() }
    }
    var lineIndex: Int = 0

    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        updateImage()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateImage()
    }

    func updateImage() {
        let symbolName = isChecked ? "checkmark.square.fill" : "square"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [.labelColor]))
        self.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let size: CGFloat = 16
        let yOffset = (lineFrag.height - size) / 2
        return CGRect(x: 0, y: yOffset, width: size, height: size)
    }
}

// MARK: - CheckboxViewProvider

final class CheckboxViewProvider: NSTextAttachmentViewProvider {

    override func loadView() {
        let button = NSButton(frame: .zero)
        button.bezelStyle = .regularSquare
        button.setButtonType(.toggle)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyUpOrDown

        if let attachment = self.textAttachment as? CheckboxAttachment {
            updateButton(button, isChecked: attachment.isChecked)
        }

        button.target = self
        button.action = #selector(checkboxTapped(_:))
        self.view = button
    }

    @objc private func checkboxTapped(_ sender: NSButton) {
        guard let attachment = self.textAttachment as? CheckboxAttachment else { return }
        attachment.isChecked.toggle()
        updateButton(sender, isChecked: attachment.isChecked)
        NotificationCenter.default.post(
            name: .floatNoteCheckboxToggled,
            object: nil,
            userInfo: [
                "lineIndex": attachment.lineIndex,
                "isChecked": attachment.isChecked
            ]
        )
    }

    private func updateButton(_ button: NSButton, isChecked: Bool) {
        let imageName = isChecked ? "checkmark.square.fill" : "square"
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
        button.contentTintColor = isChecked ? .secondaryLabelColor : .labelColor
    }
}

// MARK: - DividerAttachment

final class DividerAttachment: NSTextAttachment {

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let containerWidth = textContainer?.size.width ?? lineFrag.width
        let padding: CGFloat = 8
        let width = max(containerWidth - padding * 2, 0)
        let yOffset = (lineFrag.height - 1) / 2
        return CGRect(x: padding, y: yOffset, width: width, height: 1)
    }

    override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    ) -> NSImage? {
        let size = CGSize(width: max(imageBounds.width, 1), height: max(imageBounds.height, 1))
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.separatorColor.set()
            let line = NSBezierPath()
            line.lineWidth = 1
            line.move(to: CGPoint(x: 0, y: rect.midY))
            line.line(to: CGPoint(x: rect.maxX, y: rect.midY))
            line.stroke()
            return true
        }
        return image
    }
}

// MARK: - NoteTextView

final class NoteTextView: NSTextView {

    var slashMenu: SlashMenuState?
    var baseFontSize: CGFloat = 13
    var baseTextColor: NSColor = .labelColor

    // MARK: - Checkbox Click Handling (TextKit 1)

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            super.mouseDown(with: event)
            return
        }

        let textPoint = NSPoint(x: point.x - textContainerInset.width,
                                y: point.y - textContainerInset.height)
        let charIndex = layoutManager.characterIndex(
            for: textPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        guard charIndex < (textStorage?.length ?? 0),
              let attachment = textStorage?.attribute(.attachment, at: charIndex, effectiveRange: nil) as? CheckboxAttachment else {
            super.mouseDown(with: event)
            return
        }

        // Toggle the checkbox
        attachment.isChecked.toggle()
        NotificationCenter.default.post(
            name: .floatNoteCheckboxToggled,
            object: self,
            userInfo: [
                "lineIndex": attachment.lineIndex,
                "isChecked": attachment.isChecked
            ]
        )
    }

    private func isOverCheckbox(at point: NSPoint) -> Bool {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage else { return false }
        let textPoint = NSPoint(x: point.x - textContainerInset.width,
                                y: point.y - textContainerInset.height)
        let charIndex = layoutManager.characterIndex(
            for: textPoint, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil)
        guard charIndex < textStorage.length else { return false }
        return textStorage.attribute(.attachment, at: charIndex, effectiveRange: nil) is CheckboxAttachment
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isOverCheckbox(at: point) {
            NSCursor.pointingHand.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: Init

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
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

        // Disable auto-substitutions
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false

        textContainerInset = NSSize(width: 10, height: 8)
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        guard let sm = slashMenu, sm.isVisible else {
            super.keyDown(with: event)
            return
        }

        let keyCode = event.keyCode
        switch keyCode {
        case 125: // arrow down
            sm.moveDown()
        case 126: // arrow up
            sm.moveUp()
        case 36: // Enter
            if let command = sm.selectedCommand {
                sm.hide()
                NotificationCenter.default.post(
                    name: .floatNoteSlashCommandSelected,
                    object: self,
                    userInfo: ["command": command]
                )
            }
        case 53: // Escape
            sm.hide()
            deleteSlashText()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - deleteSlashText

    /// Finds the "/" before the cursor in the current paragraph and deletes from "/" to cursor.
    func deleteSlashText() {
        guard let storage = textStorage,
              let selectedRange = selectedRanges.first as? NSRange else { return }

        let cursorPos = selectedRange.location
        let fullString = storage.string as NSString
        let paraRange = fullString.paragraphRange(for: NSRange(location: cursorPos, length: 0))

        // Search backward from cursor within the paragraph for "/"
        let searchRange = NSRange(location: paraRange.location, length: cursorPos - paraRange.location)
        let slashRange = fullString.range(of: "/", options: .backwards, range: searchRange)

        guard slashRange.location != NSNotFound else { return }

        let deleteRange = NSRange(
            location: slashRange.location,
            length: cursorPos - slashRange.location
        )
        if shouldChangeText(in: deleteRange, replacementString: "") {
            storage.replaceCharacters(in: deleteRange, with: "")
            didChangeText()
        }
    }

    // MARK: - insertNewline

    override func insertNewline(_ sender: Any?) {
        guard let storage = textStorage,
              let selectedRange = selectedRanges.first as? NSRange else {
            super.insertNewline(sender)
            return
        }

        let cursorPos = selectedRange.location
        let fullString = storage.string as NSString
        let paraRange = fullString.paragraphRange(for: NSRange(location: cursorPos, length: 0))

        // Get the style tag at the paragraph start
        let styleTag: String?
        if paraRange.length > 0 && paraRange.location < storage.length {
            styleTag = storage.attribute(.floatNoteLineStyle, at: paraRange.location, effectiveRange: nil) as? String
        } else {
            styleTag = nil
        }

        // Check for checkbox: paragraph starts with a CheckboxAttachment
        let isCheckboxLine = paragraphStartsWithCheckbox(paraRange: paraRange, storage: storage)
        let isCheckboxStyle = styleTag == LineStyle.text.rawValue && isCheckboxLine

        // Check for bullet
        let isBulletStyle = styleTag == LineStyle.bullet.rawValue

        // Check for blockquote
        let isBlockquoteStyle = styleTag == LineStyle.blockquote.rawValue

        // Check for numbered list
        let isNumberedListStyle = styleTag == LineStyle.numberedList.rawValue

        if isCheckboxStyle {
            // Get text after the attachment + space
            let textAfterPrefix = textAfterCheckboxPrefix(paraRange: paraRange, storage: storage)
            if textAfterPrefix.isEmpty {
                // Remove checkbox prefix — convert to plain text
                removeLinePrefix(in: paraRange, storage: storage)
            } else {
                super.insertNewline(sender)
                insertCheckbox()
            }
        } else if isBulletStyle {
            let textAfterBullet = textAfterBulletPrefix(paraRange: paraRange, storage: storage)
            if textAfterBullet.isEmpty {
                removeLinePrefix(in: paraRange, storage: storage)
            } else {
                super.insertNewline(sender)
                insertBulletPrefix()
            }
        } else if isBlockquoteStyle {
            let textAfterBlockquote = textAfterBlockquotePrefix(paraRange: paraRange, storage: storage)
            if textAfterBlockquote.isEmpty {
                removeBlockquotePrefix(in: paraRange, storage: storage)
            } else {
                super.insertNewline(sender)
                insertBlockquotePrefix()
            }
        } else if isNumberedListStyle {
            let textAfterNumber = textAfterNumberedPrefix(paraRange: paraRange, storage: storage)
            if textAfterNumber.isEmpty {
                removeNumberedListPrefix(in: paraRange, storage: storage)
            } else {
                let currentNumber = currentNumberedListNumber(paraRange: paraRange, storage: storage)
                super.insertNewline(sender)
                insertNumberedListPrefix(number: currentNumber + 1)
            }
        } else {
            super.insertNewline(sender)
            // Always ensure typing attributes are correct after newline
            let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
            typingAttributes = [
                .font: font,
                .foregroundColor: baseTextColor,
                .floatNoteLineStyle: LineStyle.text.rawValue
            ]
        }
    }

    // MARK: - deleteBackward

    override func deleteBackward(_ sender: Any?) {
        super.deleteBackward(sender)
        // After any deletion, ensure typing attributes have the correct color/font
        let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
        typingAttributes[.font] = font
        typingAttributes[.foregroundColor] = baseTextColor
    }

    // MARK: - Helpers

    /// Inserts a CheckboxAttachment + space with the checkbox line style.
    func insertCheckbox() {
        guard let storage = textStorage else { return }

        let attachment = CheckboxAttachment()
        attachment.isChecked = false

        let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseTextColor,
            .floatNoteLineStyle: LineStyle.text.rawValue
        ]

        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttributes(attrs, range: NSRange(location: 0, length: attachmentString.length))

        let space = NSAttributedString(string: " ", attributes: attrs)

        guard let insertRange = selectedRanges.first as? NSRange else { return }

        if shouldChangeText(in: insertRange, replacementString: "\u{FFFC} ") {
            storage.beginEditing()
            storage.replaceCharacters(in: insertRange, with: attachmentString)
            let afterAttachment = NSRange(location: insertRange.location + 1, length: 0)
            storage.replaceCharacters(in: afterAttachment, with: space)
            storage.endEditing()

            let newCursor = NSRange(location: insertRange.location + 2, length: 0)
            setSelectedRange(newCursor)
            typingAttributes = attrs
            didChangeText()
        }
    }

    private func insertBulletPrefix() {
        guard let storage = textStorage,
              let insertRange = selectedRanges.first as? NSRange else { return }

        let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .floatNoteLineStyle: LineStyle.bullet.rawValue
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseTextColor,
            .floatNoteLineStyle: LineStyle.bullet.rawValue
        ]
        let bullet = NSAttributedString(string: "• ", attributes: attrs)

        if shouldChangeText(in: insertRange, replacementString: "• ") {
            storage.replaceCharacters(in: insertRange, with: bullet)
            let newCursor = NSRange(location: insertRange.location + 2, length: 0)
            setSelectedRange(newCursor)
            typingAttributes = textAttrs
            didChangeText()
        }
    }

    /// Removes attachment + space (or bullet "• ") from the start of a paragraph and removes the style tag.
    func removeLinePrefix(in paraRange: NSRange, storage: NSTextStorage) {
        guard paraRange.length > 0 else { return }

        let fullString = storage.string as NSString

        // Determine prefix length
        let firstChar = fullString.character(at: paraRange.location)
        let isAttachment = firstChar == 0xFFFC // NSAttachmentCharacter
        let prefixLength: Int

        if isAttachment {
            // attachment (\uFFFC) + optional space
            if paraRange.length >= 2 {
                let secondChar = fullString.character(at: paraRange.location + 1)
                prefixLength = (secondChar == 0x0020) ? 2 : 1
            } else {
                prefixLength = 1
            }
        } else {
            // Check for "• " bullet
            let bulletPrefix = "• "
            let paraString = fullString.substring(with: paraRange)
            if paraString.hasPrefix(bulletPrefix) {
                prefixLength = (bulletPrefix as NSString).length
            } else {
                return
            }
        }

        let removeRange = NSRange(location: paraRange.location, length: prefixLength)
        if shouldChangeText(in: removeRange, replacementString: "") {
            storage.beginEditing()
            storage.replaceCharacters(in: removeRange, with: "")
            // Remove the line style attribute on the remaining paragraph characters
            let newParaLength = paraRange.length - prefixLength
            if newParaLength > 0 {
                let remainingRange = NSRange(location: paraRange.location, length: newParaLength)
                storage.removeAttribute(.floatNoteLineStyle, range: remainingRange)
            }
            storage.endEditing()

            let newCursor = NSRange(location: paraRange.location, length: 0)
            setSelectedRange(newCursor)

            // Reset typing attributes to base font/color after prefix removal
            let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
            typingAttributes = [
                .font: font,
                .foregroundColor: baseTextColor,
                .floatNoteLineStyle: LineStyle.text.rawValue
            ]

            // Also fix remaining text color if any text is left on this line
            let newParaRange2 = (storage.string as NSString).paragraphRange(for: newCursor)
            if newParaRange2.length > 0 {
                storage.addAttribute(.foregroundColor, value: baseTextColor, range: newParaRange2)
                storage.addAttribute(.font, value: font, range: newParaRange2)
            }

            didChangeText()
        }
    }

    // MARK: - Paragraph Inspection

    private func paragraphStartsWithCheckbox(paraRange: NSRange, storage: NSTextStorage) -> Bool {
        guard paraRange.length > 0, paraRange.location < storage.length else { return false }
        let attachment = storage.attribute(.attachment, at: paraRange.location, effectiveRange: nil)
        return attachment is CheckboxAttachment
    }

    private func textAfterCheckboxPrefix(paraRange: NSRange, storage: NSTextStorage) -> String {
        // prefix = attachment char (\uFFFC) + space = 2 chars
        let prefixLen = 2
        guard paraRange.length > prefixLen else { return "" }
        let textStart = paraRange.location + prefixLen
        let textLen = paraRange.length - prefixLen
        // Trim the trailing newline if present
        let raw = (storage.string as NSString).substring(with: NSRange(location: textStart, length: textLen))
        return raw.trimmingCharacters(in: .newlines)
    }

    private func textAfterBulletPrefix(paraRange: NSRange, storage: NSTextStorage) -> String {
        let bulletPrefix = "• "
        let prefixLen = (bulletPrefix as NSString).length
        guard paraRange.length > prefixLen else { return "" }
        let textStart = paraRange.location + prefixLen
        let textLen = paraRange.length - prefixLen
        let raw = (storage.string as NSString).substring(with: NSRange(location: textStart, length: textLen))
        return raw.trimmingCharacters(in: .newlines)
    }

    private func textAfterBlockquotePrefix(paraRange: NSRange, storage: NSTextStorage) -> String {
        let blockquotePrefix = "> "
        let prefixLen = (blockquotePrefix as NSString).length
        guard paraRange.length > prefixLen else { return "" }
        let textStart = paraRange.location + prefixLen
        let textLen = paraRange.length - prefixLen
        let raw = (storage.string as NSString).substring(with: NSRange(location: textStart, length: textLen))
        return raw.trimmingCharacters(in: .newlines)
    }

    private func textAfterNumberedPrefix(paraRange: NSRange, storage: NSTextStorage) -> String {
        let paraString = (storage.string as NSString).substring(with: paraRange)
        // Match "N. " prefix
        guard let range = paraString.range(of: #"^\d+\. "#, options: .regularExpression) else { return "" }
        let afterPrefix = String(paraString[range.upperBound...])
        return afterPrefix.trimmingCharacters(in: .newlines)
    }

    private func currentNumberedListNumber(paraRange: NSRange, storage: NSTextStorage) -> Int {
        let paraString = (storage.string as NSString).substring(with: paraRange)
        guard let range = paraString.range(of: #"^\d+"#, options: .regularExpression) else { return 1 }
        return Int(paraString[range]) ?? 1
    }

    private func insertBlockquotePrefix() {
        guard let storage = textStorage,
              let insertRange = selectedRanges.first as? NSRange else { return }

        let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
        let prefixAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .floatNoteLineStyle: LineStyle.blockquote.rawValue
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseTextColor,
            .floatNoteLineStyle: LineStyle.blockquote.rawValue
        ]
        let prefix = NSAttributedString(string: "> ", attributes: prefixAttrs)

        if shouldChangeText(in: insertRange, replacementString: "> ") {
            storage.replaceCharacters(in: insertRange, with: prefix)
            let newCursor = NSRange(location: insertRange.location + 2, length: 0)
            setSelectedRange(newCursor)
            typingAttributes = textAttrs
            didChangeText()
        }
    }

    private func insertNumberedListPrefix(number: Int) {
        guard let storage = textStorage,
              let insertRange = selectedRanges.first as? NSRange else { return }

        let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
        let prefixAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .floatNoteLineStyle: LineStyle.numberedList.rawValue
        ]
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: baseTextColor,
            .floatNoteLineStyle: LineStyle.numberedList.rawValue
        ]
        let prefixString = "\(number). "
        let prefix = NSAttributedString(string: prefixString, attributes: prefixAttrs)

        if shouldChangeText(in: insertRange, replacementString: prefixString) {
            storage.replaceCharacters(in: insertRange, with: prefix)
            let newCursor = NSRange(location: insertRange.location + (prefixString as NSString).length, length: 0)
            setSelectedRange(newCursor)
            typingAttributes = textAttrs
            didChangeText()
        }
    }

    private func removeBlockquotePrefix(in paraRange: NSRange, storage: NSTextStorage) {
        let blockquotePrefix = "> "
        let prefixLen = (blockquotePrefix as NSString).length
        guard paraRange.length >= prefixLen else { return }

        let paraString = (storage.string as NSString).substring(with: paraRange)
        guard paraString.hasPrefix(blockquotePrefix) else { return }

        let removeRange = NSRange(location: paraRange.location, length: prefixLen)
        if shouldChangeText(in: removeRange, replacementString: "") {
            storage.beginEditing()
            storage.replaceCharacters(in: removeRange, with: "")
            let newParaLength = paraRange.length - prefixLen
            if newParaLength > 0 {
                let remainingRange = NSRange(location: paraRange.location, length: newParaLength)
                storage.removeAttribute(.floatNoteLineStyle, range: remainingRange)
            }
            storage.endEditing()

            let newCursor = NSRange(location: paraRange.location, length: 0)
            setSelectedRange(newCursor)

            let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
            typingAttributes = [
                .font: font,
                .foregroundColor: baseTextColor,
                .floatNoteLineStyle: LineStyle.text.rawValue
            ]

            didChangeText()
        }
    }

    private func removeNumberedListPrefix(in paraRange: NSRange, storage: NSTextStorage) {
        let paraString = (storage.string as NSString).substring(with: paraRange)
        guard let range = paraString.range(of: #"^\d+\. "#, options: .regularExpression) else { return }
        let prefixLen = paraString.distance(from: paraString.startIndex, to: range.upperBound)

        let removeRange = NSRange(location: paraRange.location, length: prefixLen)
        if shouldChangeText(in: removeRange, replacementString: "") {
            storage.beginEditing()
            storage.replaceCharacters(in: removeRange, with: "")
            let newParaLength = paraRange.length - prefixLen
            if newParaLength > 0 {
                let remainingRange = NSRange(location: paraRange.location, length: newParaLength)
                storage.removeAttribute(.floatNoteLineStyle, range: remainingRange)
            }
            storage.endEditing()

            let newCursor = NSRange(location: paraRange.location, length: 0)
            setSelectedRange(newCursor)

            let font = AttributedStringBuilder.roundedFont(size: baseFontSize, bold: false)
            typingAttributes = [
                .font: font,
                .foregroundColor: baseTextColor,
                .floatNoteLineStyle: LineStyle.text.rawValue
            ]

            didChangeText()
        }
    }
}
