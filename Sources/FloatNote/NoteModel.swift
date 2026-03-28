import Foundation
import SwiftUI

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

// MARK: - LineStyle

enum LineStyle: String, Equatable {
    case text, heading, bullet, divider
    case codeBlock, blockquote, numberedList
}

// MARK: - SlashCommand

enum SlashCommand: CaseIterable {
    case todo, heading, bullet, divider, clearCompleted, plainText
    case codeBlock, blockquote, numberedList

    var label: String {
        switch self {
        case .todo:           return "To-do"
        case .heading:        return "Heading"
        case .bullet:         return "Bullet"
        case .divider:        return "Divider"
        case .clearCompleted: return "Clear completed"
        case .plainText:      return "Plain text"
        case .codeBlock:      return "Code Block"
        case .blockquote:     return "Blockquote"
        case .numberedList:   return "Numbered List"
        }
    }

    var icon: String {
        switch self {
        case .todo:           return "checkmark.square"
        case .heading:        return "textformat.size.larger"
        case .bullet:         return "list.bullet"
        case .divider:        return "minus"
        case .clearCompleted: return "trash"
        case .plainText:      return "text.alignleft"
        case .codeBlock:      return "chevron.left.forwardslash.chevron.right"
        case .blockquote:     return "text.quote"
        case .numberedList:   return "list.number"
        }
    }
}

// MARK: - NoteLine

struct NoteLine: Identifiable, Equatable {
    let id: UUID
    var isCheckbox: Bool
    var isChecked: Bool
    var style: LineStyle
    var text: String

    init(id: UUID = UUID(), isCheckbox: Bool = false, isChecked: Bool = false, style: LineStyle = .text, text: String = "") {
        self.id = id
        self.isCheckbox = isCheckbox
        self.isChecked = isChecked
        self.style = style
        self.text = text
    }
}

// MARK: - GlobalSettings

@Observable
final class GlobalSettings {

    static let shared = GlobalSettings()

    var fontSize: Double {
        didSet { save() }
    }
    var opacity: Double {
        didSet { save() }
    }
    var tintColor: NoteTint {
        didSet { save() }
    }
    var textColor: NoteTint {
        didSet { save() }
    }

    @ObservationIgnored private let persistence: PersistenceManager

    private init() {
        self.persistence = .shared
        let cfg = PersistenceManager.shared.loadGlobalConfig()
        self.fontSize = cfg.fontSize
        self.opacity = cfg.opacity
        self.tintColor = cfg.tintColor
        self.textColor = cfg.textColor
    }

    init(persistence: PersistenceManager) {
        self.persistence = persistence
        let cfg = persistence.loadGlobalConfig()
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
        self.persistence.saveGlobalConfig(config)
    }
}

// MARK: - NoteModel

@Observable
final class NoteModel: Identifiable {

    let id: UUID

    var name: String {
        didSet { saveConfig() }
    }

    var lines: [NoteLine] = [] {
        didSet { scheduleSave() }
    }

    // Per-note overrides (nil = use global)
    var fontSizeOverride: Double? {
        didSet { saveConfig() }
    }
    var opacityOverride: Double? {
        didSet { saveConfig() }
    }
    var tintColorOverride: NoteTint? {
        didSet { saveConfig() }
    }
    var textColorOverride: NoteTint? {
        didSet { saveConfig() }
    }

    var isCollapsed: Bool {
        didSet { saveConfig() }
    }

    // Effective values — computed from override ?? global
    var fontSize: Double { fontSizeOverride ?? globalSettings.fontSize }
    var opacity: Double { opacityOverride ?? globalSettings.opacity }
    var tintColor: NoteTint { tintColorOverride ?? globalSettings.tintColor }
    var textColor: NoteTint { textColorOverride ?? globalSettings.textColor }

    @ObservationIgnored
    private var saveWorkItem: DispatchWorkItem?
    @ObservationIgnored
    private let persistence: PersistenceManager
    @ObservationIgnored
    private let globalSettings: GlobalSettings

    init(id: UUID, text: String? = nil, config: NoteConfig? = nil,
         persistence: PersistenceManager = .shared,
         globalSettings: GlobalSettings = .shared) {
        self.id = id
        self.persistence = persistence
        self.globalSettings = globalSettings
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
            } else if line.hasPrefix("# ") {
                return NoteLine(style: .heading, text: String(line.dropFirst(2)))
            } else if line.hasPrefix("• ") {
                return NoteLine(style: .bullet, text: String(line.dropFirst(2)))
            } else if line == "---" {
                return NoteLine(style: .divider)
            } else if line.hasPrefix("> ") {
                return NoteLine(style: .blockquote, text: String(line.dropFirst(2)))
            } else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                // Strip "N. " prefix
                if let spaceRange = line.range(of: ". ") {
                    return NoteLine(style: .numberedList, text: String(line[spaceRange.upperBound...]))
                }
                return NoteLine(style: .numberedList, text: line)
            } else {
                return NoteLine(text: line)
            }
        }
    }

    func serialize() -> String {
        lines.map { line in
            if line.isCheckbox {
                return "- [\(line.isChecked ? "x" : " ")] \(line.text)"
            }
            switch line.style {
            case .heading:      return "# \(line.text)"
            case .bullet:       return "• \(line.text)"
            case .divider:      return "---"
            case .text:         return line.text
            case .codeBlock:    return "```\n\(line.text)\n```"
            case .blockquote:   return "> \(line.text)"
            case .numberedList: return "1. \(line.text)"
            }
        }.joined(separator: "\n")
    }

    // MARK: - Line Operations

    func applySlashCommand(_ command: SlashCommand, to lineId: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == lineId }) else { return }
        switch command {
        case .todo:
            lines[index].isCheckbox = true
            lines[index].style = .text
        case .heading:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .heading
        case .bullet:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .bullet
        case .divider:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .divider
            lines[index].text = ""
        case .plainText:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .text
        case .codeBlock:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .codeBlock
        case .blockquote:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .blockquote
        case .numberedList:
            lines[index].isCheckbox = false
            lines[index].isChecked = false
            lines[index].style = .numberedList
        case .clearCompleted:
            clearCompleted()
        }
    }

    func clearCompleted() {
        lines.removeAll { $0.isCheckbox && $0.isChecked }
        if lines.isEmpty { lines = [NoteLine()] }
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
        let pm = persistence
        let item = DispatchWorkItem {
            pm.saveNote(text, id: noteId)
        }
        saveWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

// MARK: - NoteStore

@Observable
final class NoteStore {

    var notes: [NoteModel] = []
    var activeNoteId: UUID? {
        didSet {
            if let id = activeNoteId {
                persistence.saveActiveNoteId(id)
            }
        }
    }

    @ObservationIgnored
    private let persistence: PersistenceManager
    @ObservationIgnored
    private let globalSettings: GlobalSettings

    init(persistence: PersistenceManager = .shared, globalSettings: GlobalSettings = .shared) {
        self.persistence = persistence
        self.globalSettings = globalSettings
    }

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
            notes = [NoteModel(id: noteId, config: config, persistence: persistence, globalSettings: globalSettings)]
            activeNoteId = noteId
            return
        }

        let ids = persistence.loadNoteIds()
        if ids.isEmpty {
            addNote()
        } else {
            notes = ids.map { NoteModel(id: $0, persistence: persistence, globalSettings: globalSettings) }
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
        let model = NoteModel(id: id, config: config, persistence: persistence, globalSettings: globalSettings)
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
