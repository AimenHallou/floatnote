import Foundation
@testable import FloatNote

struct TestPersistenceHelper {
    let persistence: PersistenceManager
    let defaults: UserDefaults
    let tempDir: URL
    private let suiteName: String

    init() {
        suiteName = "FloatNote.Tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        persistence = PersistenceManager(defaults: defaults, notesDirectory: tempDir)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDir)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
