import SwiftUI
import AppKit

// MARK: - Slash Menu State

final class SlashMenuState: ObservableObject {
    @Published var isVisible = false
    @Published var filter = ""
    @Published var selectedIndex = 0
    @Published var lineId: UUID?

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

    func show(lineId: UUID) {
        self.lineId = lineId
        self.filter = ""
        self.selectedIndex = 0
        self.isVisible = true
    }

    func hide() {
        isVisible = false
        filter = ""
        selectedIndex = 0
        lineId = nil
    }

    func moveUp() {
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveDown() {
        selectedIndex = min(filteredCommands.count - 1, selectedIndex + 1)
    }

    func updateFilter(_ text: String) {
        // Extract text after "/"
        if let slashIndex = text.firstIndex(of: "/") {
            filter = String(text[text.index(after: slashIndex)...])
        } else {
            filter = ""
        }
        selectedIndex = 0
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
            // Color dot
            if note.tintColor != .clear {
                Circle()
                    .fill(note.tintColor.color.opacity(0.8))
                    .frame(width: 6, height: 6)
            }

            // Name or rename field
            if isEditing {
                RenameField(text: $editingName, onCommit: onCommitRename, onCancel: onCancelRename)
                    .frame(minWidth: 30, maxWidth: 80)
            } else {
                Text(note.name)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }

            // Close button (space always reserved, visible only on active)
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
        .contentShape(Rectangle())
        .overlay(TabClickHandler(onSingleClick: onSelect, onDoubleClick: onStartRename))
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
    @State private var focusedLineId: UUID?
    @State private var allLinesSelected = false
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            // ── Tint overlay (reacts to model changes) ──────────────────
            if model.tintColor != .clear {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(model.tintColor.color.opacity(0.12))
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
            // ── Line editor ──────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach($model.lines) { $line in
                        if line.style == .divider {
                            // ── Divider line ─────────────────────────────
                            Divider()
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                        } else {
                            // ── Editable line ────────────────────────────
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if line.isCheckbox {
                                    Button(action: { model.toggleCheckbox(line.id) }) {
                                        Image(systemName: line.isChecked ? "checkmark.square.fill" : "square")
                                            .font(.system(size: CGFloat(model.fontSize) * 0.9))
                                            .foregroundStyle(line.isChecked ? .secondary : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    .pointerOnHover()
                                } else if line.style == .bullet {
                                    Text("\u{2022}")
                                        .font(.system(size: CGFloat(model.fontSize), design: .rounded))
                                        .foregroundStyle(.secondary)
                                }

                                LineTextField(
                                    text: $line.text,
                                    lineId: line.id,
                                    fontSize: line.style == .heading
                                        ? CGFloat(model.fontSize * 1.4)
                                        : CGFloat(model.fontSize),
                                    isBold: line.style == .heading,
                                    isChecked: line.isCheckbox && line.isChecked,
                                    textColor: model.textColor,
                                    onSubmit: {
                                        if line.isCheckbox && line.text.isEmpty {
                                            model.toggleLineType(line.id)
                                            return
                                        }
                                        if line.style == .bullet && line.text.isEmpty {
                                            line.style = .text
                                            return
                                        }
                                        let newId = model.insertLine(
                                            after: line.id,
                                            checkbox: line.isCheckbox
                                        )
                                        // Carry over bullet style
                                        if line.style == .bullet {
                                            if let idx = model.lines.firstIndex(where: { $0.id == newId }) {
                                                model.lines[idx].style = .bullet
                                            }
                                        }
                                        postFocus(lineId: newId, cursorAtEnd: false)
                                    },
                                    onBackspaceEmpty: {
                                        if line.isCheckbox {
                                            model.toggleLineType(line.id)
                                            return
                                        }
                                        if line.style != .text {
                                            line.style = .text
                                            return
                                        }
                                        guard let index = model.lines.firstIndex(where: { $0.id == line.id }),
                                              index > 0 else { return }
                                        let prevId = model.lines[index - 1].id
                                        model.deleteLine(line.id)
                                        postFocus(lineId: prevId, cursorAtEnd: true)
                                    },
                                    onPaste: { pastedText in
                                        let existing = line.text
                                        if let lastId = model.pasteLines(pastedText, at: line.id, appendToExisting: existing) {
                                            postFocus(lineId: lastId, cursorAtEnd: true)
                                        }
                                    },
                                    slashMenu: slashMenu,
                                    onSlashCommand: { command in
                                        model.applySlashCommand(command, to: line.id)
                                    }
                                )
                            }
                            .padding(.vertical, 1)
                            .background(
                                allLinesSelected
                                    ? RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.2))
                                    : nil
                            )
                            .overlay(alignment: .topLeading) {
                                if slashMenu.isVisible && slashMenu.lineId == line.id {
                                    SlashMenuOverlay(slashMenu: slashMenu) { command in
                                        model.applySlashCommand(command, to: line.id)
                                        slashMenu.hide()
                                    }
                                    .offset(y: 24)
                                }
                            }
                            .zIndex(slashMenu.lineId == line.id ? 1 : 0)
                        }
                    }

                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let lastId = model.lines.last?.id {
                                postFocus(lineId: lastId, cursorAtEnd: true)
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let lastId = model.lines.last?.id {
                        postFocus(lineId: lastId, cursorAtEnd: true)
                    }
                }
            }

        }
        } // ZStack
        .onReceive(NotificationCenter.default.publisher(for: .floatNoteLineFocused)) { notification in
            guard let lineId = notification.userInfo?["lineId"] as? UUID,
                  model.lines.contains(where: { $0.id == lineId }) else { return }
            focusedLineId = lineId
            if allLinesSelected { exitSelectAll() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .floatNoteSelectAllLines)) { _ in
            enterSelectAll()
        }
        .onChange(of: model.lines) { _ in
            if allLinesSelected { exitSelectAll() }
        }
    }

    private func enterSelectAll() {
        allLinesSelected = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
                self.copyAllLines()
                self.exitSelectAll()
                return nil // consume the event
            }
            // Any other key exits select-all
            DispatchQueue.main.async { self.exitSelectAll() }
            return event
        }
    }

    private func exitSelectAll() {
        allLinesSelected = false
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func copyAllLines() {
        let text = model.serialize()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func postFocus(lineId: UUID, cursorAtEnd: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .floatNoteFocusLine, object: nil,
                userInfo: ["lineId": lineId, "cursorAtEnd": cursorAtEnd]
            )
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

// MARK: - LineTextField (wrapping, self-sizing)

struct LineTextField: View {

    @Binding var text: String
    let lineId: UUID
    let fontSize: CGFloat
    var isBold: Bool = false
    let isChecked: Bool
    let textColor: NoteTint
    let onSubmit: () -> Void
    let onBackspaceEmpty: () -> Void
    var onPaste: ((_ clipboardText: String) -> Void)?
    var slashMenu: SlashMenuState?
    var onSlashCommand: ((_ command: SlashCommand) -> Void)?

    @State private var dynamicHeight: CGFloat = 20

    var body: some View {
        LineTextFieldRepresentable(
            text: $text,
            dynamicHeight: $dynamicHeight,
            lineId: lineId,
            fontSize: fontSize,
            isBold: isBold,
            isChecked: isChecked,
            textColor: textColor,
            onSubmit: onSubmit,
            onBackspaceEmpty: onBackspaceEmpty,
            onPaste: onPaste,
            slashMenu: slashMenu,
            onSlashCommand: onSlashCommand
        )
        .frame(height: dynamicHeight)
    }
}

// MARK: - WrappingTextField (NSTextField subclass)

final class WrappingTextField: NSTextField {
    var onPaste: ((String) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let cell = cell else { return super.intrinsicContentSize }
        let width = bounds.width > 0 ? bounds.width : 200
        let rect = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return NSSize(width: NSView.noIntrinsicMetric, height: max(rect.height, 18))
    }

    override func textDidChange(_ notification: Notification) {
        if let editor = currentEditor(), editor.string.contains("\n") || editor.string.contains("\r") {
            let pasted = editor.string
            editor.string = ""
            stringValue = ""
            onPaste?(pasted)
            return
        }
        super.textDidChange(notification)
        invalidateIntrinsicContentSize()
        recalcHeight()
    }

    override func layout() {
        super.layout()
        recalcHeight()
    }

    func recalcHeight() {
        let newHeight = intrinsicContentSize.height
        onHeightChange?(newHeight)
    }
}

// MARK: - LineTextFieldRepresentable

struct LineTextFieldRepresentable: NSViewRepresentable {

    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    let lineId: UUID
    let fontSize: CGFloat
    var isBold: Bool = false
    let isChecked: Bool
    let textColor: NoteTint
    let onSubmit: () -> Void
    let onBackspaceEmpty: () -> Void
    var onPaste: ((_ clipboardText: String) -> Void)?
    var slashMenu: SlashMenuState?
    var onSlashCommand: ((_ command: SlashCommand) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WrappingTextField {
        let field = WrappingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.delegate = context.coordinator
        field.onPaste = { pastedText in context.coordinator.handlePaste(pastedText) }
        field.onHeightChange = { height in
            DispatchQueue.main.async { self.dynamicHeight = height }
        }
        context.coordinator.field = field
        context.coordinator.startObserving()
        return field
    }

    func updateNSView(_ nsView: WrappingTextField, context: Context) {
        context.coordinator.parent = self
        nsView.onPaste = { t in context.coordinator.handlePaste(t) }
        nsView.onHeightChange = { height in
            DispatchQueue.main.async { self.dynamicHeight = height }
        }

        let base = isBold
            ? NSFont.boldSystemFont(ofSize: fontSize)
            : NSFont.systemFont(ofSize: fontSize)
        let font: NSFont
        if let desc = base.fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: desc, size: fontSize) ?? base
        } else {
            font = base
        }

        let baseColor = textColor.nsColor

        if let editor = nsView.currentEditor() as? NSTextView {
            nsView.font = font
            let range = NSRange(location: 0, length: (editor.string as NSString).length)
            if isChecked {
                editor.textStorage?.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.secondaryLabelColor
                ], range: range)
                editor.insertionPointColor = .secondaryLabelColor
            } else {
                editor.textStorage?.removeAttribute(.strikethroughStyle, range: range)
                editor.textStorage?.addAttribute(.foregroundColor, value: baseColor, range: range)
                editor.insertionPointColor = baseColor
            }
        } else {
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if isChecked {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attrs[.foregroundColor] = NSColor.secondaryLabelColor
            } else {
                attrs[.foregroundColor] = baseColor
            }
            nsView.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
        }

        nsView.invalidateIntrinsicContentSize()
        nsView.recalcHeight()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {

        var parent: LineTextFieldRepresentable
        weak var field: NSTextField?
        private var observer: Any?

        init(parent: LineTextFieldRepresentable) { self.parent = parent }

        func startObserving() {
            observer = NotificationCenter.default.addObserver(
                forName: .floatNoteFocusLine, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self,
                      let targetId = notification.userInfo?["lineId"] as? UUID,
                      targetId == self.parent.lineId,
                      let field = self.field else { return }
                field.window?.makeFirstResponder(field)
                let cursorAtEnd = notification.userInfo?["cursorAtEnd"] as? Bool ?? false
                if cursorAtEnd, let editor = field.currentEditor() {
                    editor.selectedRange = NSRange(location: field.stringValue.count, length: 0)
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            NotificationCenter.default.post(
                name: .floatNoteLineFocused, object: nil,
                userInfo: ["lineId": parent.lineId]
            )
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
            (field as? WrappingTextField)?.recalcHeight()

            // Slash menu: detect "/" and manage filtering
            guard let sm = parent.slashMenu else { return }
            if field.stringValue.contains("/") {
                if !sm.isVisible {
                    sm.show(lineId: parent.lineId)
                }
                sm.updateFilter(field.stringValue)
            } else if sm.isVisible && sm.lineId == parent.lineId {
                sm.hide()
            }
        }

        func handlePaste(_ text: String) {
            parent.onPaste?(text)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            // Slash menu key handling
            if let sm = parent.slashMenu, sm.isVisible && sm.lineId == parent.lineId {
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    sm.moveDown()
                    return true
                }
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    sm.moveUp()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                    if let command = sm.selectedCommand {
                        // Clear the slash text
                        if let field = self.field {
                            field.stringValue = ""
                            parent.text = ""
                        }
                        sm.hide()
                        parent.onSlashCommand?(command)
                    }
                    return true
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    // Clear the slash text and dismiss
                    if let field = self.field {
                        field.stringValue = ""
                        parent.text = ""
                    }
                    sm.hide()
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if parent.text.isEmpty {
                    parent.onBackspaceEmpty()
                    return true
                }
            }
            if commandSelector == #selector(NSResponder.selectAll(_:)) {
                // If already fully selected, escalate to select-all-lines
                let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
                if textView.selectedRange == fullRange {
                    NotificationCenter.default.post(name: .floatNoteSelectAllLines, object: nil)
                    return true
                }
            }
            return false
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
