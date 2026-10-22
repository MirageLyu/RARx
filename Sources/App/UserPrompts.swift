import AppKit

@MainActor
enum UserPrompts {
    static func askPassword(archiveName: String, previousAttemptFailed: Bool) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "需要解压密码"
        if previousAttemptFailed {
            alert.informativeText = "密码不正确，请重新输入。\n\n压缩包：\(archiveName)"
        } else {
            alert.informativeText = "“\(archiveName)”已加密。点按密码框输入密码后，会在后台继续解压，不会打开主窗口。"
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 50))
        let label = NSTextField(labelWithString: "密码")
        label.frame = NSRect(x: 0, y: 32, width: 340, height: 16)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        container.addSubview(label)

        let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        secureField.placeholderString = "压缩包密码"
        secureField.font = NSFont.systemFont(ofSize: 13)
        container.addSubview(secureField)
        alert.accessoryView = container

        alert.addButton(withTitle: "解压")
        alert.addButton(withTitle: "取消")
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
            alert.messageText = "无法解压“\(archiveName)”"
        } else {
            alert.messageText = "RARx 遇到问题"
        }

        var message: String
        if let rarx = error as? RARxError {
            message = rarx.errorDescription ?? "解压失败"
            if let reason = rarx.failureReason, !reason.isEmpty {
                message += "\n\n" + reason
            }
        } else if error is CancellationError {
            return
        } else {
            message = error.localizedDescription
        }
        alert.informativeText = clean(message, limit: 1800)
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "查看日志")
        alert.icon = NSApp.applicationIconImage

        let response = present(alert)
        if response == .alertSecondButtonReturn {
            openLogs()
        }
    }

    static func showWarning(archiveName: String, destination: URL, warnings: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "已解压“\(archiveName)”，但有警告"
        var message = "文件已放在“\(destination.lastPathComponent)”。\n\n"
        let shown = warnings.prefix(6).map { "• " + clean($0, limit: 240) }
        message += shown.joined(separator: "\n")
        if warnings.count > shown.count {
            message += "\n• 另有 \(warnings.count - shown.count) 个项目"
        }
        alert.informativeText = clean(message, limit: 1800)
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "在 Finder 中显示")
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
        alert.addButton(withTitle: "好")
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
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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

        // The modal loop may run on a different active Space. Re-assert the
        // prompt once the modal session has started.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            alert.window.orderFrontRegardless()
            alert.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return alert.runModal()
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
