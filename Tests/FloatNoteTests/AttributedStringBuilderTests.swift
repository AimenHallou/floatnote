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

    @Test("Plain text round-trip")
    func plainText() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .text, text: "Hello world")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .text)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "Hello world")
    }

    @Test("Heading round-trip")
    func heading() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .heading, text: "My Heading")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .heading)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "My Heading")
    }

    @Test("Bullet round-trip")
    func bullet() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .bullet, text: "Bullet item")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .bullet)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "Bullet item")
    }

    @Test("Checkbox unchecked round-trip")
    func checkboxUnchecked() {
        let lines = [NoteLine(isCheckbox: true, isChecked: false, style: .text, text: "Task to do")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].isCheckbox == true)
        #expect(result[0].isChecked == false)
        #expect(result[0].style == .text)
        #expect(result[0].text == "Task to do")
    }

    @Test("Checkbox checked round-trip")
    func checkboxChecked() {
        let lines = [NoteLine(isCheckbox: true, isChecked: true, style: .text, text: "Done task")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].isCheckbox == true)
        #expect(result[0].isChecked == true)
        #expect(result[0].style == .text)
        #expect(result[0].text == "Done task")
    }

    @Test("Divider round-trip")
    func divider() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .divider, text: "")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .divider)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
    }

    @Test("Multi-line mixed content round-trip")
    func multiLineMixed() {
        let lines: [NoteLine] = [
            NoteLine(isCheckbox: false, isChecked: false, style: .heading, text: "Title"),
            NoteLine(isCheckbox: false, isChecked: false, style: .bullet, text: "Bullet point"),
            NoteLine(isCheckbox: true, isChecked: false, style: .text, text: "Unchecked task"),
            NoteLine(isCheckbox: true, isChecked: true, style: .text, text: "Checked task"),
            NoteLine(isCheckbox: false, isChecked: false, style: .divider, text: ""),
            NoteLine(isCheckbox: false, isChecked: false, style: .text, text: "Plain text")
        ]
        let result = roundTrip(lines)
        #expect(result.count == 6)

        #expect(result[0].style == .heading)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].text == "Title")

        #expect(result[1].style == .bullet)
        #expect(result[1].isCheckbox == false)
        #expect(result[1].text == "Bullet point")

        #expect(result[2].isCheckbox == true)
        #expect(result[2].isChecked == false)
        #expect(result[2].text == "Unchecked task")

        #expect(result[3].isCheckbox == true)
        #expect(result[3].isChecked == true)
        #expect(result[3].text == "Checked task")

        #expect(result[4].style == .divider)

        #expect(result[5].style == .text)
        #expect(result[5].isCheckbox == false)
        #expect(result[5].text == "Plain text")
    }

    @Test("Blockquote round-trip")
    func blockquote() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .blockquote, text: "Quoted text")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .blockquote)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "Quoted text")
    }

    @Test("Numbered list round-trip")
    func numberedList() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .numberedList, text: "First item")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .numberedList)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "First item")
    }

    @Test("Code block round-trip")
    func codeBlock() {
        let lines = [NoteLine(isCheckbox: false, isChecked: false, style: .codeBlock, text: "let x = 1")]
        let result = roundTrip(lines)
        #expect(result.count == 1)
        #expect(result[0].style == .codeBlock)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].isChecked == false)
        #expect(result[0].text == "let x = 1")
    }

    @Test("Duplicate lines preserve styles")
    func duplicateLines() {
        let lines: [NoteLine] = [
            NoteLine(isCheckbox: false, isChecked: false, style: .text, text: "Same text"),
            NoteLine(isCheckbox: false, isChecked: false, style: .text, text: "Same text"),
            NoteLine(isCheckbox: false, isChecked: false, style: .heading, text: "Same text")
        ]
        let result = roundTrip(lines)
        #expect(result.count == 3)
        #expect(result[0].style == .text)
        #expect(result[0].isCheckbox == false)
        #expect(result[0].text == "Same text")
        #expect(result[1].style == .text)
        #expect(result[1].isCheckbox == false)
        #expect(result[1].text == "Same text")
        #expect(result[2].style == .heading)
        #expect(result[2].isCheckbox == false)
        #expect(result[2].text == "Same text")
    }

    @Test("Empty line between paragraphs")
    func emptyLineBetweenParagraphs() {
        let lines: [NoteLine] = [
            NoteLine(isCheckbox: false, isChecked: false, style: .text, text: "First"),
            NoteLine(isCheckbox: false, isChecked: false, style: .text, text: ""),
            NoteLine(isCheckbox: false, isChecked: false, style: .text, text: "Third")
        ]
        let result = roundTrip(lines)
        #expect(result.count == 3)
        #expect(result[0].style == .text)
        #expect(result[0].text == "First")
        #expect(result[1].style == .text)
        #expect(result[1].text == "")
        #expect(result[2].style == .text)
        #expect(result[2].text == "Third")
    }
}
