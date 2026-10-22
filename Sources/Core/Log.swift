import Foundation
import os

/// Minimal, thread-safe file logger. Secrets are never passed to this API.
/// The log deliberately contains paths and diagnostics only.
enum AppLog {
    private static let logger = Logger(subsystem: "com.miragelyu.rarx", category: "core")
    private static let queue = DispatchQueue(label: "com.miragelyu.rarx.log", qos: .utility)
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var logFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["RARX_LOG_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("RARx", isDirectory: true)
            .appendingPathComponent("RARx.log", isDirectory: false)
    }

    static var logDirectoryURL: URL {
        logFileURL.deletingLastPathComponent()
    }

    static func info(_ message: String) {
        write("INFO", message)
        logger.info("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        write("WARN", message)
        logger.warning("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        write("ERROR", message)
        logger.error("\(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        guard ProcessInfo.processInfo.environment["RARX_DEBUG"] == "1" else { return }
        write("DEBUG", message)
        logger.debug("\(message, privacy: .public)")
    }

    private static func write(_ level: String, _ message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] [\(level)] \(message)\n"
        queue.async {
            do {
                try prepareDirectory()
                try rotateIfNeeded()
                let url = logFileURL
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                logger.error("Unable to write log: \(error.localizedDescription, privacy: .public)")
            }
        }
        if ProcessInfo.processInfo.environment["RARX_DEBUG"] == "1" {
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    private static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
    }

    private static func rotateIfNeeded() throws {
        let url = logFileURL
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber,
            size.int64Value > 2 * 1024 * 1024
        else { return }

        let archive = url.deletingLastPathComponent().appendingPathComponent("RARx.log.1")
        try? FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: url, to: archive)
    }

    static func flush() {
        queue.sync {}
    }

    /// Keep only useful error lines from unrar and bound them for dialogs/logs.
    static func condensedDiagnostics(_ text: String, limit: Int = 1600) -> String {
        let lines = text
            .replacingOccurrences(of: "\u{8}", with: "")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let ignoredPrefixes = [
                    "UNRAR ", "Archive:", "Details:", "Extracting from", "All OK",
                    "Extracting  ", "Creating    ", "Attributes", "-----------",
                    "Total errors:", "  OK "
                ]
                return !ignoredPrefixes.contains(where: { line.hasPrefix($0) })
            }
        var result = lines.joined(separator: "\n")
        if result.count > limit {
            result = String(result.suffix(limit))
        }
        return result
    }
}
