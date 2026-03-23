import AppKit

// MARK: - Custom NSAttributedString Keys

extension NSAttributedString.Key {
    /// Tags a paragraph with its LineStyle for round-trip parsing.
    static let floatNoteLineStyle = NSAttributedString.Key("floatNoteLineStyle")
}

// MARK: - Temporary Stubs (will be moved to NoteTextView.swift in Task 2)

class CheckboxAttachment: NSTextAttachment {
    var isChecked: Bool = false
    var lineIndex: Int = 0
}

class DividerAttachment: NSTextAttachment {}

// MARK: - AttributedStringBuilder

enum AttributedStringBuilder {

    // MARK: Build

    static func build(
        from lines: [NoteLine],
        fontSize: CGFloat,
        textColor: NoteTint
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let resolvedColor = textColor.nsColor

        for (index, line) in lines.enumerated() {
            let paragraph = buildParagraph(for: line, fontSize: fontSize, resolvedColor: resolvedColor, lineIndex: index)
            // Append newline between lines (not after the last one)
            if index < lines.count - 1 {
                paragraph.append(NSAttributedString(string: "\n"))
            }
            result.append(paragraph)
        }

        return result
    }

    // MARK: Parse

    static func parseLines(from textStorage: NSTextStorage, fontSize: CGFloat) -> [NoteLine] {
        var lines: [NoteLine] = []
        let fullString = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: textStorage.length)

        // Enumerate paragraph by paragraph
        fullString.enumerateSubstrings(in: fullRange, options: .byParagraphs) { substring, _, _, _ in
            guard let substring = substring else { return }

            // Determine the range for this paragraph in the attributed string
            let paragraphStart = fullString.range(of: substring).location
            let paragraphRange: NSRange
            if paragraphStart == NSNotFound {
                // Fallback: scan from current offset
                paragraphRange = NSRange(location: 0, length: 0)
            } else {
                paragraphRange = NSRange(location: paragraphStart, length: (substring as NSString).length)
            }

            // Read the line style tag if present
            var detectedStyle: LineStyle = .text
            var isCheckbox = false
            var isChecked = false

            if paragraphRange.length > 0 && paragraphRange.location + paragraphRange.length <= textStorage.length {
                let attrs = textStorage.attributes(at: paragraphRange.location, effectiveRange: nil)
                if let styleRaw = attrs[.floatNoteLineStyle] as? String,
                   let style = LineStyle(rawValue: styleRaw) {
                    detectedStyle = style
                }
            }

            // Strip attachment characters (\u{FFFC}) and collect plain text
            var plainText = substring.replacingOccurrences(of: "\u{FFFC}", with: "")

            // Strip bullet prefix if present (for display round-trip)
            if detectedStyle == .bullet && plainText.hasPrefix("• ") {
                plainText = String(plainText.dropFirst(2))
            }

            // Detect checkbox from attachment presence in the paragraph range
            if detectedStyle == .text {
                // Walk attributes in range to detect CheckboxAttachment
                if paragraphRange.length > 0 && paragraphRange.location + paragraphRange.length <= textStorage.length {
                    textStorage.enumerateAttribute(.attachment, in: paragraphRange, options: []) { value, _, _ in
                        if let attachment = value as? CheckboxAttachment {
                            isCheckbox = true
                            isChecked = attachment.isChecked
                        }
                    }
                }
                if isCheckbox {
                    // Strip leading space after attachment char
                    if plainText.hasPrefix(" ") {
                        plainText = String(plainText.dropFirst())
                    }
                }
            }

            if detectedStyle == .divider {
                lines.append(NoteLine(isCheckbox: false, isChecked: false, style: .divider, text: ""))
                return
            }

            lines.append(NoteLine(
                isCheckbox: isCheckbox,
                isChecked: isChecked,
                style: detectedStyle,
                text: plainText
            ))
        }

        if lines.isEmpty {
            lines = [NoteLine()]
        }

        return lines
    }

    // MARK: Font Helper

    static func roundedFont(size: CGFloat, bold: Bool) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor
            .withDesign(.rounded) {
            return NSFont(descriptor: descriptor, size: size) ?? base
        }
        return base
    }

    // MARK: - Private

    private static func buildParagraph(
        for line: NoteLine,
        fontSize: CGFloat,
        resolvedColor: NSColor,
        lineIndex: Int
    ) -> NSMutableAttributedString {
        let styleTag: [NSAttributedString.Key: Any] = [
            .floatNoteLineStyle: line.isCheckbox ? LineStyle.text.rawValue : line.style.rawValue
        ]

        switch (line.isCheckbox, line.style) {

        case (true, _):
            // Checkbox line: attachment + space + text
            let attachment = CheckboxAttachment()
            attachment.isChecked = line.isChecked
            attachment.lineIndex = lineIndex

            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttributes(styleTag, range: NSRange(location: 0, length: attachmentString.length))

            let spacer = NSAttributedString(
                string: " ",
                attributes: styleTag.merging([
                    .font: roundedFont(size: fontSize, bold: false),
                    .foregroundColor: resolvedColor
                ]) { $1 }
            )

            var textAttrs: [NSAttributedString.Key: Any] = styleTag.merging([
                .font: roundedFont(size: fontSize, bold: false),
                .foregroundColor: line.isChecked ? NSColor.secondaryLabelColor : resolvedColor
            ]) { $1 }

            if line.isChecked {
                textAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                textAttrs[.strikethroughColor] = NSColor.secondaryLabelColor
            }

            let textString = NSAttributedString(string: line.text, attributes: textAttrs)

            let result = NSMutableAttributedString()
            result.append(attachmentString)
            result.append(spacer)
            result.append(textString)
            return result

        case (false, .text):
            let attrs: [NSAttributedString.Key: Any] = styleTag.merging([
                .font: roundedFont(size: fontSize, bold: false),
                .foregroundColor: resolvedColor
            ]) { $1 }
            return NSMutableAttributedString(string: line.text, attributes: attrs)

        case (false, .heading):
            let attrs: [NSAttributedString.Key: Any] = styleTag.merging([
                .font: roundedFont(size: fontSize * 1.4, bold: true),
                .foregroundColor: resolvedColor
            ]) { $1 }
            return NSMutableAttributedString(string: line.text, attributes: attrs)

        case (false, .bullet):
            let bulletAttrs: [NSAttributedString.Key: Any] = styleTag.merging([
                .font: roundedFont(size: fontSize, bold: false),
                .foregroundColor: NSColor.secondaryLabelColor
            ]) { $1 }
            let textAttrs: [NSAttributedString.Key: Any] = styleTag.merging([
                .font: roundedFont(size: fontSize, bold: false),
                .foregroundColor: resolvedColor
            ]) { $1 }

            let result = NSMutableAttributedString()
            result.append(NSAttributedString(string: "• ", attributes: bulletAttrs))
            result.append(NSAttributedString(string: line.text, attributes: textAttrs))
            return result

        case (false, .divider):
            let attachment = DividerAttachment()
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttributes(styleTag, range: NSRange(location: 0, length: attachmentString.length))
            return attachmentString
        }
    }
}
