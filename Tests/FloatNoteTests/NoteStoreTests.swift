import Testing
import Foundation
@testable import FloatNote

@Suite("NoteStore")
struct NoteStoreTests {

    private func makeStore() -> (NoteStore, TestPersistenceHelper) {
        let helper = TestPersistenceHelper()
        let gs = GlobalSettings(persistence: helper.persistence)
        let store = NoteStore(persistence: helper.persistence, globalSettings: gs)
        return (store, helper)
    }

    // MARK: - load

    @Test("load with no saved data creates one default note")
    func loadNoSavedDataCreatesOneNote() {
        let (store, helper) = makeStore()
        defer { helper.cleanup() }
        store.load()
        #expect(store.notes.count == 1)
        #expect(store.activeNoteId == store.notes.first?.id)
    }

    // MARK: - addNote

    @Test("addNote increments count and sets activeNoteId")
    func addNoteIncrementsCountAndSetsActive() {
        let (store, helper) = makeStore()
        defer { helper.cleanup() }
        store.load()
        let initialCount = store.notes.count
        let newNote = store.addNote()
        #expect(store.notes.count == initialCount + 1)
        #expect(store.activeNoteId == newNote.id)
    }

    // MARK: - removeNote

    @Test("removeNote on last note refuses deletion")
    func removeNoteOnLastNoteRefuses() {
        let (store, helper) = makeStore()
        defer { helper.cleanup() }
        store.load()
        #expect(store.notes.count == 1)
        let onlyId = store.notes[0].id
        store.removeNote(onlyId)
        #expect(store.notes.count == 1)
    }

    @Test("removeNote updates activeNoteId")
    func removeNoteUpdatesActiveNoteId() {
        let (store, helper) = makeStore()
        defer { helper.cleanup() }
        store.load()
        _ = store.addNote()
        #expect(store.notes.count == 2)

        let activeId = store.activeNoteId!
        store.removeNote(activeId)
        #expect(store.notes.count == 1)
        #expect(store.activeNoteId != activeId)
        #expect(store.activeNoteId == store.notes.first?.id)
    }
}
