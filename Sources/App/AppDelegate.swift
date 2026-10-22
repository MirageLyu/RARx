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
                    title: L("Cannot Open"),
                    message: L("RARx only handles readable .rar archives.")
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
        appMenu.addItem(withTitle: L("About RARx"), action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: L("Settings…"), action: #selector(showSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        let defaultItem = appMenu.addItem(
            withTitle: L("Set as Default RAR Handler"),
            action: #selector(setDefaultAction),
            keyEquivalent: ""
        )
        defaultItem.target = self
        appMenu.addItem(withTitle: L("Open Logs"), action: #selector(openLogsAction), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        let hideItem = appMenu.addItem(
            withTitle: L("Hide RARx"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(
            withTitle: L("Quit RARx"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L("Edit"))
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L("Window"))
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: L("Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: L("Bring All to Front"),
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.setActivationPolicy(.regular)
        let creditsText = [
            L("Double-click a RAR archive to extract it silently into the same folder."),
            L("The original RARx code is released under the MIT License."),
            "https://github.com/MirageLyu/RARx",
            L("UnRAR 7.13 is Copyright © Alexander Roshal. RAR is a trademark of RARLAB.")
        ].joined(separator: "\n\n")
        let credits = NSAttributedString(
            string: creditsText,
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
            title: success
                ? L("RARx Is Now the Default RAR Handler")
                : L("The Change Was Not Confirmed"),
            message: success
                ? L("Finder will extract .rar files silently with RARx.")
                : L("macOS did not confirm the change. Try again later.")
        )
    }

    @objc private func openLogsAction() {
        UserPrompts.openLogs()
    }
}
