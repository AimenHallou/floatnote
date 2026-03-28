import AppKit
import Foundation

// MARK: - GlobalConfig

struct GlobalConfig: Codable {
    var fontSize: Double = 13
    var opacity: Double = 0.85
    var tintColor: NoteTint = .clear
    var textColor: NoteTint = .clear
}

// MARK: - NoteConfig (per-note overrides, stored in UserDefaults)

struct NoteConfig: Codable {
    var name: String = "Note"
    var fontSize: Double?
    var opacity: Double?
    var tintColor: NoteTint?
    var textColor: NoteTint?
    var isCollapsed: Bool = false
    var windowX: Double?
    var windowY: Double?
    var windowW: Double?
    var windowH: Double?

    var windowFrame: NSRect? {
        guard let x = windowX, let y = windowY, let w = windowW, let h = windowH else { return nil }
        let frame = NSRect(x: x, y: y, width: w, height: h)
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        return onScreen ? frame : nil
    }

    mutating func setWindowFrame(_ frame: NSRect) {
        windowX = frame.origin.x
        windowY = frame.origin.y
        windowW = frame.size.width
        windowH = frame.size.height
    }
}

// MARK: - PersistenceManager

final class PersistenceManager {

    static let shared = PersistenceManager()

    let defaults: UserDefaults
    let notesDir: URL

    private enum Key {
        static let noteIds  = "floatnote.noteIds"
        static let hotkey   = "floatnote.hotkey"
        static let globalConfig = "floatnote.globalConfig"
        static let oldWindowFrame = "floatnote.windowFrame"

        static func noteConfig(_ id: UUID) -> String {
            "floatnote.note.\(id.uuidString).config"
        }
    }

    private func noteFileURL(_ id: UUID) -> URL {
        notesDir.appendingPathComponent("\(id.uuidString).txt")
    }

    init(defaults: UserDefaults, notesDirectory: URL) {
        self.defaults = defaults
        self.notesDir = notesDirectory
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FloatNote", isDirectory: true)
        self.init(defaults: .standard, notesDirectory: dir)
    }

    // MARK: - Global Config

    func saveGlobalConfig(_ config: GlobalConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Key.globalConfig)
        }
    }

    func loadGlobalConfig() -> GlobalConfig {
        guard let data = defaults.data(forKey: Key.globalConfig),
              let config = try? JSONDecoder().decode(GlobalConfig.self, from: data) else {
            return GlobalConfig()
        }
        return config
    }

    // MARK: - Note IDs

    func saveNoteIds(_ ids: [UUID]) {
        defaults.set(ids.map(\.uuidString), forKey: Key.noteIds)
    }

    func loadNoteIds() -> [UUID] {
        guard let strings = defaults.stringArray(forKey: Key.noteIds) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    // MARK: - Note Content

    func saveNote(_ text: String, id: UUID) {
        try? text.write(to: noteFileURL(id), atomically: true, encoding: .utf8)
    }

    func loadNote(id: UUID) -> String {
        (try? String(contentsOf: noteFileURL(id), encoding: .utf8)) ?? ""
    }

    // MARK: - Note Config

    func saveNoteConfig(_ config: NoteConfig, id: UUID) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: Key.noteConfig(id))
        }
    }

    func loadNoteConfig(id: UUID) -> NoteConfig {
        guard let data = defaults.data(forKey: Key.noteConfig(id)),
              let config = try? JSONDecoder().decode(NoteConfig.self, from: data) else {
            return NoteConfig()
        }
        return config
    }

    // MARK: - Delete Note

    func deleteNote(id: UUID) {
        try? FileManager.default.removeItem(at: noteFileURL(id))
        defaults.removeObject(forKey: Key.noteConfig(id))
    }

    // MARK: - Migration from old single-note format

    func migrateOldNoteIfNeeded() -> (text: String, frame: NSRect?)? {
        let oldNoteURL = notesDir.appendingPathComponent("note.txt")
        guard FileManager.default.fileExists(atPath: oldNoteURL.path) else { return nil }

        let text = (try? String(contentsOf: oldNoteURL, encoding: .utf8)) ?? ""

        var frame: NSRect? = nil
        if let dict = defaults.dictionary(forKey: Key.oldWindowFrame),
           let x = dict["x"] as? Double,
           let y = dict["y"] as? Double,
           let w = dict["w"] as? Double,
           let h = dict["h"] as? Double {
            let rect = NSRect(x: x, y: y, width: w, height: h)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) {
                frame = rect
            }
        }

        try? FileManager.default.removeItem(at: oldNoteURL)
        defaults.removeObject(forKey: Key.oldWindowFrame)

        return (text, frame)
    }

    // MARK: - Window Frame (global)

    func saveWindowFrame(_ frame: NSRect) {
        let dict: [String: Double] = [
            "x": frame.origin.x, "y": frame.origin.y,
            "w": frame.size.width, "h": frame.size.height
        ]
        defaults.set(dict, forKey: "floatnote.windowFrame.global")
    }

    func loadWindowFrame() -> NSRect? {
        guard let dict = defaults.dictionary(forKey: "floatnote.windowFrame.global"),
              let x = dict["x"] as? Double, let y = dict["y"] as? Double,
              let w = dict["w"] as? Double, let h = dict["h"] as? Double else { return nil }
        let frame = NSRect(x: x, y: y, width: w, height: h)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(frame) } ? frame : nil
    }

    // MARK: - Active Tab

    func saveActiveNoteId(_ id: UUID) {
        defaults.set(id.uuidString, forKey: "floatnote.activeNoteId")
    }

    func loadActiveNoteId() -> UUID? {
        guard let str = defaults.string(forKey: "floatnote.activeNoteId") else { return nil }
        return UUID(uuidString: str)
    }

    // MARK: - Hotkey

    func saveHotkey(_ combo: HotkeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            defaults.set(data, forKey: Key.hotkey)
        }
    }

    func loadHotkey() -> HotkeyCombo? {
        guard let data = defaults.data(forKey: Key.hotkey),
              let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) else {
            return nil
        }
        return combo
    }
}
