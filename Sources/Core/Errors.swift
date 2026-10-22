import Foundation

/// User-facing failures. The Chinese copy is intentionally friendly; raw unrar
/// diagnostics are kept separately so the log still contains actionable detail.
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
            return "RAR 解压引擎缺失"
        case .archiveMissing:
            return "找不到压缩包"
        case .notARARArchive:
            return "这不是有效的 RAR 压缩包"
        case .passwordRequired:
            return "压缩包需要密码"
        case .incorrectPassword:
            return "压缩包密码不正确"
        case .passwordCancelled:
            return "已取消输入密码"
        case .archiveEmpty:
            return "压缩包是空的"
        case .invalidArchive:
            return "压缩包已损坏或格式不受支持"
        case .missingVolume:
            return "缺少分卷文件"
        case .unrarFailed:
            return "解压失败"
        case .destinationUnavailable:
            return "无法使用目标文件夹"
        case .destinationNotWritable:
            return "没有权限写入目标文件夹"
        case .insufficientSpace:
            return "磁盘空间不足"
        case .unsafeArchive:
            return "压缩包包含不安全的文件路径"
        case .commitFailed:
            return "无法完成文件写入"
        case .cancelled:
            return "已取消解压"
        }
    }

    var failureReason: String? {
        switch self {
        case .engineMissing(let path):
            return "内置 unrar 引擎不可执行：\(path)"
        case .archiveMissing(let path):
            return "文件不存在：\(path)"
        case .notARARArchive(let detail):
            return detail.isEmpty ? "没有找到 RAR 文件头。" : detail
        case .passwordRequired:
            return "该压缩包使用密码加密。"
        case .incorrectPassword:
            return "请重新输入压缩包密码。"
        case .passwordCancelled:
            return nil
        case .archiveEmpty:
            return "压缩包内没有可解压的项目。"
        case .invalidArchive(let detail):
            return detail
        case .missingVolume(let detail):
            return detail
        case .unrarFailed(_, let detail):
            return detail
        case .destinationUnavailable(let detail):
            return detail
        case .destinationNotWritable(let path):
            return "无法写入 \(path)"
        case .insufficientSpace(let needed, let available):
            return "预计需要 \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file))，当前可用 \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))。"
        case .unsafeArchive(let detail):
            return detail
        case .commitFailed(let detail, let stage, _):
            if let stage {
                return "\(detail)\n未完成的临时文件保留在：\(stage.path)"
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
    case 0: return "成功"
    case 1: return "警告"
    case 2: return "严重错误"
    case 3: return "校验和错误"
    case 4: return "压缩包被锁定"
    case 5: return "写入错误"
    case 6: return "打开文件失败"
    case 7: return "命令行错误"
    case 8: return "内存不足"
    case 9: return "创建文件失败"
    case 10: return "没有文件"
    case 11: return "密码错误"
    case 12: return "文件打开失败"
    default: return "未知错误（\(status)）"
    }
}
