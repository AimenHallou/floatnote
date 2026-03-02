import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    // MARK: - Properties

    private var floatingWindow: NSPanel?
    private let persistence = PersistenceManager.shared
    private let hotkeyManager = HotkeyManager.shared

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon — enforced via LSUIElement in Info.plist (Resources/Info.plist).
        // Belt-and-suspenders: also set programmatically.
        NSApp.setActivationPolicy(.accessory)

        setupWindow()
        hotkeyManager.onToggle = { [weak self] in
            self?.toggleWindow()
        }
        hotkeyManager.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist window state one last time.
        if let window = floatingWindow {
            persistence.saveWindowFrame(window.frame)
        }
    }

    // MARK: - Window Setup

    private func setupWindow() {
        let savedFrame = persistence.loadWindowFrame()

        // NSPanel so we can be floating + borderless without losing key events.
        let panel = NSPanel(
            contentRect: savedFrame ?? NSRect(x: 100, y: 100, width: 280, height: 220),
            styleMask: [
                .borderless,
                .resizable,
                .nonactivatingPanel,
                .utilityWindow
            ],
            backing: .buffered,
            defer: false
        )

        panel.title = "FloatNote"
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 180, height: 140)

        // Allow the panel to receive key events even when not the active app.
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true

        // SwiftUI content.
        let contentView = ContentView()
            .environmentObject(NoteModel.shared)
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView

        // Corner radius via layer — applied AFTER setting contentView.
        // The SwiftUI view also clips itself, but masking the hosting view
        // ensures the shadow boundary is correct.
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        panel.delegate = self
        panel.orderFront(nil)

        self.floatingWindow = panel
    }

    // MARK: - Toggle

    func toggleWindow() {
        guard let window = floatingWindow else { return }
        if window.isVisible {
            persistence.saveWindowFrame(window.frame)
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard let window = floatingWindow else { return }
        persistence.saveWindowFrame(window.frame)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = floatingWindow else { return }
        persistence.saveWindowFrame(window.frame)
    }
}
