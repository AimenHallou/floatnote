import SwiftUI

// MARK: - Settings View

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: NoteStore
    @ObservedObject private var global = GlobalSettings.shared
    @State private var selectedTab: UUID? // nil = global

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Tab bar ─────────────────────────────────────────────────
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    settingsTabButton(label: "Global", isSelected: selectedTab == nil) {
                        selectedTab = nil
                    }

                    ForEach(store.notes) { note in
                        settingsTabButton(
                            label: note.name,
                            isSelected: selectedTab == note.id,
                            tint: note.tintColor
                        ) {
                            selectedTab = note.id
                            store.activeNoteId = note.id
                        }
                    }
                }
            }

            Divider()

            if selectedTab == nil {
                GlobalSettingsContent(global: global)
            } else if let model = store.notes.first(where: { $0.id == selectedTab }) {
                NoteSettingsContent(model: model, dismiss: dismiss)
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
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            selectedTab = store.activeNoteId
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
