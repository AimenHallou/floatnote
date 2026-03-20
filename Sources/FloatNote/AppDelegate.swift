import AppKit
import SwiftUI
import Combine

// MARK: - Notification Names

extension Notification.Name {
    static let floatNoteOpenSettings   = Notification.Name("floatnote.openSettings")
    static let floatNoteFocusLine      = Notification.Name("floatnote.focusLine")
    static let floatNoteLineFocused    = Notification.Name("floatnote.lineFocused")
    static let floatNoteSelectAllLines = Notification.Name("floatnote.selectAllLines")
}

// MARK: - FloatingPanel

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var panel: FloatingPanel!
    private let store = NoteStore()
    private var statusItem: NSStatusItem?
    private let persistence = PersistenceManager.shared
    private var opacityCancellables = Set<AnyCancellable>()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupMainMenu()
        store.load()
        createWindow()
        setupStatusItem()
        observeOpacity()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persistence.saveWindowFrame(panel.frame)
    }

    // MARK: - Window

    private func createWindow() {
        let defaultFrame = NSRect(x: 100, y: 100, width: 280, height: 220)
        let frame = persistence.loadWindowFrame() ?? defaultFrame

        panel = FloatingPanel(
            contentRect: frame,
            styleMask: [.resizable, .nonactivatingPanel, .utilityWindow],
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
        panel.minSize = NSSize(width: 200, height: 80)
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.alphaValue = store.activeNote?.opacity ?? 0.85

        let contentView = ContentView().environmentObject(store)
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView

        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 12
        hostingView.layer?.masksToBounds = true

        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeOpacity() {
        let global = GlobalSettings.shared

        // When active note or its override changes, or global opacity changes, update panel
        store.$activeNoteId
            .compactMap { [weak self] _ in self?.store.activeNote }
            .map { $0.$opacityOverride }
            .switchToLatest()
            .combineLatest(global.$opacity)
            .sink { [weak self] override_, globalVal in
                self?.panel.alphaValue = override_ ?? globalVal
            }
            .store(in: &opacityCancellables)

        // Also react when switching tabs immediately
        store.$activeNoteId
            .sink { [weak self] _ in
                guard let self, let note = self.store.activeNote else { return }
                self.panel.alphaValue = note.opacity
            }
            .store(in: &opacityCancellables)
    }

    // MARK: - Toggle

    private func toggleWindow() {
        if panel.isVisible {
            persistence.saveWindowFrame(panel.frame)
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Main Menu

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit FloatNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")

        let biggerItem = NSMenuItem(title: "Increase Font Size", action: #selector(increaseFontSize), keyEquivalent: "=")
        biggerItem.keyEquivalentModifierMask = .command
        biggerItem.target = self
        viewMenu.addItem(biggerItem)

        let biggerAlt = NSMenuItem(title: "Increase Font Size", action: #selector(increaseFontSize), keyEquivalent: "+")
        biggerAlt.keyEquivalentModifierMask = [.command, .shift]
        biggerAlt.target = self
        biggerAlt.isAlternate = true
        viewMenu.addItem(biggerAlt)

        let smallerItem = NSMenuItem(title: "Decrease Font Size", action: #selector(decreaseFontSize), keyEquivalent: "-")
        smallerItem.keyEquivalentModifierMask = .command
        smallerItem.target = self
        viewMenu.addItem(smallerItem)

        let resetItem = NSMenuItem(title: "Reset Font Size", action: #selector(resetFontSize), keyEquivalent: "0")
        resetItem.keyEquivalentModifierMask = .command
        resetItem.target = self
        viewMenu.addItem(resetItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func increaseFontSize() {
        guard let note = store.activeNote else { return }
        let current = note.fontSize
        if current < 32 { note.fontSizeOverride = current + 1 }
    }

    @objc private func decreaseFontSize() {
        guard let note = store.activeNote else { return }
        let current = note.fontSize
        if current > 9 { note.fontSizeOverride = current - 1 }
    }

    @objc private func resetFontSize() {
        store.activeNote?.fontSizeOverride = nil
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "FloatNote")
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Show / Hide", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let newNoteItem = NSMenuItem(title: "New Tab", action: #selector(newTabFromMenu), keyEquivalent: "n")
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit FloatNote", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func toggleFromMenu() { toggleWindow() }

    @objc private func newTabFromMenu() {
        store.addNote()
        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettingsFromMenu() {
        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        NotificationCenter.default.post(name: .floatNoteOpenSettings, object: nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard notification.object as? FloatingPanel === panel else { return }
        persistence.saveWindowFrame(panel.frame)
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? FloatingPanel === panel else { return }
        persistence.saveWindowFrame(panel.frame)
    }
}
