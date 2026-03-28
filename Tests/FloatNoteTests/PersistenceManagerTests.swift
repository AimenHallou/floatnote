import Testing
import Foundation
@testable import FloatNote

@Suite("PersistenceManager")
struct PersistenceManagerTests {

    @Test("saveNote/loadNote round-trip")
    func saveLoadNoteRoundTrip() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let id = UUID()
        let text = "Hello, FloatNote!"
        helper.persistence.saveNote(text, id: id)
        let loaded = helper.persistence.loadNote(id: id)
        #expect(loaded == text)
    }

    @Test("loadNote for nonexistent ID returns empty string")
    func loadNoteNonexistentReturnsEmpty() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let id = UUID()
        let loaded = helper.persistence.loadNote(id: id)
        #expect(loaded == "")
    }

    @Test("deleteNote removes file")
    func deleteNoteRemovesFile() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let id = UUID()
        helper.persistence.saveNote("some content", id: id)
        helper.persistence.deleteNote(id: id)
        let loaded = helper.persistence.loadNote(id: id)
        #expect(loaded == "")
    }

    @Test("saveNoteConfig/loadNoteConfig round-trip")
    func saveLoadNoteConfigRoundTrip() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let id = UUID()
        var config = NoteConfig()
        config.name = "My Test Note"
        config.fontSize = 16.0
        config.tintColor = .blue

        helper.persistence.saveNoteConfig(config, id: id)
        let loaded = helper.persistence.loadNoteConfig(id: id)

        #expect(loaded.name == "My Test Note")
        #expect(loaded.fontSize == 16.0)
        #expect(loaded.tintColor == .blue)
    }

    @Test("saveNoteIds/loadNoteIds round-trip")
    func saveLoadNoteIdsRoundTrip() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let ids = [UUID(), UUID(), UUID()]
        helper.persistence.saveNoteIds(ids)
        let loaded = helper.persistence.loadNoteIds()
        #expect(loaded == ids)
    }

    @Test("unicode content preserved")
    func unicodeContentPreserved() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let id = UUID()
        let text = "日本語テスト 🎵 émoji café naïve résumé"
        helper.persistence.saveNote(text, id: id)
        let loaded = helper.persistence.loadNote(id: id)
        #expect(loaded == text)
    }

    @Test("saveGlobalConfig/loadGlobalConfig round-trip")
    func saveLoadGlobalConfigRoundTrip() {
        let helper = TestPersistenceHelper()
        defer { helper.cleanup() }

        let config = GlobalConfig(fontSize: 18.0, opacity: 0.75, tintColor: .green, textColor: .purple)
        helper.persistence.saveGlobalConfig(config)
        let loaded = helper.persistence.loadGlobalConfig()

        #expect(loaded.fontSize == 18.0)
        #expect(loaded.opacity == 0.75)
        #expect(loaded.tintColor == .green)
        #expect(loaded.textColor == .purple)
    }
}
