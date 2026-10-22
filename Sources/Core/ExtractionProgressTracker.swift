import Foundation

/// Parses unrar's terminal-style progress output. unrar emits a stream of
/// backspace characters, so the raw stream is inspected rather than a cleaned
/// terminal rendering. Display progress is best-effort; actual success is always
/// determined by the process exit status and file validation.
final class ExtractionProgressTracker {
    private let stagePrefixes: [String]
    private let entriesByPath: [String: ArchiveEntry]
    private let totalBytes: Int64
    private let totalFiles: Int
    private let onProgress: (ExtractionProgress) -> Void
    private let lock = NSLock()

    private var buffer = ""
    private var currentOutputPath: String?
    private var currentEntry: ArchiveEntry?
    private var currentPercent: Double = 0
    private var completedBytes: Int64 = 0
    private var completedFiles = 0
    private var lastOverall: Double = 0
    private var didFinish = false

    init(stage: URL, listing: ArchiveListing, onProgress: @escaping (ExtractionProgress) -> Void) {
        let raw = stage.path
        let canonical = stage.resolvingSymlinksInPath().path
        self.stagePrefixes = Array(Set([raw, canonical]))
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
            .sorted { $0.count > $1.count }
        var map: [String: ArchiveEntry] = [:]
        for entry in listing.entries where entry.kind.contributesToSize {
            map[entry.path] = entry
        }
        self.entriesByPath = map
        self.totalBytes = max(0, listing.totalUncompressedSize)
        self.totalFiles = listing.fileCount
        self.onProgress = onProgress
    }

    func consume(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        buffer.append(text)
        if buffer.count > 128 * 1024 {
            buffer = String(buffer.suffix(96 * 1024))
        }
        processBuffer()
        lock.unlock()
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        didFinish = true
        completedBytes = totalBytes
        completedFiles = totalFiles
        let progress = ExtractionProgress(
            fractionCompleted: 1,
            currentFilePath: currentEntry?.path ?? currentOutputPath.map(displayPath),
            completedFiles: totalFiles,
            totalFiles: totalFiles
        )
        onProgress(progress)
    }

    private func processBuffer() {
        if let markerRange = buffer.range(of: "Extracting  ", options: .backwards) {
            let tail = buffer[markerRange.upperBound...]
            let endIndex = tail.firstIndex(where: { character in
                character == "\u{8}" || character == "\r" || character == "\n"
            }) ?? tail.index(tail.startIndex, offsetBy: min(4096, tail.count))
            let candidate = String(tail[..<endIndex]).trimmingCharacters(in: .whitespaces)
            if !candidate.isEmpty {
                updatePath(candidate)
            }

            let progressSection = String(tail[..<endIndex])
            if let percent = lastPercent(in: progressSection) {
                updatePercent(percent)
            }
        }

        if buffer.contains("All OK") {
            currentPercent = 100
        }
        emitIfChanged()
    }

    private func updatePath(_ outputPath: String) {
        if let previous = currentOutputPath {
            let isContinuation = outputPath.hasPrefix(previous) || previous.hasPrefix(outputPath)
            if isContinuation {
                currentOutputPath = outputPath
                if let entry = resolveEntry(for: outputPath) {
                    currentEntry = entry
                }
                return
            }
            // A new record means the previous file is done, whether or not we
            // observed its final percentage.
            if let entry = currentEntry {
                completedBytes += max(0, entry.uncompressedSize)
            }
            completedFiles += 1
        }

        currentOutputPath = outputPath
        currentEntry = resolveEntry(for: outputPath)
        currentPercent = 0
    }

    private func updatePercent(_ percent: Double) {
        currentPercent = min(100, max(0, percent))
        emitIfChanged()
    }

    private func emitIfChanged() {
        guard !didFinish else { return }
        let overall = overallPercent()
        if abs(overall - lastOverall) < 0.4 && overall < 100 {
            return
        }
        lastOverall = overall
        let progress = ExtractionProgress(
            fractionCompleted: min(1, max(0, overall / 100)),
            currentFilePath: currentEntry?.path ?? currentOutputPath.map(displayPath),
            completedFiles: min(totalFiles, completedFiles),
            totalFiles: totalFiles
        )
        onProgress(progress)
    }

    private func overallPercent() -> Double {
        if totalBytes > 0 {
            var done = Double(completedBytes)
            if let currentEntry {
                done += Double(max(0, currentEntry.uncompressedSize)) * currentPercent / 100
            }
            return min(100, max(lastOverall, done / Double(totalBytes) * 100))
        }
        if totalFiles > 0 {
            let done = Double(completedFiles) + currentPercent / 100
            return min(100, max(lastOverall, done / Double(totalFiles) * 100))
        }
        return currentPercent
    }

    private func resolveEntry(for outputPath: String) -> ArchiveEntry? {
        for prefix in stagePrefixes where outputPath.hasPrefix(prefix) {
            let relative = String(outputPath.dropFirst(prefix.count))
            if let entry = entriesByPath[relative] {
                return entry
            }
        }

        // unrar normally prints exactly stage + entry path. This fallback covers
        // symlink-resolved prefixes and unusual path spellings.
        let normalized = outputPath.replacingOccurrences(of: "\\", with: "/")
        for (path, entry) in entriesByPath {
            let suffix = "/" + path
            if normalized.hasSuffix(suffix) {
                return entry
            }
        }
        return nil
    }

    private func displayPath(_ outputPath: String) -> String {
        for prefix in stagePrefixes where outputPath.hasPrefix(prefix) {
            return String(outputPath.dropFirst(prefix.count))
        }
        return URL(fileURLWithPath: outputPath).lastPathComponent
    }

    private func lastPercent(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,3})%"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.matches(in: text, range: range).last,
              match.numberOfRanges > 1,
              let subrange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[subrange])
    }
}
