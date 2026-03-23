import SwiftUI
import AppKit

// MARK: - Slash Menu State

final class SlashMenuState: ObservableObject {
    @Published var isVisible = false
    @Published var filter = ""
    @Published var selectedIndex = 0
    @Published var charIndex: Int?

    var filteredCommands: [SlashCommand] {
        if filter.isEmpty { return SlashCommand.allCases }
        return SlashCommand.allCases.filter {
            $0.label.localizedCaseInsensitiveContains(filter)
        }
    }

    var selectedCommand: SlashCommand? {
        let cmds = filteredCommands
        guard cmds.indices.contains(selectedIndex) else { return cmds.first }
        return cmds[selectedIndex]
    }

    func show(charIndex: Int) {
        self.charIndex = charIndex
        self.filter = ""
        self.selectedIndex = 0
        self.isVisible = true
    }

    func hide() {
        isVisible = false
        filter = ""
        selectedIndex = 0
        charIndex = nil
    }

    func moveUp() {
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveDown() {
        selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1)
    }
}

// MARK: - ContentView

struct ContentView: View {

    @EnvironmentObject private var store: NoteStore
    @ObservedObject private var global = GlobalSettings.shared
    @State private var isHovering = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // ── Frosted glass ────────────────────────────────────────────
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Tab bar ──────────────────────────────────────────────
                TabBar(isWindowHovering: isHovering, onOpenSettings: { showSettings = true })

                // ── Note editors (all alive, only active visible) ────────
                ZStack {
                    ForEach(store.notes) { note in
                        let isActive = store.activeNoteId == note.id
                        NoteEditorView(
                            model: note,
                            isWindowHovering: isHovering
                        )
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(isActive)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            SettingsView(store: store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatNoteOpenSettings)) { _ in
            showSettings = true
        }
    }
}

// MARK: - Tab Bar

struct TabBar: View {

    @EnvironmentObject private var store: NoteStore
    let isWindowHovering: Bool
    let onOpenSettings: () -> Void
    @State private var editingTabId: UUID?
    @State private var editingName = ""
    @State private var hoveredTabId: UUID?

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(store.notes) { note in
                    TabItemView(
                        note: note,
                        isActive: store.activeNoteId == note.id,
                        isHovered: hoveredTabId == note.id,
                        isEditing: editingTabId == note.id,
                        editingName: $editingName,
                        canDelete: store.notes.count > 1,
                        onSelect: { store.activeNoteId = note.id },
                        onStartRename: {
                            editingName = note.name
                            editingTabId = note.id
                        },
                        onCommitRename: {
                            if !editingName.trimmingCharacters(in: .whitespaces).isEmpty {
                                note.name = editingName
                            }
                            editingTabId = nil
                        },
                        onCancelRename: { editingTabId = nil },
                        onDelete: { store.removeNote(note.id) }
                    )
                    .onHover { hovering in
                        hoveredTabId = hovering ? note.id : nil
                    }
                }

                // ── Add tab button ───────────────────────────────────────
                Button(action: { store.addNote() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .help("New note")
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }

            // ── Settings button (top right) ─────────────────────────
            if isWindowHovering {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .help("Settings")
                .padding(.trailing, 6)
                .padding(.top, 6)
            }
        }
        // Separator line between tabs and content
        Divider()
            .opacity(0.3)
        .onChange(of: store.activeNoteId) { _ in
            if editingTabId != nil {
                // Commit current rename before switching
                if let id = editingTabId,
                   let note = store.notes.first(where: { $0.id == id }),
                   !editingName.trimmingCharacters(in: .whitespaces).isEmpty {
                    note.name = editingName
                }
                editingTabId = nil
            }
        }
    }
}

// MARK: - Tab Item

struct TabItemView: View {

    @ObservedObject var note: NoteModel
    let isActive: Bool
    let isHovered: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let canDelete: Bool
    let onSelect: () -> Void
    let onStartRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            // Clickable tab content (name + color dot)
            HStack(spacing: 3) {
                if note.tintColor != .clear {
                    Circle()
                        .fill(note.tintColor.color.opacity(0.8))
                        .frame(width: 6, height: 6)
                }

                if isEditing {
                    RenameField(text: $editingName, onCommit: onCommitRename, onCancel: onCancelRename)
                        .frame(minWidth: 30, maxWidth: 80)
                } else {
                    Text(note.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(isActive ? .primary : .secondary)
                }
            }
            .contentShape(Rectangle())
            .overlay(TabClickHandler(onSingleClick: onSelect, onDoubleClick: onStartRename))

            // Close button — sits outside the click handler overlay
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .opacity(isActive && !isEditing ? 1 : 0)
                .allowsHitTesting(isActive && !isEditing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? Color.primary.opacity(0.08) : Color.clear)
        )
        .contextMenu {
            Button("Rename") { onStartRename() }

            Menu("Color") {
                ForEach(NoteTint.allCases) { tint in
                    Button(action: { note.tintColorOverride = tint }) {
                        Label(tint.label, systemImage: tint == .clear ? "circle.dashed" : "circle.fill")
                    }
                }
            }

            if canDelete {
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

// MARK: - Rename Field (inline NSTextField for tab rename)

struct RenameField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 11)
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = text
        field.delegate = context.coordinator
        // Auto-focus
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RenameField
        init(parent: RenameField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                parent.onCommit()
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// MARK: - Note Editor

struct NoteEditorView: View {

    @ObservedObject var model: NoteModel
    @ObservedObject private var global = GlobalSettings.shared
    @StateObject private var slashMenu = SlashMenuState()
    let isWindowHovering: Bool
    @State private var slashMenuPosition: CGPoint?

    var body: some View {
        ZStack {
            // ── Tint overlay (reacts to model changes) ──────────────────
            if model.tintColor != .clear {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.tintColor.color.opacity(0.12))
                    .allowsHitTesting(false)
            }

            NoteTextViewRepresentable(
                model: model,
                slashMenu: slashMenu,
                slashMenuPosition: $slashMenuPosition
            )

            if slashMenu.isVisible, let pos = slashMenuPosition {
                SlashMenuOverlay(slashMenu: slashMenu) { command in
                    NotificationCenter.default.post(
                        name: .floatNoteSlashCommandSelected,
                        object: nil,
                        userInfo: ["command": command]
                    )
                }
                .position(x: pos.x, y: pos.y)
            }
        }
    }

}

// MARK: - Slash Menu Overlay

struct SlashMenuOverlay: View {
    @ObservedObject var slashMenu: SlashMenuState
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        let commands = slashMenu.filteredCommands
        if !commands.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.element) { index, command in
                    Button(action: { onSelect(command) }) {
                        HStack(spacing: 8) {
                            Image(systemName: command.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            Text(command.label)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            index == slashMenu.selectedIndex
                                ? RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(0.15))
                                : nil
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Interactive button hover modifier

struct HoverHighlight: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .opacity(isHovered ? 0.5 : 1.0)
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.12)) { isHovered = inside }
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

extension View {
    func pointerOnHover() -> some View {
        modifier(HoverHighlight())
    }
}

// MARK: - Tab click handler (instant mouseDown, no SwiftUI tap delay)

struct TabClickHandler: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClickView {
        let view = ClickView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ClickView, context: Context) {
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }

    final class ClickView: NSView {
        var onSingleClick: (() -> Void)?
        var onDoubleClick: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 {
                onDoubleClick?()
            } else {
                onSingleClick?()
            }
        }
    }
}
