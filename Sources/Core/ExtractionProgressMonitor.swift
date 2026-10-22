import Foundation

/// File-system based progress. unrar buffers its terminal output when stdout is
/// a pipe, so relying on percentage escape sequences can leave a progress UI at
/// 0% until completion. Polling the hidden staging directory is a reliable
/// cross-version signal for both one huge file and many small files.
final class ExtractionProgressMonitor: @unchecked Sendable {
    private let stage: URL
    private let totalBytes: Int64
    private let totalFiles: Int
    private let onProgress: (ExtractionProgress) -> Void
    private let queue = DispatchQueue(label: "com.miragelyu.rarx.progress", qos: .utility)
    private let lock = NSLock()

    private var timer: DispatchSourceTimer?
    private var currentFile: String?
    private var lastFraction: Double = 0
    private var stopped = false

    init(stage: URL, listing: ArchiveListing, onProgress: @escaping (ExtractionProgress) -> Void) {
        self.stage = stage
        self.totalBytes = max(0, listing.totalUncompressedSize)
        self.totalFiles = listing.fileCount
        self.onProgress = onProgress
    }

    func start() {
        lock.lock()
        guard timer == nil, !stopped else {
            lock.unlock()
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.08, repeating: .milliseconds(350), leeway: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        lock.unlock()
        timer.resume()
    }

    func updateCurrentFile(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        lock.lock()
        currentFile = path
        lock.unlock()
    }

    func stop() {
        lock.lock()
        stopped = true
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
    }

    func complete() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        lastFraction = 1
        let file = currentFile
        let timer = self.timer
        self.timer = nil
        lock.unlock()
        timer?.cancel()
        onProgress(ExtractionProgress(
            fractionCompleted: 1,
            currentFilePath: file,
            completedFiles: totalFiles,
            totalFiles: totalFiles
        ))
    }

    private func tick() {
        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        let preferredFile = currentFile
        let previous = lastFraction
        lock.unlock()

        var bytes: Int64 = 0
        var files = 0
        var largestPath: String?
        var largestSize: Int64 = -1
        let base = stage.path.hasSuffix("/") ? stage.path : stage.path + "/"

        if let enumerator = FileManager.default.enumerator(
            at: stage,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                let size = Int64(values?.fileSize ?? 0)
                files += 1
                if size > 0 {
                    let (sum, overflow) = bytes.addingReportingOverflow(size)
                    bytes = overflow ? Int64.max : sum
                }
                if size > largestSize, url.path.hasPrefix(base) {
                    largestSize = size
                    largestPath = String(url.path.dropFirst(base.count))
                }
            }
        }

        let fraction: Double
        if totalBytes > 0 {
            fraction = min(0.995, Double(bytes) / Double(totalBytes))
        } else if totalFiles > 0 {
            fraction = min(0.995, Double(files) / Double(totalFiles))
        } else {
            fraction = 0
        }

        lock.lock()
        if stopped {
            lock.unlock()
            return
        }
        let displayFile = preferredFile ?? largestPath
        let adjusted = max(previous, fraction)
        lastFraction = adjusted
        lock.unlock()

        onProgress(ExtractionProgress(
            fractionCompleted: adjusted,
            currentFilePath: displayFile,
            completedFiles: min(totalFiles, files),
            totalFiles: totalFiles
        ))
    }
}
