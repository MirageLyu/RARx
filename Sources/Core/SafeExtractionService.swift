import Foundation
import Darwin

/// Performs the high-level safe extraction transaction:
/// inspect → disk check → hidden staging directory → sandboxed unrar →
/// symlink/hardlink validation → non-destructive merge → cleanup.
final class SafeExtractionService: @unchecked Sendable {
    private let engine: UnrarEngine

    init(engine: UnrarEngine) {
        self.engine = engine
    }

    func extract(
        archive: URL,
        listing: ArchiveListing,
        password: String?,
        destination: URL,
        onProgress: @escaping (ExtractionProgress) -> Void = { _ in }
    ) async throws -> ExtractionResult {
        let started = Date()
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RARxError.destinationUnavailable(destination.path)
        }

        try checkDiskSpace(for: listing, destination: destination)
        cleanStaleStages(in: destination)

        let token = UUID().uuidString
        let stage = destination.appendingPathComponent(".rarx-\(token).tmp", isDirectory: true)
        let ownerLock = destination.appendingPathComponent(".rarx-\(token).lock", isDirectory: false)
        do {
            try fm.createDirectory(
                at: stage,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try Data("\(getpid())\n".utf8).write(to: ownerLock, options: .atomic)
        } catch {
            try? fm.removeItem(at: stage)
            AppLog.error("Unable to create staging area: \(error.localizedDescription)")
            throw RARxError.destinationNotWritable(destination.path + "（\(error.localizedDescription)）")
        }

        var stageURL = stage
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try? stageURL.setResourceValues(hiddenValues)

        var preserveStage = false
        defer {
            if !preserveStage {
                try? fm.removeItem(at: stage)
            }
            try? fm.removeItem(at: ownerLock)
        }

        onProgress(ExtractionProgress(fractionCompleted: 0, currentFilePath: listing.entries.first(where: { $0.kind == .file })?.path, completedFiles: 0, totalFiles: listing.fileCount))
        AppLog.info("Extraction started: archive=\(archive.path) destination=\(destination.path) total=\(byteString(listing.totalUncompressedSize)) files=\(listing.fileCount)")

        try Task.checkCancellation()
        let raw = try await engine.extract(
            archive: archive,
            listing: listing,
            password: password,
            stage: stage
        ) { progress in
            onProgress(progress)
        }

        try Task.checkCancellation()
        let validation = validateStagedTree(stage)
        var warnings = raw.warnings
        warnings.append(contentsOf: validation.warnings)
        warnings = deduplicated(warnings)

        if !validation.removedLinks.isEmpty {
            AppLog.warning("Removed \(validation.removedLinks.count) unsafe staged link(s)")
        }

        let children = (try? fm.contentsOfDirectory(atPath: stage.path)) ?? []
        guard !children.isEmpty else {
            throw RARxError.archiveEmpty
        }

        try Task.checkCancellation()
        let outcome: MergeOutcome
        do {
            outcome = try FileMerger.commit(stagedContentsOf: stage, to: destination)
        } catch let failure as MergeFailure {
            if !failure.rollbackSucceeded {
                preserveStage = true
                AppLog.error("Commit failed and rollback was incomplete; staging kept at \(stage.path)")
                throw RARxError.commitFailed(
                    detail: failure.detail,
                    stage: stage,
                    rollbackSucceeded: false
                )
            }
            throw RARxError.commitFailed(detail: failure.detail, stage: nil, rollbackSucceeded: true)
        } catch {
            throw RARxError.commitFailed(
                detail: error.localizedDescription,
                stage: nil,
                rollbackSucceeded: true
            )
        }

        do {
            try fm.removeItem(at: stage)
        } catch {
            AppLog.warning("Unable to remove staging directory \(stage.path): \(error.localizedDescription)")
        }
        let duration = Date().timeIntervalSince(started)
        AppLog.info("Extraction completed: archive=\(archive.path) files=\(outcome.movedFileCount) renamed=\(outcome.renamedItems.count) warnings=\(warnings.count) duration=\(String(format: "%.2f", duration))s")

        return ExtractionResult(
            archive: archive,
            destination: destination,
            extractedFileCount: outcome.movedFileCount,
            warnings: warnings,
            renamedItems: outcome.renamedItems,
            duration: duration
        )
    }

