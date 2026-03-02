import SwiftUI
import AppKit
import Carbon.HIToolbox

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var pendingCombo: HotkeyCombo = HotkeyManager.shared.hotkey
    @State private var isRecording: Bool = false
    @State private var recordingDisplay: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("FloatNote Settings")
                .font(.headline)

            Divider()

            // ── Hotkey recorder ───────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("Global Hotkey")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                KeyRecorderField(
                    combo: $pendingCombo,
                    isRecording: $isRecording,
                    recordingDisplay: $recordingDisplay
                )
            }

            Spacer()

            // ── Buttons ───────────────────────────────────────────────────
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    HotkeyManager.shared.updateHotkey(pendingCombo)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 300, height: 180)
    }
}

// MARK: - KeyRecorderField

/// An NSViewRepresentable that captures key combos via a focused NSTextField.
struct KeyRecorderField: NSViewRepresentable {

    @Binding var combo: HotkeyCombo
    @Binding var isRecording: Bool
    @Binding var recordingDisplay: String

    func makeCoordinator() -> Coordinator {
        Coordinator(combo: $combo, isRecording: $isRecording, recordingDisplay: $recordingDisplay)
    }

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.coordinator = context.coordinator
        view.update(combo: combo, isRecording: false)
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.update(combo: combo, isRecording: isRecording)
    }

    // MARK: Coordinator

    final class Coordinator {
        @Binding var combo: HotkeyCombo
        @Binding var isRecording: Bool
        @Binding var recordingDisplay: String

        init(combo: Binding<HotkeyCombo>, isRecording: Binding<Bool>, recordingDisplay: Binding<String>) {
            _combo = combo
            _isRecording = isRecording
            _recordingDisplay = recordingDisplay
        }

        func didCapture(_ combo: HotkeyCombo) {
            self.combo = combo
            self.isRecording = false
            self.recordingDisplay = combo.displayString
        }

        func startRecording() {
            isRecording = true
            recordingDisplay = "Press a key combo…"
        }

        func cancelRecording() {
            isRecording = false
            recordingDisplay = combo.displayString
        }
    }
}

// MARK: - KeyRecorderNSView

final class KeyRecorderNSView: NSView {

    weak var coordinator: KeyRecorderField.Coordinator?
    private let button = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButton() {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(buttonClicked)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func update(combo: HotkeyCombo, isRecording: Bool) {
        if isRecording {
            button.title = "Press a key combo…"
            button.highlight(true)
        } else {
            button.title = combo.displayString
            button.highlight(false)
        }
    }

    @objc private func buttonClicked() {
        coordinator?.startRecording()
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let coordinator, coordinator.isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording.
        if event.keyCode == UInt16(kVK_Escape) {
            coordinator.cancelRecording()
            return
        }

        // Require at least one modifier key (except Shift alone).
        let modifierFlags = event.modifierFlags.intersection([
            .command, .option, .control, .shift
        ])
        let hasCommandOrControl = modifierFlags.contains(.command) || modifierFlags.contains(.control)
        guard hasCommandOrControl else {
            // Flash the button to indicate invalid combo.
            NSSound.beep()
            return
        }

        var cgFlags: CGEventFlags = []
        if modifierFlags.contains(.command) { cgFlags.insert(.maskCommand) }
        if modifierFlags.contains(.shift)   { cgFlags.insert(.maskShift) }
        if modifierFlags.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if modifierFlags.contains(.control) { cgFlags.insert(.maskControl) }

        let combo = HotkeyCombo(keyCode: Int64(event.keyCode), modifiers: cgFlags.rawValue)
        coordinator.didCapture(combo)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        // Let modifier-only changes pass through while recording.
        super.flagsChanged(with: event)
    }
}
