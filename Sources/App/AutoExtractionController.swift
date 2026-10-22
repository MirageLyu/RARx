import AppKit

/// Handles Finder open events as a background utility: no main window, no
/// confirmation. Each archive is inspected, extracted into a hidden sibling
/// staging directory, validated, merged without overwriting, and the app exits
/// once the queue is empty.
@MainActor
final class AutoExtractionController {
    private let engine: UnrarEngine
    private let service: SafeExtractionService
    private let progressHUD = ExtractionHUDController()

    private var queue: [URL] = []
    private var trackedPaths: Set<String> = []
    private var rootTask: Task<Void, Never>?
    private var serviceTask: Task<ExtractionResult, Error>?
    private var cancelled = false
    private var passwordCache: [String: String] = [:]

    var onIdle: (() -> Void)?
    var hasWork: Bool { rootTask != nil || !queue.isEmpty }

    init(engine: UnrarEngine) {
        self.engine = engine
        self.service = SafeExtractionService(engine: engine)
    }

    func enqueue(_ urls: [URL]) {
        let candidates = urls.filter { url in
            guard url.isFileURL else { return false }
            let ext = url.pathExtension.lowercased()
            guard ext == "rar" else { return false }
            let path = url.standardizedFileURL.path
            return FileManager.default.fileExists(atPath: path)
        }
        var accepted: [URL] = []
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard !trackedPaths.contains(path) else { continue }
            trackedPaths.insert(path)
            accepted.append(url)
        }
        guard !accepted.isEmpty else { return }
        queue.append(contentsOf: accepted)
        AppLog.info("Queued \(accepted.count) archive(s), pending=\(queue.count)")
        startNextIfNeeded()
    }

    func cancelAll() {
        guard hasWork else { return }
        cancelled = true
        for url in queue {
            trackedPaths.remove(url.standardizedFileURL.path)
        }
        queue.removeAll()
        progressHUD.setPhase(L("Canceling…"))
        AppLog.info("User canceled extraction")
        serviceTask?.cancel()
        rootTask?.cancel()
    }

    func shutdown() {
        cancelAll()
        progressHUD.finish()
    }

    private func startNextIfNeeded() {
        guard rootTask == nil else { return }
        guard !queue.isEmpty else {
            onIdle?()
            return
        }

        let url = queue.removeFirst()
        cancelled = false
        rootTask = Task { [weak self] in
            guard let self else { return }
            await self.process(openedURL: url)
            self.progressHUD.finish()
            self.rootTask = nil
            self.trackedPaths.remove(url.standardizedFileURL.path)
            if self.queue.isEmpty {
                self.passwordCache.removeAll()
                self.onIdle?()
            } else {
                self.startNextIfNeeded()
            }
        }
    }

    private func process(openedURL: URL) async {
        let archive: URL
        do {
            archive = try VolumeResolver.firstVolume(for: openedURL)
        } catch {
            showFailure(error, archiveName: openedURL.lastPathComponent)
            return
        }

        if archive.path != openedURL.path {
            AppLog.info("Opened \(openedURL.lastPathComponent); continuing from first volume \(archive.lastPathComponent)")
        }

        let destination = archive.deletingLastPathComponent()
        let archiveName = archive.lastPathComponent

        do {
            let listing = try await inspectWithPassword(archive: archive, archiveName: archiveName)
            try Task.checkCancellation()
            guard !cancelled else { return }

            var password = passwordCache[archive.path]
            if listing.requiresPassword && password == nil {
                guard let entered = UserPrompts.askPassword(
                    archiveName: archiveName,
                    previousAttemptFailed: false
                ) else {
                    AppLog.info("Password prompt canceled by user")
                    return
                }
                password = entered
                passwordCache[archive.path] = entered
            }

            progressHUD.begin(archiveName: archiveName) { [weak self] in
                self?.cancelAll()
            }

            var failedAttempts = 0
            while true {
                try Task.checkCancellation()
                do {
                    let result = try await performExtraction(
                        archive: archive,
                        listing: listing,
                        password: password,
                        destination: destination
                    )
                    progressHUD.finish()
                    if !result.warnings.isEmpty {
                        UserPrompts.showWarning(
                            archiveName: archiveName,
                            destination: result.destination,
                            warnings: result.warnings
                        )
                    }
                    if AppSettings.playCompletionSound {
                        NSSound(named: "Glass")?.play()
                    }
                    AppLog.info("Auto extraction succeeded for \(archive.path): files=\(result.extractedFileCount), renamed=\(result.renamedItems.count), warnings=\(result.warnings.count)")
                    return
                } catch RARxError.incorrectPassword {
                    failedAttempts += 1
                    passwordCache.removeValue(forKey: archive.path)
                    if failedAttempts >= 3 {
                        throw RARxError.incorrectPassword
                    }
                    guard let entered = UserPrompts.askPassword(
                        archiveName: archiveName,
                        previousAttemptFailed: true
                    ) else {
                        AppLog.info("Password retry canceled by user")
                        return
                    }
                    password = entered
                    passwordCache[archive.path] = entered
                }
            }
        } catch {
            if cancelled || error is CancellationError {
                AppLog.info("Extraction canceled for \(archive.path)")
                return
            }
            if let rarx = error as? RARxError, rarx.isCancellation {
                AppLog.info("Extraction canceled for \(archive.path): \(rarx.localizedDescription)")
                return
            }
            showFailure(error, archiveName: archiveName)
        }
    }

    private func inspectWithPassword(archive: URL, archiveName: String) async throws -> ArchiveListing {
        var password = passwordCache[archive.path]
        var failedAttempts = 0

        while true {
            try Task.checkCancellation()
            do {
                let listing = try await engine.inspect(archive: archive, password: password)
                return listing
            } catch RARxError.passwordRequired {
                guard let entered = UserPrompts.askPassword(
                    archiveName: archiveName,
                    previousAttemptFailed: false
                ) else {
                    throw RARxError.passwordCancelled
                }
                password = entered
                passwordCache[archive.path] = entered
            } catch RARxError.incorrectPassword {
                failedAttempts += 1
                passwordCache.removeValue(forKey: archive.path)
                if failedAttempts >= 3 {
                    throw RARxError.incorrectPassword
                }
                guard let entered = UserPrompts.askPassword(
                    archiveName: archiveName,
                    previousAttemptFailed: true
                ) else {
                    throw RARxError.passwordCancelled
                }
                password = entered
                passwordCache[archive.path] = entered
            }
        }
    }

    /// The service is fully synchronous once listing finishes, so run the whole
    /// transaction on a detached task to keep the main thread responsive.
    private func performExtraction(
        archive: URL,
        listing: ArchiveListing,
        password: String?,
        destination: URL
    ) async throws -> ExtractionResult {
        let progressHandler: (ExtractionProgress) -> Void = { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressHUD.update(progress)
            }
        }

        let task = Task.detached(priority: .userInitiated) { [service, archive, listing, password, destination, progressHandler] in
            try await service.extract(
                archive: archive,
                listing: listing,
                password: password,
                destination: destination,
                onProgress: progressHandler
            )
        }
        serviceTask = task
        defer { serviceTask = nil }
        return try await task.value
    }

    private func showFailure(_ error: Error, archiveName: String?) {
        AppLog.error("Extraction failed for \(archiveName ?? "unknown"): \(error.localizedDescription)")
        if let rarx = error as? RARxError, let reason = rarx.failureReason {
            AppLog.error("Failure detail: \(reason.replacingOccurrences(of: "\n", with: " | "))")
        }
        progressHUD.finish()
        UserPrompts.showError(archiveName: archiveName, error: error)
    }
}
