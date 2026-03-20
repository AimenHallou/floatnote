import SwiftUI

// MARK: - Settings View

enum SettingsTab: Hashable {
    case general
    case global
    case note(UUID)
}

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NoteStore
    @ObservedObject private var global = GlobalSettings.shared
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Tab bar ─────────────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    settingsTabButton(label: "General", isSelected: selectedTab == .general) {
                        selectedTab = .general
                    }

                    settingsTabButton(label: "Global", isSelected: selectedTab == .global) {
                        selectedTab = .global
                    }

                    ForEach(store.notes) { note in
                        settingsTabButton(
                            label: note.name,
                            isSelected: selectedTab == .note(note.id),
                            tint: note.tintColor
                        ) {
                            selectedTab = .note(note.id)
                            store.activeNoteId = note.id
                        }
                    }
                }
            }

            Divider()

            switch selectedTab {
            case .general:
                GeneralSettingsContent()
            case .global:
                GlobalSettingsContent(global: global)
            case .note(let id):
                if let model = store.notes.first(where: { $0.id == id }) {
                    NoteSettingsContent(model: model, dismiss: dismiss)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if let id = store.activeNoteId {
                selectedTab = .note(id)
            }
        }
    }

    private func settingsTabButton(label: String, isSelected: Bool, tint: NoteTint = .clear, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if tint != .clear {
                    Circle()
                        .fill(tint.color.opacity(0.8))
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Settings

struct GeneralSettingsContent: View {

    @State private var isRecording = false
    @State private var recordedCombo: HotkeyCombo? = nil

    private var hotkey: HotkeyCombo {
        recordedCombo ?? HotkeyManager.shared.hotkey
    }

    private var dataPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FloatNote").path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Hotkey ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Show / Hide Hotkey")
                HStack {
                    Text(hotkey.displayString)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )

                    if isRecording {
                        Text("Press new shortcut...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isRecording {
                        Button("Cancel") {
                            isRecording = false
                            recordedCombo = nil
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Change") {
                            isRecording = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .background(
                HotkeyRecorderOverlay(isRecording: $isRecording, onRecord: { combo in
                    recordedCombo = combo
                    isRecording = false
                    // Defer event tap re-registration to next run loop
                    // so the local key monitor is fully torn down first
                    DispatchQueue.main.async {
                        HotkeyManager.shared.updateHotkey(combo)
                    }
                })
            )

            // ── Data Location ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("Data Location")
                HStack(spacing: 6) {
                    Text(dataPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataPath)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Finder")
                }
            }

            // ── About ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("FloatNote")
                        .font(.system(size: 11, weight: .semibold))
                    Text("v1.0.0")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Button(action: {
                    if let url = URL(string: "https://github.com/AimenHallou/floatnote") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 10))
                        Text("github.com/AimenHallou/floatnote")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Hotkey Recorder (NSView overlay to capture key events)

struct HotkeyRecorderOverlay: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (HotkeyCombo) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RecorderView()
        view.onRecord = onRecord
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? RecorderView else { return }
        view.onRecord = onRecord
        if isRecording {
            // Install local key monitor
            view.startMonitoring()
        } else {
            view.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var view: RecorderView?
    }

    final class RecorderView: NSView {
        var onRecord: ((HotkeyCombo) -> Void)?
        private var monitor: Any?

        func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let hasModifier = flags.contains(.maskCommand) || flags.contains(.maskControl)
                if hasModifier {
                    let combo = HotkeyCombo(
                        keyCode: Int64(event.keyCode),
                        modifiers: flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl]).rawValue
                    )
                    self?.onRecord?(combo)
                    return nil // consume
                }
                return event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit { stopMonitoring() }
    }
}

// MARK: - Global Settings Content

struct GlobalSettingsContent: View {

    @ObservedObject var global: GlobalSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Default settings for all notes")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsRowFontSize(
                value: global.fontSize,
                decrease: { global.fontSize = max(global.fontSize - 1, 9) },
                increase: { global.fontSize = min(global.fontSize + 1, 32) }
            )

            SettingsRowOpacity(value: $global.opacity)

            SettingsRowColor(label: "Note Color", selection: global.tintColor) { global.tintColor = $0 }

            SettingsRowColor(label: "Text Color", selection: global.textColor, showLetter: true) { global.textColor = $0 }
        }
    }
}

// MARK: - Note Settings Content

struct NoteSettingsContent: View {

    @ObservedObject var model: NoteModel
    let dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings for \(model.name)")
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsRowFontSize(
                value: model.fontSize,
                decrease: { model.fontSizeOverride = max(model.fontSize - 1, 9) },
                increase: { model.fontSizeOverride = min(model.fontSize + 1, 32) }
            )

            SettingsRowOpacity(value: Binding(
                get: { model.opacity },
                set: { model.opacityOverride = $0 }
            ))

            SettingsRowColor(label: "Note Color", selection: model.tintColor) {
                model.tintColorOverride = $0 == .clear ? nil : $0
            }

            SettingsRowColor(label: "Text Color", selection: model.textColor, showLetter: true) {
                model.textColorOverride = $0 == .clear ? nil : $0
            }

            Button("Clear Note", role: .destructive) {
                model.clearAll()
                dismiss()
            }
        }
    }
}

// MARK: - Shared Setting Rows

struct SettingsRowFontSize: View {
    let value: Double
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack {
            Text("Font Size")
            Spacer()
            Button(action: decrease) {
                Image(systemName: "minus").frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)

            Text("\(Int(value))")
                .monospacedDigit()
                .frame(width: 28, alignment: .center)

            Button(action: increase) {
                Image(systemName: "plus").frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct SettingsRowOpacity: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("Opacity")
            Spacer()
            Slider(value: $value, in: 0.15...1.0)
                .frame(minWidth: 80, maxWidth: 120)
            Text("\(Int(value * 100))%")
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }
}

struct SettingsRowColor: View {
    let label: String
    let selection: NoteTint
    var showLetter: Bool = false
    let onSelect: (NoteTint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
            HStack(spacing: 6) {
                ForEach(NoteTint.allCases) { tint in
                    Button(action: { onSelect(tint) }) {
                        ZStack {
                            if tint == .clear {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                                    .frame(width: 20, height: 20)
                                if showLetter {
                                    Text("A").font(.system(size: 9, weight: .bold)).foregroundStyle(.primary)
                                }
                            } else {
                                Circle()
                                    .fill(tint.color.opacity(0.7))
                                    .frame(width: 20, height: 20)
                                if showLetter {
                                    Text("A").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                }
                            }

                            if selection == tint {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 2)
                                    .frame(width: 26, height: 26)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(tint.label)
                }
            }
        }
    }
}
