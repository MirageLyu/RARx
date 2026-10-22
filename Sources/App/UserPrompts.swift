import AppKit

@MainActor
enum UserPrompts {
    static func askPassword(archiveName: String, previousAttemptFailed: Bool) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("Password Required")
        if previousAttemptFailed {
            alert.informativeText = L("Incorrect password. Try again.") + "\n\n" + L("Archive: %@", archiveName)
        } else {
            alert.informativeText = L("“%@” is encrypted. Click the password field to enter its password. Extraction continues in the background without opening a main window.", archiveName)
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 50))
        let label = NSTextField(labelWithString: L("Password"))
        label.frame = NSRect(x: 0, y: 32, width: 340, height: 16)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        container.addSubview(label)

        let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        secureField.placeholderString = L("Archive password")
        secureField.font = NSFont.systemFont(ofSize: 13)
        container.addSubview(secureField)
        alert.accessoryView = container

        alert.addButton(withTitle: L("Extract"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = secureField
        alert.window.defaultButtonCell = alert.buttons.first?.cell as? NSButtonCell

        let response = present(alert)
        let password = secureField.stringValue
        secureField.stringValue = ""
        guard response == .alertFirstButtonReturn, !password.isEmpty else {
            return nil
        }
        return password
    }

    static func showError(archiveName: String?, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if let archiveName {
            alert.messageText = L("Could not extract “%@”", archiveName)
        } else {
            alert.messageText = L("RARx encountered a problem")
        }

        var message: String
        if let rarx = error as? RARxError {
            message = rarx.errorDescription ?? L("Extraction failed")
            if let reason = rarx.failureReason, !reason.isEmpty {
                message += "\n\n" + reason
            }
        } else if error is CancellationError {
            return
        } else {
            message = error.localizedDescription
        }
        alert.informativeText = clean(message, limit: 1800)
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Open Logs"))
        alert.icon = NSApp.applicationIconImage

        let response = present(alert)
        if response == .alertSecondButtonReturn {
            openLogs()
        }
    }

    static func showWarning(archiveName: String, destination: URL, warnings: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L("Extracted “%@” with warnings", archiveName)
        var message = L("Files were extracted to “%@”.", destination.lastPathComponent) + "\n\n"
        let shown = warnings.prefix(6).map { "• " + clean($0, limit: 240) }
        message += shown.joined(separator: "\n")
        if warnings.count > shown.count {
            message += "\n• " + L("Not shown: %d", warnings.count - shown.count)
        }
        alert.informativeText = clean(message, limit: 1800)
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Show in Finder"))
        alert.icon = NSApp.applicationIconImage

        let response = present(alert)
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
    }

    static func showNotice(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("OK"))
        alert.icon = NSApp.applicationIconImage
        _ = present(alert)
    }

    static func openLogs() {
        let fm = FileManager.default
        try? fm.createDirectory(at: AppLog.logDirectoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppLog.logDirectoryURL)
    }

    /// A UIElement app must temporarily become a regular app *after* its alert
    /// window exists. Otherwise the alert can be created behind the frontmost
    /// application and the background extraction appears to hang.
    @discardableResult
    private static func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        _ = alert.window
        alert.window.level = .modalPanel
        alert.window.hidesOnDeactivate = false
        alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        centerOnActiveScreen(alert.window)
        alert.window.orderFrontRegardless()
        NSApp.requestUserAttention(.informationalRequest)

        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(0.8)
        while !NSApp.isActive && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            NSApp.activate(ignoringOtherApps: true)
        }
        alert.window.makeKeyAndOrderFront(nil)
        alert.window.orderFrontRegardless()

        AppLog.debug("Prompt window: policy=\(NSApp.activationPolicy().rawValue) active=\(NSApp.isActive) visible=\(alert.window.isVisible)")

        // The modal loop may start on a different Space. Re-assert the prompt and
        // center it on the screen under the pointer once the session is active.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            alert.window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            centerOnActiveScreen(alert.window)
            alert.window.orderFrontRegardless()
            alert.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return alert.runModal()
    }

    private static func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private static func clean(_ value: String, limit: Int) -> String {
        var text = value
            .replacingOccurrences(of: "\u{8}", with: "")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\0", with: "")
        if text.count > limit {
            text = String(text.prefix(limit)) + "…"
        }
        return text
    }
}
