import Foundation
import Darwin

struct MergeOutcome {
    let movedFileCount: Int
    let renamedItems: [String]
}

struct MergeFailure: Error {
    let detail: String
    let rollbackSucceeded: Bool
}

/// Moves staged results into the destination without ever overwriting an
/// existing item. Directory conflicts are merged; item conflicts are renamed
/// Finder-style (" 2", " 3", ...). Every move is journaled so a failed commit can
/// be rolled back.
enum FileMerger {
    private enum ItemKind {
        case missing
        case file
        case directory
        case symbolicLink
        case other
    }

    private struct Move {
        let source: URL
        let destination: URL
    }

    private struct CommitContext {
        var moves: [Move] = []
        var renamed: [String] = []
        var movedFileCount = 0
    }

    static func commit(stagedContentsOf stage: URL, to destination: URL) throws -> MergeOutcome {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: stage,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw MergeFailure(
                detail: "无法读取临时解压目录：\(error.localizedDescription)",
                rollbackSucceeded: true
            )
        }

        guard !children.isEmpty else {
            throw MergeFailure(detail: "临时解压目录中没有文件。", rollbackSucceeded: true)
        }

        let fileCount = countFiles(in: stage)
        var context = CommitContext(movedFileCount: fileCount)

        do {
            for child in children {
                try merge(source: child, targetParent: destination, context: &context)
            }
        } catch {
            let rollback = rollback(context.moves)
            let detail = "写入目标文件夹时出错：\(error.localizedDescription)"
            if rollback.error != nil {
                AppLog.error("Commit rollback failed: \(rollback.error!.localizedDescription)")
            }
            throw MergeFailure(
                detail: detail,
                rollbackSucceeded: rollback.error == nil
            )
        }

        if let leftovers = try? FileManager.default.contentsOfDirectory(atPath: stage.path), !leftovers.isEmpty {
            AppLog.debug("Staging directory retained \(leftovers.count) empty directories after merge")
        }
        return MergeOutcome(movedFileCount: context.movedFileCount, renamedItems: context.renamed)
    }

    private static func merge(source: URL, targetParent: URL, context: inout CommitContext) throws {
        let target = targetParent.appendingPathComponent(source.lastPathComponent)
        let sourceKind = kind(of: source)
        let targetKind = kind(of: target)

        if targetKind == .missing {
            try move(source, to: target, context: &context)
            return
        }

        if sourceKind == .directory && targetKind == .directory {
            let children = try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: nil,
                options: []
            )
            for child in children {
                try merge(source: child, targetParent: target, context: &context)
            }
            return
        }

        let replacement = uniqueDestination(for: target)
        context.renamed.append(replacement.lastPathComponent)
        try move(source, to: replacement, context: &context)
    }

    private static func move(_ source: URL, to destination: URL, context: inout CommitContext) throws {
        try FileManager.default.moveItem(at: source, to: destination)
        context.moves.append(Move(source: source, destination: destination))
    }

    private static func rollback(_ moves: [Move]) -> (restored: Int, error: Error?) {
        var restored = 0
        for move in moves.reversed() {
            guard pathExists(move.destination) else { continue }
            do {
                let parent = move.source.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                if !pathExists(move.source) {
                    try FileManager.default.moveItem(at: move.destination, to: move.source)
                    restored += 1
                }
            } catch {
                return (restored, error)
            }
        }
        return (restored, nil)
    }

    private static func uniqueDestination(for target: URL) -> URL {
        let parent = target.deletingLastPathComponent()
        let name = target.lastPathComponent
        let extensionPart = target.pathExtension
        let baseName: String
        if extensionPart.isEmpty {
            baseName = name
        } else {
            baseName = String(name.dropLast(extensionPart.count + 1))
        }

        for index in 2...9999 {
            let candidateName: String
            if extensionPart.isEmpty {
                candidateName = "\(name) \(index)"
            } else {
                candidateName = "\(baseName) \(index).\(extensionPart)"
            }
            let candidate = parent.appendingPathComponent(candidateName)
            if !pathExists(candidate) {
                return candidate
            }
        }

        let fallbackName = extensionPart.isEmpty
            ? "\(name) \(UUID().uuidString.prefix(8))"
            : "\(baseName) \(UUID().uuidString.prefix(8)).\(extensionPart)"
        return parent.appendingPathComponent(fallbackName)
    }

    private static func countFiles(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                count += 1
            } else if values?.isDirectory != true {
                count += 1
            }
        }
        return count
    }

    private static func kind(of url: URL) -> ItemKind {
        var info = Darwin.stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT || errno == ENOTDIR {
                return .missing
            }
            return .other
        }
        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFLNK:
            return .symbolicLink
        case S_IFREG:
            return .file
        default:
            return .other
        }
    }

    private static func pathExists(_ url: URL) -> Bool {
        var info = Darwin.stat()
        return lstat(url.path, &info) == 0
    }
}
