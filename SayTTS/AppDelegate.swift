import AppKit
import SwiftUI

/// Menu bar host: owns the status item and the settings window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSPanel!
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The status item mirrors the server state, so keep it in sync.
        model.onStatusChange = { [weak self] _ in
            self?.updateStatusItemAppearance()
        }

        setUpStatusItem()
        setUpWindow()

        if model.autoStart {
            model.start()
        }

        if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            showWindow(nil)
        }
    }

    /// Menus live in the status bar, so there is no main window and no Dock tile.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Give the listener a moment to drain before the process goes away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRunning else { return .terminateNow }
        Task { [weak self] in
            guard let self else { return }
            await self.model.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "SayTTS"
        )
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItemAppearance()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // Distinguish left from right click so each can do something different.
        if NSApp.currentEvent?.type == .rightMouseUp {
            presentContextMenu()
        } else {
            toggleWindow()
        }
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        let symbol = model.isRunning ? "waveform.circle.fill" : "waveform.circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SayTTS")
        image?.isTemplate = true
        button.image = image
        button.toolTip = model.serverURL.map { "SayTTS — \($0)" } ?? "SayTTS"
    }

    /// Right click: status summary and quit.
    private func presentContextMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let statusEntry = NSMenuItem(title: "Status: \(model.status.title)", action: nil, keyEquivalent: "")
        statusEntry.isEnabled = false
        menu.addItem(statusEntry)

        if let url = model.serverURL {
            let urlItem = NSMenuItem(title: url, action: nil, keyEquivalent: "")
            urlItem.isEnabled = false
            menu.addItem(urlItem)
        }

        if let detail = model.status.detail {
            let detailItem = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            detailItem.isEnabled = false
            menu.addItem(detailItem)
        }

        menu.addItem(.separator())

        let toggleTitle = model.isRunning ? "Stop Server" : "Start Server"
        let toggle = NSMenuItem(
            title: toggleTitle,
            action: #selector(toggleServer),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = !model.status.locksSettings || model.isRunning
        menu.addItem(toggle)

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showWindow),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SayTTS", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Pop the menu up under the status item rather than handing it to the
        // status item, which would take over left clicks too.
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 4), in: button)
    }

    @objc private func toggleServer() {
        model.toggle()
    }

    @objc private func quit() {
        Task { [weak self] in
            guard let self else { return }
            await self.model.shutdown()
            NSApp.terminate(nil)
        }
    }

    // MARK: Settings window

    private func setUpWindow() {
        let hosting = NSHostingController(rootView: SettingsView(model: model))

        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SayTTS"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        // No frame autosave: the panel is not resizable and its size comes from
        // `SettingsView`, so a restored frame would only fight the layout.
    }

    /// Left click: show the window, or hide it if already frontmost.
    private func toggleWindow() {
        if window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showWindow(nil)
        }
    }

    @objc func showWindow(_ sender: Any?) {
        positionWindowUnderStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Anchors the panel under the status item, clamped to the visible screen.
    private func positionWindowUnderStatusItem() {
        guard let button = statusItem.button, let screen = button.window?.screen ?? NSScreen.main else { return }

        let buttonFrame = button.convert(button.bounds, to: nil)
        let windowSize = window.frame.size
        let visible = screen.visibleFrame

        var origin = NSPoint(
            x: buttonFrame.midX - windowSize.width / 2,
            y: visible.maxY - buttonFrame.height - windowSize.height
        )

        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - windowSize.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - windowSize.height - 8)

        window.setFrameOrigin(origin)
    }
}
