import Foundation

/// User-facing failures. Raw UnRAR diagnostics are kept separately so the log
/// still contains actionable detail even when the friendly message is localized.
enum RARxError: LocalizedError {
    case engineMissing(String)
    case archiveMissing(String)
    case notARARArchive(String)
    case passwordRequired
    case incorrectPassword
    case passwordCancelled
    case archiveEmpty
    case invalidArchive(String)
    case missingVolume(String)
    case unrarFailed(code: Int32, detail: String)
    case destinationUnavailable(String)
    case destinationNotWritable(String)
    case insufficientSpace(needed: Int64, available: Int64)
    case unsafeArchive(String)
    case commitFailed(detail: String, stage: URL?, rollbackSucceeded: Bool)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .engineMissing:
            return L("RAR extraction engine unavailable")
        case .archiveMissing:
            return L("Archive not found")
        case .notARARArchive:
            return L("Not a valid RAR archive")
        case .passwordRequired:
            return L("Password required")
        case .incorrectPassword:
            return L("Incorrect password")
        case .passwordCancelled:
            return L("Password entry canceled")
        case .archiveEmpty:
            return L("Archive is empty")
        case .invalidArchive:
            return L("Archive is damaged or unsupported")
        case .missingVolume:
            return L("Missing volume")
        case .unrarFailed:
            return L("Extraction failed")
        case .destinationUnavailable:
            return L("Destination folder unavailable")
        case .destinationNotWritable:
            return L("Cannot write to destination folder")
        case .insufficientSpace:
            return L("Not enough disk space")
        case .unsafeArchive:
            return L("Archive contains an unsafe path")
        case .commitFailed:
            return L("Could not complete the file write")
        case .cancelled:
            return L("Extraction canceled")
        }
    }

    var failureReason: String? {
        switch self {
        case .engineMissing(let path):
            return L("The bundled UnRAR engine is not executable: %@", path)
        case .archiveMissing(let path):
            return L("File does not exist: %@", path)
        case .notARARArchive(let detail):
            return detail.isEmpty ? L("No RAR signature was found.") : detail
        case .passwordRequired:
            return L("This archive is password-protected.")
        case .incorrectPassword:
            return L("Enter the archive password again.")
        case .passwordCancelled:
            return nil
        case .archiveEmpty:
            return L("The archive contains no extractable items.")
        case .invalidArchive(let detail):
            return detail.isEmpty ? L("The archive is damaged or uses an unsupported format.") : detail
        case .missingVolume(let detail):
            return detail.isEmpty ? L("Make sure all volumes are in the same folder.") : detail
        case .unrarFailed(_, let detail):
            return detail
        case .destinationUnavailable(let detail):
            return detail
        case .destinationNotWritable(let path):
            return L("Cannot write to %@", path)
        case .insufficientSpace(let needed, let available):
            return L(
                "Estimated size: %@. Available: %@.",
                ByteCountFormatter.string(fromByteCount: needed, countStyle: .file),
                ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            )
        case .unsafeArchive(let detail):
            return detail
        case .commitFailed(let detail, let stage, _):
            if let stage {
                return detail + "\n" + L("Incomplete staging files were kept at: %@", stage.path)
            }
            return detail
        case .cancelled:
            return nil
        }
    }

    var isCancellation: Bool {
        switch self {
        case .cancelled, .passwordCancelled:
            return true
        default:
            return false
        }
    }
}

/// A low-level command failure with enough context for the diagnostic log.
struct CommandFailure: Error {
    let status: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        [stderr, stdout]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }
}

func byteString(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func humanDescription(for status: Int32) -> String {
    switch status {
    case 0: return L("Success")
    case 1: return L("Warning")
    case 2: return L("Fatal error")
    case 3: return L("Checksum error")
    case 4: return L("Archive is locked")
    case 5: return L("Write error")
    case 6: return L("Could not open file")
    case 7: return L("Command-line error")
    case 8: return L("Out of memory")
    case 9: return L("Could not create file")
    case 10: return L("No files")
    case 11: return L("Incorrect password")
    case 12: return L("File open failed")
    default: return L("Unknown error (%d)", status)
    }
}
