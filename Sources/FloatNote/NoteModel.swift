import Foundation
import SwiftUI
import Combine

// MARK: - NoteTint

enum NoteTint: String, Codable, CaseIterable, Identifiable {
    case clear, yellow, blue, green, pink, orange, purple

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .clear:  return .clear
        case .yellow: return .yellow
        case .blue:   return .blue
        case .green:  return .green
        case .pink:   return .pink
        case .orange: return .orange
        case .purple: return .purple
        }
    }

    var nsColor: NSColor {
        switch self {
        case .clear:  return .labelColor
        case .yellow: return NSColor(Color.yellow)
        case .blue:   return NSColor(Color.blue)
        case .green:  return NSColor(Color.green)
        case .pink:   return NSColor(Color.pink)
        case .orange: return NSColor(Color.orange)
        case .purple: return NSColor(Color.purple)
        }
    }

    var label: String {
        rawValue == "clear" ? "Default" : rawValue.capitalized
    }
}

// MARK: - NoteLine

struct NoteLine: Identifiable, Equatable {
    let id: UUID
    var isCheckbox: Bool
    var isChecked: Bool
    var text: String

    init(id: UUID = UUID(), isCheckbox: Bool = false, isChecked: Bool = false, text: String = "") {
        self.id = id
        self.isCheckbox = isCheckbox
        self.isChecked = isChecked
        self.text = text
    }
}

// MARK: - GlobalSettings

final class GlobalSettings: ObservableObject {

    static let shared = GlobalSettings()

    @Published var fontSize: Double {
        didSet { save() }
    }
    @Published var opacity: Double {
        didSet { save() }
    }
    @Published var tintColor: NoteTint {
        didSet { save() }
    }
    @Published var textColor: NoteTint {
        didSet { save() }
    }

    private init() {
        let cfg = PersistenceManager.shared.loadGlobalConfig()
        self.fontSize = cfg.fontSize
        self.opacity = cfg.opacity
        self.tintColor = cfg.tintColor
        self.textColor = cfg.textColor
    }

    private func save() {
        let config = GlobalConfig(
            fontSize: fontSize, opacity: opacity,
            tintColor: tintColor, textColor: textColor
        )
        PersistenceManager.shared.saveGlobalConfig(config)
    }
}

// MARK: - NoteModel

final class NoteModel: ObservableObject, Identifiable {

    let id: UUID

    @Published var name: String {
        didSet { saveConfig() }
    }

    @Published var lines: [NoteLine] = [] {
        didSet { scheduleSave() }
    }

    // Per-note overrides (nil = use global)
    @Published var fontSizeOverride: Double? {
        didSet { saveConfig() }
    }
    @Published var opacityOverride: Double? {
        didSet { saveConfig() }
    }
    @Published var tintColorOverride: NoteTint? {
        didSet { saveConfig() }
    }
    @Published var textColorOverride: NoteTint? {
        didSet { saveConfig() }
    }

    @Published var isCollapsed: Bool {
        didSet { saveConfig() }
    }

    // Effective values (override ?? global)
    var fontSize: Double { fontSizeOverride ?? GlobalSettings.shared.fontSize }
    var opacity: Double { opacityOverride ?? GlobalSettings.shared.opacity }
    var tintColor: NoteTint { tintColorOverride ?? GlobalSettings.shared.tintColor }
    var textColor: NoteTint { textColorOverride ?? GlobalSettings.shared.textColor }

    private var saveWorkItem: DispatchWorkItem?
    private let persistence = PersistenceManager.shared

    init(id: UUID, text: String? = nil, config: NoteConfig? = nil) {
        self.id = id
        let cfg = config ?? persistence.loadNoteConfig(id: id)
        self.name = cfg.name
        self.fontSizeOverride = cfg.fontSize
        self.opacityOverride = cfg.opacity
        self.tintColorOverride = cfg.tintColor
        self.textColorOverride = cfg.textColor
        self.isCollapsed = cfg.isCollapsed

        let content = text ?? persistence.loadNote(id: id)
        lines = Self.parse(content)
        if lines.isEmpty { lines = [NoteLine()] }
    }

    // MARK: - Parse / Serialize

