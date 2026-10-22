import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var extractionController: AutoExtractionController?
    private var settingsController: SettingsWindowController?
    private var pendingURLs: [URL] = []
    private var hasReceivedOpenEvent = false
    private var manualLaunchWork: DispatchWorkItem?
    private var idleWork: DispatchWorkItem?
    private var settingsShownAt: Date?
    private var settingsShownByLaunchCheck = false
    private var startupEngineError: Error?
    private var terminatingAfterCancel = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        buildMainMenu()
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.info("RARx \(AppSettings.appVersion) launched; pid=\(ProcessInfo.processInfo.processIdentifier)")

        do {
            let engine = try UnrarEngine.bundled()
            let controller = AutoExtractionController(engine: engine)
            controller.onIdle = { [weak self] in
                self?.scheduleIdleTermination()
            }
            extractionController = controller
            if let version = engine.version() {
                AppLog.info("Engine: \(version)")
            }
        } catch {
            startupEngineError = error
            AppLog.error("Bundled engine unavailable: \(error.localizedDescription)")
        }

        if !pendingURLs.isEmpty {
            let urls = pendingURLs
            pendingURLs.removeAll()
            receive(urls: urls)
        } else {
            scheduleManualLaunchCheck()
        }

        if let startupEngineError {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                UserPrompts.showError(archiveName: nil, error: startupEngineError)
                self?.terminateSoon()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppLog.info("Received open event for \(urls.count) URL(s)")
        receive(urls: urls)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        AppLog.info("Received legacy open event for \(filenames.count) file(s)")
        receive(urls: filenames.map { URL(fileURLWithPath: $0) })
        NSApp.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showSettings()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminatingAfterCancel {
            return .terminateNow
        }
        guard extractionController?.hasWork == true else {
            extractionController?.shutdown()
            return .terminateNow
        }

        terminatingAfterCancel = true
        extractionController?.shutdown()
        Task { @MainActor [weak self] in
            for _ in 0..<60 {
                if self?.extractionController?.hasWork != true { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        idleWork?.cancel()
        manualLaunchWork?.cancel()
        AppLog.flush()
    }

    // MARK: - Open event routing

    private func receive(urls: [URL]) {
        hasReceivedOpenEvent = true
        manualLaunchWork?.cancel()
        if startupEngineError != nil { return }

        guard let extractionController else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        extractionController.enqueue(urls)

        if extractionController.hasWork == false {
            AppLog.warning("Open event contained no supported, readable .rar files")
            if settingsController == nil {
                UserPrompts.showNotice(
                    title: "无法打开",
                    message: "RARx 只处理存在且可读取的 .rar 压缩包。"
                )
                scheduleIdleTermination()
            }
            return
        }

        // A delayed open event can arrive just after the manual-launch settings
        // window was shown. Close that window so the Finder interaction remains
        // completely silent.
        if settingsShownByLaunchCheck,
           let shownAt = settingsShownAt,
           Date().timeIntervalSince(shownAt) < 2.0,
           let settingsController {
            settingsShownByLaunchCheck = false
            settingsController.close()
            self.settingsController = nil
            setAccessoryPolicy()
        }
    }

    private func scheduleManualLaunchCheck() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.hasReceivedOpenEvent else { return }
            guard self.startupEngineError == nil else { return }
            guard self.extractionController?.hasWork != true else { return }
            self.settingsShownByLaunchCheck = true
            self.settingsShownAt = Date()
            self.showSettings()
        }
        manualLaunchWork?.cancel()
        manualLaunchWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    // MARK: - Settings

    private func showSettings() {
        manualLaunchWork?.cancel()
        NSApp.setActivationPolicy(.regular)
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onClose = { [weak self] in
                self?.settingsWindowClosed()
            }
            settingsController = controller
        }
        settingsShownAt = settingsShownAt ?? Date()
        settingsController?.show()
    }

    private func settingsWindowClosed() {
        settingsController = nil
        settingsShownByLaunchCheck = false
        settingsShownAt = nil
        if extractionController?.hasWork == true {
            setAccessoryPolicy()
        } else {
            scheduleIdleTermination()
        }
    }

    private func setAccessoryPolicy() {
        NSApp.setActivationPolicy(.accessory)
    }

    private func scheduleIdleTermination() {
        guard settingsController == nil else { return }
        guard extractionController?.hasWork != true else { return }
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.settingsController == nil, self.extractionController?.hasWork != true else { return }
            NSApp.terminate(nil)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func terminateSoon() {
        idleWork?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于 RARx", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "设置…", action: #selector(showSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        let defaultItem = appMenu.addItem(
            withTitle: "设为默认 RAR 打开方式",
            action: #selector(setDefaultAction),
            keyEquivalent: ""
        )
        defaultItem.target = self
        appMenu.addItem(withTitle: "打开日志", action: #selector(openLogsAction), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(
            withTitle: "隐藏 RARx",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(
            withTitle: "退出 RARx",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "前置全部窗口",
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.setActivationPolicy(.regular)
        let credits = NSAttributedString(
            string: "双击 RAR，静默解压到当前文件夹。\n\nRARx 原创代码以 MIT 许可发布。\nhttps://github.com/MirageLyu/RARx\n\nUnRAR 7.13 版权归 Alexander Roshal 所有。RAR 是 RARLAB 的商标。",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "RARx",
            .applicationVersion: AppSettings.appVersion,
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsAction() {
        settingsShownByLaunchCheck = false
        showSettings()
    }

    @objc private func setDefaultAction() {
        let success = DefaultHandlerManager.setAsDefault()
        settingsController?.model.refreshHandler()
        UserPrompts.showNotice(
            title: success ? "已设为默认 RAR 打开方式" : "设置未生效",
            message: success
                ? "Finder 双击 .rar 后将由 RARx 静默解压。"
                : "macOS 没有确认这次更改。请稍后在设置中重试。"
        )
    }

    @objc private func openLogsAction() {
        UserPrompts.openLogs()
    }
}
