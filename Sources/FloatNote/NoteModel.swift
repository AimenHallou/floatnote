import Foundation
import Combine

/// Shared observable model that bridges persistence and the SwiftUI view.
final class NoteModel: ObservableObject {

    static let shared = NoteModel()

    @Published var text: String = "" {
        didSet {
            scheduleSave()
        }
    }

    private var saveWorkItem: DispatchWorkItem?

    private init() {
        text = PersistenceManager.shared.loadNote()
    }

    // Debounce saves: coalesce rapid keystrokes into one disk write every 0.3s.
    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            PersistenceManager.shared.saveNote(self.text)
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