    static func parse(_ text: String) -> [NoteLine] {
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: "\n").map { line in
            if line.hasPrefix("- [x] ") {
                return NoteLine(isCheckbox: true, isChecked: true, text: String(line.dropFirst(6)))
            } else if line.hasPrefix("- [ ] ") {
                return NoteLine(isCheckbox: true, isChecked: false, text: String(line.dropFirst(6)))
            } else {
                return NoteLine(text: line)
            }
        }
    }

    func serialize() -> String {
        lines.map { line in
            if line.isCheckbox {
                return "- [\(line.isChecked ? "x" : " ")] \(line.text)"
            } else {
                return line.text
            }
        }.joined(separator: "\n")
    }

    // MARK: - Line Operations

    @discardableResult
    func insertLine(after id: UUID, checkbox: Bool = false) -> UUID {
        let newLine = NoteLine(isCheckbox: checkbox)
        if let index = lines.firstIndex(where: { $0.id == id }) {
            lines.insert(newLine, at: index + 1)
        } else {
            lines.append(newLine)
        }
        return newLine.id
    }

    func deleteLine(_ id: UUID) {
        guard lines.count > 1 else {
            if let index = lines.firstIndex(where: { $0.id == id }) {
                lines[index] = NoteLine()
            }
            return
        }
        lines.removeAll { $0.id == id }
    }

    func toggleCheckbox(_ id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].isChecked.toggle()
    }

    func toggleLineType(_ id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].isCheckbox.toggle()
        if !lines[index].isCheckbox {
            lines[index].isChecked = false
        }
    }

    @discardableResult
    func pasteLines(_ text: String, at lineId: UUID, appendToExisting: String) -> UUID? {
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !rawLines.isEmpty else { return nil }
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return nil }

        lines[index].text = appendToExisting + rawLines[0]
        lines[index].isCheckbox = true

        var lastId = lineId
        for i in 1..<rawLines.count {
            let newLine = NoteLine(isCheckbox: true, text: rawLines[i])
            if let insertIdx = lines.firstIndex(where: { $0.id == lastId }) {
                lines.insert(newLine, at: insertIdx + 1)
            }
            lastId = newLine.id
        }
        return lastId
    }

    func clearAll() {
        lines = [NoteLine()]
    }

    // MARK: - Window Frame

    func saveWindowFrame(_ frame: NSRect) {
        var config = persistence.loadNoteConfig(id: id)
        config.setWindowFrame(frame)
        persistence.saveNoteConfig(config, id: id)
    }

    // MARK: - Persistence

    private func saveConfig() {
        var config = persistence.loadNoteConfig(id: id)
        config.name = name
        config.fontSize = fontSizeOverride
        config.opacity = opacityOverride
        config.tintColor = tintColorOverride
        config.textColor = textColorOverride
        config.isCollapsed = isCollapsed
        persistence.saveNoteConfig(config, id: id)
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let text = serialize()
        let noteId = id
        let item = DispatchWorkItem {
            PersistenceManager.shared.saveNote(text, id: noteId)
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

// MARK: - NoteStore

final class NoteStore: ObservableObject {

    @Published var notes: [NoteModel] = []
    @Published var activeNoteId: UUID? {
        didSet {
            if let id = activeNoteId {
                PersistenceManager.shared.saveActiveNoteId(id)
            }
        }
    }

    private let persistence = PersistenceManager.shared

    var activeNote: NoteModel? {
        notes.first { $0.id == activeNoteId }
    }

    func load() {
        if let migration = persistence.migrateOldNoteIfNeeded() {
            let noteId = UUID()
            var config = NoteConfig(name: "Note 1")
            if let frame = migration.frame { config.setWindowFrame(frame) }
            persistence.saveNoteConfig(config, id: noteId)
            persistence.saveNote(migration.text, id: noteId)
            persistence.saveNoteIds([noteId])
            notes = [NoteModel(id: noteId, config: config)]
            activeNoteId = noteId
            return
        }

        let ids = persistence.loadNoteIds()
        if ids.isEmpty {
            addNote()
        } else {
            notes = ids.map { NoteModel(id: $0) }
            let savedActive = persistence.loadActiveNoteId()
            activeNoteId = notes.contains(where: { $0.id == savedActive }) ? savedActive : notes.first?.id
        }
    }

    @discardableResult
    func addNote() -> NoteModel {
        let id = UUID()
        var config = NoteConfig()
        config.name = "Note \(notes.count + 1)"
        persistence.saveNoteConfig(config, id: id)
        persistence.saveNote("", id: id)
        let model = NoteModel(id: id, config: config)
        notes.append(model)
        activeNoteId = id
        saveNoteIds()
        return model
    }

    func removeNote(_ id: UUID) {
        guard notes.count > 1 else { return }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if activeNoteId == id {
            let newIndex = index > 0 ? index - 1 : index + 1
            activeNoteId = notes[newIndex].id
        }
        notes.remove(at: index)
        persistence.deleteNote(id: id)
        saveNoteIds()
    }

    func saveNoteIds() {
        persistence.saveNoteIds(notes.map(\.id))
    }
}
