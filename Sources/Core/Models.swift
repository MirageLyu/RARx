import Foundation

enum ArchiveEntryKind: String {
    case file
    case directory
    case symbolicLink
    case hardLink
    case service
    case other

    var isContainer: Bool {
        self == .directory
    }

    var contributesToSize: Bool {
        switch self {
        case .file, .symbolicLink, .hardLink:
            return true
        default:
            return false
        }
    }
}

struct ArchiveEntry {
    let path: String
    let kind: ArchiveEntryKind
    let uncompressedSize: Int64
    let compressedSize: Int64
    let modified: Date?
    let isEncrypted: Bool
    let crc: String?
    let attributes: String
    let flags: String
}

struct ArchiveListing {
    let entries: [ArchiveEntry]
    let format: String
    let encryptedHeaders: Bool
    let encryptedEntries: Bool
    let totalUncompressedSize: Int64
    let fileCount: Int

    var requiresPassword: Bool {
        encryptedHeaders || encryptedEntries
    }

    var isEmpty: Bool {
        entries.allSatisfy { $0.kind == .service }
    }
}

struct ExtractionProgress {
    let fractionCompleted: Double
    let currentFilePath: String?
    let completedFiles: Int
    let totalFiles: Int

    static let zero = ExtractionProgress(fractionCompleted: 0, currentFilePath: nil, completedFiles: 0, totalFiles: 0)
}

struct ExtractionResult {
    let archive: URL
    let destination: URL
    let extractedFileCount: Int
    let warnings: [String]
    let renamedItems: [String]
    let duration: TimeInterval
}

struct EngineRunOutput {
    let status: Int32
    let stdout: String
    let stderr: String
    let wasCancelled: Bool
    let terminationReason: Process.TerminationReason

    var combined: String {
        var pieces: [String] = []
        if !stderr.isEmpty { pieces.append(stderr) }
        if !stdout.isEmpty { pieces.append(stdout) }
        return pieces.joined(separator: "\n")
    }
}

struct RawExtraction {
    let status: Int32
    let warnings: [String]
    let skippedLinks: [String]
    let detail: String
}
