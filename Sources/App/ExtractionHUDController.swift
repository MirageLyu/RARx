import AppKit

/// Optional, non-activating progress panel for long extractions. It is disabled
/// by default so Finder double-click remains completely silent. When enabled it
/// appears after a delay and never steals focus.
@MainActor
final class ExtractionHUDController {
    private var panel: NSPanel?
    private var titleLabel: NSTextField?
    private var detailLabel: NSTextField?
    private var percentLabel: NSTextField?
    private var progressBar: NSProgressIndicator?
    private var cancelButton: NSButton?
    private var showWorkItem: DispatchWorkItem?
    private var cancelHandler: (() -> Void)?
    private var archiveName = ""
    private var currentProgress: ExtractionProgress?
    private var currentFile: String?
    private var phaseText = "准备解压…"
    private var wantsVisible = false

    func begin(archiveName: String, cancel: @escaping () -> Void) {
        guard AppSettings.showProgressDuringExtraction else { return }
        self.archiveName = archiveName
        self.cancelHandler = cancel
        self.phaseText = "正在读取压缩包…"
        self.currentProgress = nil
        self.currentFile = nil
        self.wantsVisible = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsVisible else { return }
            self.showPanel()
        }
        showWorkItem?.cancel()
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func update(_ progress: ExtractionProgress) {
        currentProgress = progress
        currentFile = progress.currentFilePath
        refreshContent()
    }

    func setPhase(_ text: String) {
        phaseText = text
        if let detailLabel {
            detailLabel.stringValue = text
        }
    }

    func finish() {
        wantsVisible = false
        showWorkItem?.cancel()
        showWorkItem = nil
        cancelHandler = nil
        currentProgress = nil
        currentFile = nil
        archiveName = ""
        guard let panel else { return }
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        self.titleLabel = nil
        self.detailLabel = nil
        self.percentLabel = nil
        self.progressBar = nil
        self.cancelButton = nil
    }

    private func showPanel() {
        if panel == nil {
            buildPanel()
        }
        guard let panel else { return }
        position(panel)
        refreshContent()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 108),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 380, height: 108))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.13).cgColor
        panel.contentView = effect

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "正在解压")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false

        let percent = NSTextField(labelWithString: "0%")
        percent.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        percent.textColor = .secondaryLabelColor
        percent.alignment = .right
        percent.translatesAutoresizingMaskIntoConstraints = false

        let detail = NSTextField(labelWithString: "准备解压…")
        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.translatesAutoresizingMaskIntoConstraints = false

        let progress = NSProgressIndicator()
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelAction))
        cancel.isBordered = false
        cancel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        cancel.contentTintColor = .controlAccentColor
        cancel.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(icon)
        content.addSubview(title)
        content.addSubview(percent)
        content.addSubview(detail)
        content.addSubview(progress)
        content.addSubview(cancel)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -14),

            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            icon.topAnchor.constraint(equalTo: content.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),

            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 11),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 1),
            title.trailingAnchor.constraint(lessThanOrEqualTo: percent.leadingAnchor, constant: -10),

            percent.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            percent.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            percent.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -10),

            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            cancel.centerYAnchor.constraint(equalTo: detail.centerYAnchor),

            progress.leadingAnchor.constraint(equalTo: icon.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            progress.heightAnchor.constraint(equalToConstant: 4)
        ])

        self.panel = panel
        self.titleLabel = title
        self.detailLabel = detail
        self.percentLabel = percent
        self.progressBar = progress
        self.cancelButton = cancel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width - 22,
            y: visible.minY + 22
        ))
    }

    private func refreshContent() {
        guard panel != nil else { return }
        titleLabel?.stringValue = "正在解压 \(truncate(archiveName, limit: 46))"
        if let progress = currentProgress {
            let percent = Int((progress.fractionCompleted * 100).rounded())
            percentLabel?.stringValue = "\(min(100, max(0, percent)))%"
            progressBar?.doubleValue = progress.fractionCompleted
            if let file = currentFile, !file.isEmpty {
                detailLabel?.stringValue = truncate(file, limit: 62)
            } else {
                detailLabel?.stringValue = phaseText
            }
        } else {
            percentLabel?.stringValue = ""
            progressBar?.doubleValue = 0
            detailLabel?.stringValue = phaseText
        }
    }

    @objc private func cancelAction() {
        guard let cancelHandler else { return }
        cancelButton?.isEnabled = false
        cancelButton?.title = "正在取消…"
        detailLabel?.stringValue = "正在取消…"
        cancelHandler()
    }

    private func truncate(_ value: String, limit: Int) -> String {
        if value.count <= limit { return value }
        return String(value.prefix(max(1, limit - 1))) + "…"
    }
}
