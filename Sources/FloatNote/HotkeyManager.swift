import AppKit
import Carbon.HIToolbox

/// Manages a system-wide CGEventTap for the show/hide toggle hotkey.
/// Requires Accessibility permission (AXIsProcessTrusted).
final class HotkeyManager {

    static let shared = HotkeyManager()

    // Called on the main thread when the hotkey fires.
    var onToggle: (() -> Void)?

    // Current hotkey combo — loaded from UserDefaults.
    private(set) var hotkey: HotkeyCombo {
        didSet { PersistenceManager.shared.saveHotkey(hotkey) }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var accessibilityPollTimer: Timer?

    // We keep a single retained Unmanaged reference alive for the life of
    // the singleton, so we never double-retain or leak.
    private var retainedSelf: Unmanaged<HotkeyManager>?

    private init() {
        hotkey = PersistenceManager.shared.loadHotkey() ?? HotkeyCombo.defaultCombo
    }

    // MARK: - Public API

    func startMonitoring() {
        if AXIsProcessTrusted() {
            registerEventTap()
        } else {
            requestAccessibilityPermission()
            startAccessibilityPoll()
        }
    }

    func updateHotkey(_ combo: HotkeyCombo) {
        hotkey = combo
        removeEventTap()
        if AXIsProcessTrusted() {
            registerEventTap()
        }
    }

    // MARK: - Accessibility Permission

    private func requestAccessibilityPermission() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "FloatNote needs Accessibility access"
            alert.informativeText = """
                To use the global hotkey (⌘⇧Space by default), FloatNote needs \
                Accessibility permission.

                Open System Settings → Privacy & Security → Accessibility \
                and enable FloatNote.
                """
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            alert.alertStyle = .informational

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func startAccessibilityPoll() {
        // Schedule on the main run loop so it fires reliably.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.accessibilityPollTimer = Timer.scheduledTimer(
                withTimeInterval: 2.0,
                repeats: true
            ) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self.accessibilityPollTimer = nil
                    self.registerEventTap()
                }
            }
        }
    }

    // MARK: - Event Tap

    private func registerEventTap() {
        removeEventTap()

        // Retain self once for the duration of this tap's lifetime.
        // We balance the retain in removeEventTap().
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        let selfPtr = retained.toOpaque()

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, userInfo) -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap else {
            // Creation failed; release our extra retain.
            retained.release()
            retainedSelf = nil
            startAccessibilityPoll()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil

        // Balance the retain we took in registerEventTap().
        retainedSelf?.release()
        retainedSelf = nil
    }

    // MARK: - Event Handling

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {

        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if hotkey.matches(keyCode: keyCode, flags: flags) {
            DispatchQueue.main.async { [weak self] in
                self?.onToggle?()
            }
            // Consume the event.
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}

// MARK: - HotkeyCombo

struct HotkeyCombo: Codable, Equatable {

    let keyCode: Int64
    let modifiers: UInt64   // CGEventFlags raw value

    /// Default: ⌘ + Shift + Space
    static let defaultCombo = HotkeyCombo(
        keyCode: Int64(kVK_Space),
        modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue
    )

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let relevantFlags = flags.intersection([
            .maskCommand, .maskShift, .maskAlternate, .maskControl
        ])
        let expectedFlags = CGEventFlags(rawValue: modifiers).intersection([
            .maskCommand, .maskShift, .maskAlternate, .maskControl
        ])
        return keyCode == self.keyCode && relevantFlags == expectedFlags
    }

    /// Human-readable description, e.g. "⌘⇧Space"
    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_Space:     keyName = "Space"
        case kVK_Return:    keyName = "Return"
        case kVK_Tab:       keyName = "Tab"
        case kVK_Delete:    keyName = "Delete"
        case kVK_Escape:    keyName = "Esc"
        default:
            // Try the ANSI letter map first, fall back to raw code.
            if let letter = virtualKeyToChar(Int(keyCode)) {
                keyName = letter
            } else {
                keyName = "Key(\(keyCode))"
            }
        }

        parts.append(keyName)
        return parts.joined()
    }
}

// Minimal virtual-key-to-char mapping for display purposes.
// Returns nil if the key code doesn't map to a known letter.
private func virtualKeyToChar(_ vk: Int) -> String? {
    // Carbon ANSI key codes (not contiguous A–Z; this is the physical layout map).
    let map: [Int: String] = [
        0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",  6: "Z",  7: "X",
        8: "C",  9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
       16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
       24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
       31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J",
       40: "K", 45: "N", 46: "M", 47: ".", 48: "Tab"
    ]
    return map[vk]
}
