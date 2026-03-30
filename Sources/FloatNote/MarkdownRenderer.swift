import AppKit
import Markdown

// MARK: - MarkdownRenderer

struct MarkdownRenderer: MarkupWalker {

    private(set) var result = NSMutableAttributedString()

    private let fontSize: CGFloat
    private let textColor: NSColor

    // State
    private var isBold: Bool = false
    private var isItalic: Bool = false
    private var isInsideBlockQuote: Bool = false
    private var isInsideCodeBlock: Bool = false
    private var isOrderedList: Bool = false
    private var listItemNumber: Int = 0
    private var needsNewlineBefore: Bool = false

    init(fontSize: CGFloat, textColor: NSColor) {
        self.fontSize = fontSize
        self.textColor = textColor
    }

    // MARK: - Entry Point

    static func render(markdown: String, fontSize: CGFloat, textColor: NSColor) -> NSMutableAttributedString {
        let document = Document(parsing: markdown)
        var renderer = MarkdownRenderer(fontSize: fontSize, textColor: textColor)
        renderer.visit(document)
        return renderer.result
    }

    // MARK: - Block Visitors

    mutating func visitHeading(_ heading: Heading) {
        appendNewlineIfNeeded()
        let headingFont = AttributedStringBuilder.roundedFont(size: fontSize * 1.4, bold: true)
        let savedBold = isBold
        isBold = true
        let startIndex = result.length
        descendInto(heading)
        isBold = savedBold
        // Apply heading font and style tag over the range we just appended
        let range = NSRange(location: startIndex, length: result.length - startIndex)
        if range.length > 0 {
            result.addAttribute(.font, value: headingFont, range: range)
            result.addAttribute(.foregroundColor, value: textColor, range: range)
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.heading.rawValue, range: range)
        }
        needsNewlineBefore = true
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        appendNewlineIfNeeded()
        let startIndex = result.length
        descendInto(paragraph)
        let range = NSRange(location: startIndex, length: result.length - startIndex)
        if range.length > 0 && !isInsideBlockQuote && !isInsideCodeBlock {
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.text.rawValue, range: range)
        }
        needsNewlineBefore = true
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        appendNewlineIfNeeded()
        let attachment = DividerAttachment()
        let attachmentStr = NSMutableAttributedString(attachment: attachment)
        let attrs: [NSAttributedString.Key: Any] = [
            .floatNoteLineStyle: LineStyle.divider.rawValue,
            .font: AttributedStringBuilder.roundedFont(size: fontSize, bold: false),
            .foregroundColor: textColor
        ]
        attachmentStr.addAttributes(attrs, range: NSRange(location: 0, length: attachmentStr.length))
        result.append(attachmentStr)
        needsNewlineBefore = true
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        appendNewlineIfNeeded()
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let bg = NSColor.quaternaryLabelColor
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.headIndent = 8
        paraStyle.firstLineHeadIndent = 8
        paraStyle.tailIndent = -8
        let attrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: textColor,
            .backgroundColor: bg,
            .paragraphStyle: paraStyle,
            .floatNoteLineStyle: LineStyle.codeBlock.rawValue
        ]
        // Strip trailing newline from code block content
        let code = codeBlock.code.hasSuffix("\n")
            ? String(codeBlock.code.dropLast())
            : codeBlock.code
        result.append(NSAttributedString(string: code, attributes: attrs))
        needsNewlineBefore = true
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        appendNewlineIfNeeded()
        let savedInsideBlockQuote = isInsideBlockQuote
        isInsideBlockQuote = true
        let startIndex = result.length
        descendInto(blockQuote)
        isInsideBlockQuote = savedInsideBlockQuote
        // Apply blockquote paragraph style and tag
        let range = NSRange(location: startIndex, length: result.length - startIndex)
        if range.length > 0 {
            let paraStyle = NSMutableParagraphStyle()
            paraStyle.headIndent = 20
            paraStyle.firstLineHeadIndent = 20
            result.addAttribute(.paragraphStyle, value: paraStyle, range: range)
            result.addAttribute(.floatNoteLineStyle, value: LineStyle.blockquote.rawValue, range: range)
        }
        needsNewlineBefore = true
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        appendNewlineIfNeeded()
        let savedOrdered = isOrderedList
        let savedNumber = listItemNumber
        isOrderedList = true
        listItemNumber = Int(orderedList.startIndex)
        descendInto(orderedList)
        isOrderedList = savedOrdered
        listItemNumber = savedNumber
        needsNewlineBefore = true
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        appendNewlineIfNeeded()
        let savedOrdered = isOrderedList
        isOrderedList = false
        descendInto(unorderedList)
        isOrderedList = savedOrdered
        needsNewlineBefore = true
    }

    mutating func visitListItem(_ listItem: ListItem) {
        appendNewlineIfNeeded()

        if let checkbox = listItem.checkbox {
            // Checkbox list item
            let isChecked = checkbox == .checked
            let attachment = CheckboxAttachment()
            attachment.isChecked = isChecked
            attachment.fontSize = fontSize

            let font = AttributedStringBuilder.roundedFont(size: fontSize, bold: false)
            let checkboxAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .floatNoteLineStyle: LineStyle.text.rawValue
            ]
            let attachmentStr = NSMutableAttributedString(attachment: attachment)
            attachmentStr.addAttributes(checkboxAttrs, range: NSRange(location: 0, length: attachmentStr.length))
            result.append(attachmentStr)
            result.append(NSAttributedString(string: " ", attributes: checkboxAttrs))

            let startIndex = result.length
            descendInto(listItem)
            let range = NSRange(location: startIndex, length: result.length - startIndex)
            if range.length > 0 {
                result.addAttribute(.floatNoteLineStyle, value: LineStyle.text.rawValue, range: range)
                if isChecked {
                    result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                }
            }
        } else if isOrderedList {
            let prefix = "\(listItemNumber). "
            listItemNumber += 1
            let font = AttributedStringBuilder.roundedFont(size: fontSize, bold: false)
            let prefixAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .floatNoteLineStyle: LineStyle.numberedList.rawValue
            ]
            result.append(NSAttributedString(string: prefix, attributes: prefixAttrs))
            let startIndex = result.length
            descendInto(listItem)
            let range = NSRange(location: startIndex, length: result.length - startIndex)
            if range.length > 0 {
                result.addAttribute(.floatNoteLineStyle, value: LineStyle.numberedList.rawValue, range: range)
            }
        } else {
            // Bullet list item
            let font = AttributedStringBuilder.roundedFont(size: fontSize, bold: false)
            let bulletAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .floatNoteLineStyle: LineStyle.bullet.rawValue
            ]
            result.append(NSAttributedString(string: "• ", attributes: bulletAttrs))
            let startIndex = result.length
            descendInto(listItem)
            let range = NSRange(location: startIndex, length: result.length - startIndex)
            if range.length > 0 {
                result.addAttribute(.floatNoteLineStyle, value: LineStyle.bullet.rawValue, range: range)
            }
        }

        needsNewlineBefore = true
    }

    // MARK: - Inline Visitors

    mutating func visitText(_ text: Text) {
        let font = currentFont()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        result.append(NSAttributedString(string: text.string, attributes: attrs))
    }

    mutating func visitStrong(_ strong: Strong) {
        let savedBold = isBold
        isBold = true
        descendInto(strong)
        isBold = savedBold
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        let savedItalic = isItalic
        isItalic = true
        descendInto(emphasis)
        isItalic = savedItalic
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        let monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: textColor,
            .backgroundColor: NSColor.quaternaryLabelColor
        ]
        result.append(NSAttributedString(string: inlineCode.code, attributes: attrs))
    }

    mutating func visitLink(_ link: Link) {
        let startIndex = result.length
        descendInto(link)
        let range = NSRange(location: startIndex, length: result.length - startIndex)
        if range.length > 0, let destination = link.destination, let url = URL(string: destination) {
            result.addAttribute(.link, value: url, range: range)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            result.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        }
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: currentFont(),
            .foregroundColor: textColor
        ]
        result.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: currentFont(),
            .foregroundColor: textColor
        ]
        result.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    // MARK: - Helpers

    private func currentFont() -> NSFont {
        AttributedStringBuilder.roundedFont(size: fontSize, bold: isBold)
    }

    private mutating func appendNewlineIfNeeded() {
        guard needsNewlineBefore && result.length > 0 else { return }
        let font = AttributedStringBuilder.roundedFont(size: fontSize, bold: false)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .floatNoteLineStyle: LineStyle.text.rawValue
        ]
        result.append(NSAttributedString(string: "\n", attributes: attrs))
        needsNewlineBefore = false
    }
}
