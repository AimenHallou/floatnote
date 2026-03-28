import Testing
import Foundation
@testable import FloatNote

@Suite("NoteModel Parse")
struct NoteModelParseTests {

    // MARK: - Checkbox round-trips

    @Test("checked checkbox round-trips")
    func checkedCheckboxRoundTrip() {
        let lines = NoteModel.parse("- [x] Buy milk")
        #expect(lines.count == 1)
        #expect(lines[0].isCheckbox == true)
        #expect(lines[0].isChecked == true)
        #expect(lines[0].text == "Buy milk")
    }

    @Test("unchecked checkbox round-trips")
    func uncheckedCheckboxRoundTrip() {
        let lines = NoteModel.parse("- [ ] Buy milk")
        #expect(lines.count == 1)
        #expect(lines[0].isCheckbox == true)
        #expect(lines[0].isChecked == false)
        #expect(lines[0].text == "Buy milk")
    }

    @Test("checkbox with empty text round-trips")
    func checkboxEmptyTextRoundTrip() {
        let lines = NoteModel.parse("- [ ] ")
        #expect(lines.count == 1)
        #expect(lines[0].isCheckbox == true)
        #expect(lines[0].text == "")
    }

    // MARK: - Other line types

    @Test("heading round-trips")
    func headingRoundTrip() {
        let lines = NoteModel.parse("# My Heading")
        #expect(lines.count == 1)
        #expect(lines[0].style == .heading)
        #expect(lines[0].isCheckbox == false)
        #expect(lines[0].text == "My Heading")
    }

    @Test("bullet round-trips")
    func bulletRoundTrip() {
        let lines = NoteModel.parse("• My bullet")
        #expect(lines.count == 1)
        #expect(lines[0].style == .bullet)
        #expect(lines[0].isCheckbox == false)
        #expect(lines[0].text == "My bullet")
    }

    @Test("divider round-trips")
    func dividerRoundTrip() {
        let lines = NoteModel.parse("---")
        #expect(lines.count == 1)
        #expect(lines[0].style == .divider)
        #expect(lines[0].text == "")
    }

    @Test("plain text round-trips")
    func plainTextRoundTrip() {
        let lines = NoteModel.parse("Hello world")
        #expect(lines.count == 1)
        #expect(lines[0].style == .text)
        #expect(lines[0].isCheckbox == false)
        #expect(lines[0].text == "Hello world")
    }

    // MARK: - Edge cases

    @Test("empty string returns empty array")
    func emptyStringReturnsEmpty() {
        let lines = NoteModel.parse("")
        #expect(lines.isEmpty)
    }

    @Test("whitespace-only line parses as plain text")
    func whitespaceOnlyLine() {
        let lines = NoteModel.parse("   ")
        #expect(lines.count == 1)
        #expect(lines[0].style == .text)
        #expect(lines[0].text == "   ")
    }

    @Test("unicode and emoji preserved")
    func unicodeEmojiPreserved() {
        let lines = NoteModel.parse("日本語 🎵 café")
        #expect(lines.count == 1)
        #expect(lines[0].text == "日本語 🎵 café")
    }

    // MARK: - Multiline

    @Test("multiline mixed content parses correctly")
    func multilineMixedContent() {
        let text = "# Title\n- [x] Done\n- [ ] Todo\n• Item\n---\nPlain"
        let lines = NoteModel.parse(text)
        #expect(lines.count == 6)

        #expect(lines[0].style == .heading)
        #expect(lines[0].text == "Title")

        #expect(lines[1].isCheckbox == true)
        #expect(lines[1].isChecked == true)
        #expect(lines[1].text == "Done")

        #expect(lines[2].isCheckbox == true)
        #expect(lines[2].isChecked == false)
        #expect(lines[2].text == "Todo")

        #expect(lines[3].style == .bullet)
        #expect(lines[3].text == "Item")

        #expect(lines[4].style == .divider)

        #expect(lines[5].style == .text)
        #expect(lines[5].text == "Plain")
    }

    // MARK: - Serialize stability

    @Test("serialize then re-parse is stable")
    func serializeThenReparseIsStable() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }
        let gs = GlobalSettings(persistence: helper.persistence)
        let text = "# Title\n- [x] Done\n- [ ] Todo\n• Item\n---\nPlain"
        let note = NoteModel(id: UUID(), text: text, persistence: helper.persistence, globalSettings: gs)

        let serialized = note.serialize()
        let reparsed = NoteModel.parse(serialized)

        #expect(reparsed.count == note.lines.count)
        for (a, b) in zip(note.lines, reparsed) {
            #expect(a.isCheckbox == b.isCheckbox)
            #expect(a.isChecked == b.isChecked)
            #expect(a.style == b.style)
            #expect(a.text == b.text)
        }
    }
}
