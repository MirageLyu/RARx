import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    var onClose: (() -> Void)?

    init() {
        let model = SettingsModel()
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 530),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RARx 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.setContentSize(NSSize(width: 600, height: 530))
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        model.refreshHandler()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
