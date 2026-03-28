import AppKit

// MARK: - Custom NSAttributedString Keys

extension NSAttributedString.Key {
    /// Tags a paragraph with its LineStyle for round-trip parsing.
    static let floatNoteLineStyle = NSAttributedString.Key("floatNoteLineStyle")
}

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

        let baseFont = roundedFont(size: fontSize, bold: false)
        let newlineAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: resolvedColor,
            .floatNoteLineStyle: LineStyle.text.rawValue
        ]

        for (index, line) in lines.enumerated() {
            let paragraph = buildParagraph(for: line, fontSize: fontSize, resolvedColor: resolvedColor, lineIndex: index)
            // Append newline between lines (not after the last one)
            if index < lines.count - 1 {
                paragraph.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
            }
            result.append(paragraph)
        }

        return result
    }

    // MARK: Parse

    static func parseLines(from textStorage: NSTextStorage, fontSize: CGFloat) -> [NoteLine] {
        var lines: [NoteLine] = []
        let fullString = textStorage.string as NSString
        let totalLength = textStorage.length

        // Enumerate paragraph by paragraph using character ranges to avoid
        // the first-occurrence-of-substring bug when duplicate text exists.
        var searchLocation = 0
        while searchLocation <= totalLength {
            let charRange = NSRange(location: searchLocation, length: 0)
            let paragraphRange = fullString.paragraphRange(for: charRange)

            // Extract the substring for this paragraph (excluding trailing newline)
            let contentRange: NSRange
            if paragraphRange.length > 0 &&
               fullString.character(at: paragraphRange.location + paragraphRange.length - 1) == unichar(("\n" as UnicodeScalar).value) {
                contentRange = NSRange(location: paragraphRange.location, length: paragraphRange.length - 1)
            } else {
                contentRange = paragraphRange
            }

            let substring = fullString.substring(with: contentRange)

            // Read the line style tag directly from the correct paragraph range
            var detectedStyle: LineStyle = .text
            var isCheckbox = false
            var isChecked = false

            if paragraphRange.length > 0 && paragraphRange.location < totalLength {
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
                if paragraphRange.length > 0 && paragraphRange.location < totalLength {
                    let checkRange = NSRange(location: paragraphRange.location, length: min(paragraphRange.length, totalLength - paragraphRange.location))
                    textStorage.enumerateAttribute(.attachment, in: checkRange, options: []) { value, _, _ in
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
            } else {
                lines.append(NoteLine(
                    isCheckbox: isCheckbox,
                    isChecked: isChecked,
                    style: detectedStyle,
                    text: plainText
                ))
            }

            // Advance past this paragraph
            let nextLocation = paragraphRange.location + paragraphRange.length
            if nextLocation <= searchLocation {
                break  // Safety: prevent infinite loop
            }
            searchLocation = nextLocation

            // If we've consumed all characters, stop (avoids processing an extra empty paragraph)
            if searchLocation >= totalLength {
                break
            }
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
            let dividerAttrs: [NSAttributedString.Key: Any] = [
                .floatNoteLineStyle: LineStyle.divider.rawValue,
                .font: roundedFont(size: fontSize, bold: false),
                .foregroundColor: resolvedColor
            ]
            attachmentString.addAttributes(dividerAttrs, range: NSRange(location: 0, length: attachmentString.length))
            return attachmentString
        }
    }
}