    /// A crash can leave a hidden staging directory behind. Locks record the
    /// owning PID so a later run can safely remove only abandoned transactions.
    private func cleanStaleStages(in destination: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: destination.path) else { return }
        let prefix = ".rarx-"
        let suffix = ".tmp"

        for name in names where name.hasPrefix(prefix) && name.hasSuffix(suffix) {
            let token = String(name.dropFirst(prefix.count).dropLast(suffix.count))
            guard !token.isEmpty else { continue }
            let stage = destination.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: stage.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            let lock = destination.appendingPathComponent(".rarx-\(token).lock", isDirectory: false)
            if let text = try? String(contentsOf: lock, encoding: .utf8),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if pid == getpid() {
                    // A failed attempt in this process. Safe to remove.
                } else if kill(pid, 0) == 0 || errno == EPERM {
                    AppLog.debug("Skipping active staging directory owned by pid \(pid): \(stage.path)")
                    continue
                }
            } else {
                // Older stages may predate lock files. Only remove clearly old
                // leftovers to avoid racing an extraction from another copy.
                let modified = (try? stage.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                if Date().timeIntervalSince(modified) < 3600 {
                    continue
                }
            }

            do {
                try fm.removeItem(at: stage)
                try? fm.removeItem(at: lock)
                AppLog.info("Removed abandoned staging directory \(stage.path)")
            } catch {
                AppLog.warning("Unable to remove abandoned staging directory \(stage.path): \(error.localizedDescription)")
            }
        }
    }

    private func checkDiskSpace(for listing: ArchiveListing, destination: URL) throws {
        guard listing.totalUncompressedSize > 0 else { return }
        let values = try? destination.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        let important = values?.volumeAvailableCapacityForImportantUsage as? Int64
        let regular = values?.volumeAvailableCapacity as? Int64
        let available = important ?? regular ?? 0
        guard available > 0 else { return }

        let total = listing.totalUncompressedSize
        let margin = max(Int64(10 * 1024 * 1024), total / 50)
        let (needed, overflow) = total.addingReportingOverflow(margin)
        let required = overflow ? Int64.max : needed
        if required > available {
            throw RARxError.insufficientSpace(needed: required, available: available)
        }
    }

    private struct ValidationResult {
        var warnings: [String] = []
        var removedLinks: [String] = []
    }

    private func validateStagedTree(_ stage: URL) -> ValidationResult {
        var result = ValidationResult()
        guard let enumerator = FileManager.default.enumerator(
            at: stage,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .linkCountKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return result
        }

        for case let url as URL in enumerator {
            var info = Darwin.stat()
            guard lstat(url.path, &info) == 0 else { continue }
            let mode = info.st_mode & S_IFMT

            if mode == S_IFLNK {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
                let resolved: String
                if target.hasPrefix("/") {
                    resolved = URL(fileURLWithPath: target).standardizedFileURL.path
                } else {
                    let canonicalParent = PathTools.canonical(url.deletingLastPathComponent().path)
                    resolved = URL(fileURLWithPath: canonicalParent)
                        .appendingPathComponent(target)
                        .standardizedFileURL.path
                }
                if !PathTools.isDescendant(resolved, of: stage.path) {
                    try? FileManager.default.removeItem(at: url)
                    let relative = relativePath(url, stage: stage)
                    result.removedLinks.append(relative)
                    result.warnings.append("已移除指向压缩包外部的符号链接：\(relative)")
                    AppLog.warning("Removed escaping symlink \(relative) -> \(target)")
                }
                continue
            }

            if mode == S_IFREG && info.st_nlink > 1 {
                try? FileManager.default.removeItem(at: url)
                let relative = relativePath(url, stage: stage)
                result.removedLinks.append(relative)
                result.warnings.append("已跳过硬链接项目：\(relative)")
                AppLog.warning("Removed hard-linked staged file \(relative) with \(info.st_nlink) links")
            }
        }
        return result
    }

    private func relativePath(_ url: URL, stage: URL) -> String {
        let base = stage.path.hasSuffix("/") ? stage.path : stage.path + "/"
        if url.path.hasPrefix(base) {
            return String(url.path.dropFirst(base.count))
        }
        return url.lastPathComponent
    }

    private func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}
