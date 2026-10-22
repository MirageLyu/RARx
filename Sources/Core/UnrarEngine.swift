import Foundation
import Darwin

enum EngineLocator {
    static func locate() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("engine/unrar"))
        }
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        if let executableDirectory {
            candidates.append(executableDirectory.appendingPathComponent("../Resources/engine/unrar").standardizedFileURL)
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

final class UnrarEngine: @unchecked Sendable {
    let executableURL: URL
    private let sandboxExecURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    static func bundled() throws -> UnrarEngine {
        guard let url = EngineLocator.locate() else {
            throw RARxError.engineMissing("Contents/Resources/engine/unrar")
        }
        return UnrarEngine(executableURL: url)
    }

    func version() -> String? {
        let runner = ProcessRunner(executableURL: executableURL, arguments: [])
        do {
            let output = try runner.run()
            let firstLine = (output.stderr + "\n" + output.stdout)
                .split(separator: "\n")
                .first(where: { $0.contains("UNRAR") })
            return firstLine.map(String.init)
        } catch {
            return nil
        }
    }

    // MARK: - Inspection

    func inspect(archive: URL, password: String?) async throws -> ArchiveListing {
        try validateArchiveFile(archive)

        let arguments: [String]
        if password == nil {
            arguments = ["lt", "-c-", "-cfg-", "-p-", archive.path]
        } else {
            arguments = ["lt", "-c-", "-cfg-", "-p", archive.path]
        }

        let runner = ProcessRunner(
            executableURL: executableURL,
            arguments: arguments,
            stdin: password.map { Data(($0 + "\n").utf8) }
        )
        let output = try await runner.runAsync()

        if output.wasCancelled {
            throw CancellationError()
        }

        if output.status == 11 || output.combined.localizedCaseInsensitiveContains("Incorrect password") {
            throw password == nil ? RARxError.passwordRequired : RARxError.incorrectPassword
        }

        if output.combined.localizedCaseInsensitiveContains("is not RAR archive")
            || output.combined.localizedCaseInsensitiveContains("is not rar archive") {
            throw RARxError.notARARArchive(AppLog.condensedDiagnostics(output.combined))
        }

        if output.status != 0 && output.status != 10 {
            throw mapListingFailure(output)
        }

        let listing = try Self.parseListing(output.stdout, status: output.status)
        if listing.encryptedHeaders && password == nil {
            throw RARxError.passwordRequired
        }
        if output.status == 10 && listing.entries.isEmpty {
            return listing
        }
        if listing.entries.isEmpty && !listing.encryptedHeaders {
            throw RARxError.archiveEmpty
        }
        return listing
    }

    private func mapListingFailure(_ output: EngineRunOutput) -> RARxError {
        let lower = output.combined.lowercased()
        if lower.contains("is not rar archive") || lower.contains("not a rar archive") {
            return .notARARArchive(AppLog.condensedDiagnostics(output.combined))
        }
        if lower.contains("unexpected end") || lower.contains("corrupt") || lower.contains("checksum") {
            return .invalidArchive(AppLog.condensedDiagnostics(output.combined))
        }
        if lower.contains("cannot open") || lower.contains("cannot find") {
            return .archiveMissing(output.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return .unrarFailed(code: output.status, detail: AppLog.condensedDiagnostics(output.combined))
    }

    private func validateArchiveFile(_ archive: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw RARxError.archiveMissing(archive.path)
        }
        guard FileManager.default.isReadableFile(atPath: archive.path) else {
            throw RARxError.archiveMissing(archive.path)
        }
        guard archive.pathExtension.lowercased() == "rar" else {
            throw RARxError.notARARArchive("文件扩展名不是 .rar")
        }
    }

    static func parseListing(_ text: String, status: Int32) throws -> ArchiveListing {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var format = "RAR"
        var encryptedHeaders = false
        var entries: [ArchiveEntry] = []
        var block: [String: String]?

        func finishBlock() {
            guard let current = block, let name = current["Name"], !name.isEmpty else {
                block = nil
                return
            }
            let type = current["Type"] ?? "File"
            let kind: ArchiveEntryKind
            switch type.lowercased() {
            case "file":
                kind = .file
            case "directory":
                kind = .directory
            case "unix symbolic link", "symbolic link":
                kind = .symbolicLink
            case "hard link":
                kind = .hardLink
            case "service":
                kind = .service
            default:
                kind = .other
            }

            let size = parseNumber(current["Size"]) ?? 0
            let packed = parseNumber(current["Packed size"]) ?? 0
            let modified = parseDate(current["mtime"])
            let flags = current["Flags"] ?? ""
            let encrypted = type.lowercased() != "directory" && flags.lowercased().contains("encrypted")
            let crc = current["CRC32"] ?? current["CRC32 MAC"] ?? current["Pack-CRC32"]
            let attributes = current["Attributes"] ?? ""

            entries.append(
                ArchiveEntry(
                    path: name,
                    kind: kind,
                    uncompressedSize: size,
                    compressedSize: packed,
                    modified: modified,
                    isEncrypted: encrypted,
                    crc: crc,
                    attributes: attributes,
                    flags: flags
                )
            )
            block = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Details: ") {
                format = String(trimmed.dropFirst("Details: ".count))
                if format.lowercased().contains("encrypted headers") {
                    encryptedHeaders = true
                }
                continue
            }
            if trimmed.hasPrefix("Name: ") {
                finishBlock()
                block = ["Name": String(trimmed.dropFirst("Name: ".count))]
                continue
            }
            guard var current = block else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard Self.knownListingKeys.contains(key) else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            current[key] = value
            block = current
        }
        finishBlock()

        if status == 10 {
            encryptedHeaders = format.lowercased().contains("encrypted headers")
        }

        let encryptedEntries = entries.contains { $0.isEncrypted }
        let total = entries
            .filter { $0.kind.contributesToSize }
            .reduce(Int64(0)) { partial, entry in
                let (sum, overflow) = partial.addingReportingOverflow(entry.uncompressedSize)
                return overflow ? Int64.max : sum
            }
        let fileCount = entries.filter { $0.kind == .file || $0.kind == .symbolicLink || $0.kind == .hardLink }.count

        return ArchiveListing(
            entries: entries,
            format: format,
            encryptedHeaders: encryptedHeaders,
            encryptedEntries: encryptedEntries,
            totalUncompressedSize: total,
            fileCount: fileCount
        )
    }

    private static let knownListingKeys: Set<String> = [
        "Name", "Type", "Size", "Packed size", "Ratio", "mtime", "ctime", "atime",
        "Attributes", "CRC32", "CRC32 MAC", "Pack-CRC32", "Host OS", "Compression",
        "Flags", "Redir type", "Target"
    ]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    private static let dateLock = NSLock()

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let prefix = value.split(separator: ",", maxSplits: 1).first.map(String.init) ?? value
        dateLock.lock()
        defer { dateLock.unlock() }
        return dateFormatter.date(from: prefix)
    }

    private static func parseNumber(_ value: String?) -> Int64? {
        guard let value else { return nil }
        let cleaned = value.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Int64(cleaned)
    }

    // MARK: - Extraction

    func extract(
        archive: URL,
        listing: ArchiveListing,
        password: String?,
        stage: URL,
        onProgress: @escaping (ExtractionProgress) -> Void
    ) async throws -> RawExtraction {
        let passwordArgument = password == nil ? "-p-" : "-p"
        let stageArgument = stage.path.hasSuffix("/") ? stage.path : stage.path + "/"
        let unrarArguments = [
            "x", "-y", "-o+", "-c-", "-cfg-", "-ts",
            passwordArgument, archive.path, stageArgument
        ]

        let monitor = ExtractionProgressMonitor(
            stage: stage,
            listing: listing,
            onProgress: onProgress
        )
        let tracker = ExtractionProgressTracker(
            stage: stage,
            listing: listing
        ) { progress in
            monitor.updateCurrentFile(progress.currentFilePath)
        }
        monitor.start()
        defer { monitor.stop() }

        let processURL: URL
        let processArguments: [String]
        if FileManager.default.isExecutableFile(atPath: sandboxExecURL.path) {
            let profile = sandboxProfileText(writableDirectory: stage)
            processURL = sandboxExecURL
            processArguments = ["-p", profile, executableURL.path] + unrarArguments
            AppLog.debug("Extraction sandbox enabled for \(stage.path)")
        } else {
            processURL = executableURL
            processArguments = unrarArguments
            AppLog.warning("sandbox-exec unavailable; continuing with staging-only extraction")
        }

        var environment = [String: String]()
        environment["TMPDIR"] = stage.path

        let runner = ProcessRunner(
            executableURL: processURL,
            arguments: processArguments,
            stdin: password.map { Data(($0 + "\n").utf8) },
            environment: environment,
            currentDirectoryURL: stage
        )

        let output: EngineRunOutput
        do {
            output = try await runner.runAsync(
                onStdout: { data in tracker.consume(data) },
                onStderr: { data in tracker.consume(data) }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RARxError.unrarFailed(code: -1, detail: error.localizedDescription)
        }

        tracker.finish()

        if output.wasCancelled {
            throw CancellationError()
        }

        if output.status == 11 {
            throw password == nil ? RARxError.passwordRequired : RARxError.incorrectPassword
        }

        let detail = AppLog.condensedDiagnostics(output.combined)
        let allOutput = output.combined
        if output.status != 0 {
            AppLog.error("unrar extraction exited \(output.status), output: \(allOutput.replacingOccurrences(of: "\u{8}", with: "").suffix(2400))")
        }
        let fatalWarningMarkers = [
            "unexpected end of archive",
            "crc failed",
            "checksum error",
            "you need to start extraction from a previous volume",
            "cannot find volume",
            "next volume is required",
            "cannot open",
            "permission denied",
            "operation not permitted"
        ]

        if output.status != 0 {
            if output.status == 1 && !fatalWarningMarkers.contains(where: { allOutput.localizedCaseInsensitiveContains($0) }) {
                monitor.complete()
                let warnings = Self.warnings(from: allOutput)
                return RawExtraction(
                    status: output.status,
                    warnings: warnings.isEmpty ? ["解压引擎报告了非致命警告。"] : warnings,
                    skippedLinks: Self.skippedLinks(from: allOutput),
                    detail: detail
                )
            }

            let lower = allOutput.lowercased()
            if lower.contains("not rar archive") {
                throw RARxError.notARARArchive(detail)
            }
            if lower.contains("cannot find volume")
                || lower.contains("you need to start extraction from a previous volume")
                || lower.contains("next volume is required") {
                throw RARxError.missingVolume(detail.isEmpty ? "请确认所有分卷文件都在同一文件夹。" : detail)
            }
            if lower.contains("password") {
                throw password == nil ? RARxError.passwordRequired : RARxError.incorrectPassword
            }
            if output.status == 3 || lower.contains("crc failed") || lower.contains("checksum error") {
                throw RARxError.invalidArchive(detail.isEmpty ? "压缩包校验失败。" : detail)
            }
            if lower.contains("permission denied") || lower.contains("operation not permitted") {
                throw RARxError.destinationNotWritable(stage.path)
            }
            if lower.contains("no space") || lower.contains("disk full") {
                throw RARxError.insufficientSpace(needed: listing.totalUncompressedSize, available: 0)
            }
            throw RARxError.unrarFailed(code: output.status, detail: detail.isEmpty ? humanDescription(for: output.status) : detail)
        }

        monitor.complete()
        let warnings = Self.warnings(from: allOutput)
        return RawExtraction(
            status: output.status,
            warnings: warnings,
            skippedLinks: Self.skippedLinks(from: allOutput),
            detail: detail
        )
    }

    private func sandboxProfileText(writableDirectory: URL) -> String {
        let canonical = PathTools.canonical(writableDirectory.path)
        let escaped = canonical
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (version 1)
        (allow default)
        (deny file-write*)
        (allow file-write* (subpath "\(escaped)"))
        (allow file-write* (literal "/dev/null") (literal "/dev/zero") (literal "/dev/stdout") (literal "/dev/stderr") (literal "/dev/tty"))
        """
    }

    static func skippedLinks(from output: String) -> [String] {
        let pattern = #"Skipping the potentially unsafe (.+?) link"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var results: [String] = []
        for match in regex.matches(in: output, range: range) {
            guard match.numberOfRanges > 1, let subrange = Range(match.range(at: 1), in: output) else { continue }
            let value = output[subrange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, !results.contains(value) {
                results.append(value)
            }
        }
        return results
    }

    static func warnings(from output: String) -> [String] {
        var results: [String] = []
        let links = skippedLinks(from: output)
        for link in links {
            results.append("已跳过不安全的符号链接：\(link)")
        }
        let patterns = [
            #"Cannot set file time for (.+)"#,
            #"Cannot set attribute for (.+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            for match in regex.matches(in: output, range: range) {
                guard match.numberOfRanges > 1, let subrange = Range(match.range(at: 1), in: output) else { continue }
                let item = output[subrange].trimmingCharacters(in: .whitespacesAndNewlines)
                let message = "无法完整恢复文件属性：\(item)"
                if !results.contains(message) { results.append(message) }
            }
        }
        return results
    }
}
