import AppKit
import Foundation

/// Handles all persistence: note text, window frame, hotkey combo.
final class PersistenceManager {

    static let shared = PersistenceManager()

    // MARK: - Keys

    private enum Key {
        static let windowFrame  = "floatnote.windowFrame"
        static let hotkey       = "floatnote.hotkey"
    }

    // MARK: - Note file URL

    private var noteFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("FloatNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("note.txt")
    }

    private init() {}

    // MARK: - Note

    func saveNote(_ text: String) {
        do {
            try text.write(to: noteFileURL, atomically: true, encoding: .utf8)
        } catch {
            // Non-fatal — user will see note is the same as before.
            print("[FloatNote] Failed to save note: \(error)")
        }
    }

    func loadNote() -> String {
        guard let text = try? String(contentsOf: noteFileURL, encoding: .utf8) else {
            return ""
        }
        return text
    }

    // MARK: - Window Frame

    func saveWindowFrame(_ frame: NSRect) {
        let dict: [String: Double] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height
        ]
        UserDefaults.standard.set(dict, forKey: Key.windowFrame)
    }

    func loadWindowFrame() -> NSRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: Key.windowFrame),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["w"] as? Double,
              let h = dict["h"] as? Double
        else { return nil }

        let frame = NSRect(x: x, y: y, width: w, height: h)

        // Sanity-check: make sure the frame is actually on a screen.
        let onScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame)
        }
        return onScreen ? frame : nil
    }

    // MARK: - Hotkey

    func saveHotkey(_ combo: HotkeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: Key.hotkey)
        }
    }

    func loadHotkey() -> HotkeyCombo? {
        guard let data = UserDefaults.standard.data(forKey: Key.hotkey),
              let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data)
        else { return nil }
        return combo
    }
}
