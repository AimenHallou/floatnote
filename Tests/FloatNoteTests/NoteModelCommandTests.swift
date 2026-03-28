import Testing
import Foundation
@testable import FloatNote

@Suite("NoteModel Commands")
struct NoteModelCommandTests {

    private func makeNote(_ text: String) -> (NoteModel, TestPersistenceHelper) {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let note = NoteModel(id: UUID(), text: text, persistence: helper.persistence, globalSettings: gs)
        return (note, helper)
    }

    // MARK: - .todo

    @Test(".todo adds checkbox to plain text line")
    func todoAddsCheckbox() {
        let (note, helper) = makeNote("Buy milk")
        defer { helper.cleanup() }
        let lineId = note.lines[0].id
        note.applySlashCommand(.todo, to: lineId)
        #expect(note.lines[0].isCheckbox == true)
        #expect(note.lines[0].style == .text)
    }

    // MARK: - .heading

    @Test(".heading sets heading style and removes checkbox")
    func headingSetsStyleRemovesCheckbox() {
        let (note, helper) = makeNote("- [x] Done item")
        defer { helper.cleanup() }
        let lineId = note.lines[0].id
        note.applySlashCommand(.heading, to: lineId)
        #expect(note.lines[0].style == .heading)
        #expect(note.lines[0].isCheckbox == false)
        #expect(note.lines[0].isChecked == false)
    }

    // MARK: - .bullet

    @Test(".bullet sets bullet style")
    func bulletSetsBulletStyle() {
        let (note, helper) = makeNote("Some text")
        defer { helper.cleanup() }
        let lineId = note.lines[0].id
        note.applySlashCommand(.bullet, to: lineId)
        #expect(note.lines[0].style == .bullet)
        #expect(note.lines[0].isCheckbox == false)
    }

    // MARK: - .plainText

    @Test(".plainText strips all formatting from checkbox line")
    func plainTextStripsCheckbox() {
        let (note, helper) = makeNote("- [x] Done item")
        defer { helper.cleanup() }
        let lineId = note.lines[0].id
        note.applySlashCommand(.plainText, to: lineId)
        #expect(note.lines[0].style == .text)
        #expect(note.lines[0].isCheckbox == false)
        #expect(note.lines[0].isChecked == false)
    }

    @Test(".plainText strips all formatting from heading line")
    func plainTextStripsHeading() {
        let (note, helper) = makeNote("# My Heading")
        defer { helper.cleanup() }
        let lineId = note.lines[0].id
        note.applySlashCommand(.plainText, to: lineId)
        #expect(note.lines[0].style == .text)
        #expect(note.lines[0].isCheckbox == false)
    }

    // MARK: - clearCompleted

    @Test("clearCompleted removes only checked items")
    func clearCompletedRemovesOnlyChecked() {
        let (note, helper) = makeNote("- [x] Done\n- [ ] Not done\nPlain")
        defer { helper.cleanup() }
        note.clearCompleted()
        #expect(note.lines.count == 2)
        #expect(note.lines.allSatisfy { !($0.isCheckbox && $0.isChecked) })
    }

    @Test("clearCompleted on empty note doesn't crash")
    func clearCompletedEmptyNote() {
        let (note, helper) = makeNote("")
        defer { helper.cleanup() }
        // Should not crash
        note.clearCompleted()
        #expect(note.lines.count >= 1)
    }

    // MARK: - .codeBlock / .blockquote / .numberedList

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

    // MARK: - Nonexistent lineId

    @Test("applySlashCommand to nonexistent lineId is no-op")
    func applyCommandToNonexistentIdIsNoOp() {
        let (note, helper) = makeNote("Some text")
        defer { helper.cleanup() }
        let originalLines = note.lines
        note.applySlashCommand(.todo, to: UUID())
        #expect(note.lines.count == originalLines.count)
        #expect(note.lines[0].isCheckbox == originalLines[0].isCheckbox)
        #expect(note.lines[0].style == originalLines[0].style)
    }
}
