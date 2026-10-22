import Foundation

enum VolumeResolver {
    /// If Finder opened a later part of a split archive, extract from the first
    /// volume instead. This is what users expect when double-clicking part 2.
    static func firstVolume(for url: URL) throws -> URL {
        let name = url.lastPathComponent
        guard let regex = try? NSRegularExpression(
            pattern: #"^(.*)\.part([0-9]+)\.rar$"#,
            options: [.caseInsensitive]
        ) else {
            return url
        }

        let nsName = name as NSString
        let range = NSRange(location: 0, length: nsName.length)
        guard let match = regex.firstMatch(in: name, range: range),
              match.numberOfRanges == 3,
              let baseRange = Range(match.range(at: 1), in: name),
              let numberRange = Range(match.range(at: 2), in: name) else {
            return url
        }

        let base = String(name[baseRange])
        let number = Int(name[numberRange]) ?? 1
        if number == 1 {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []

        var first: (number: Int, url: URL)?
        for sibling in siblings {
            let siblingName = sibling.lastPathComponent
            let nsSibling = siblingName as NSString
            let siblingRange = NSRange(location: 0, length: nsSibling.length)
            guard let siblingMatch = regex.firstMatch(in: siblingName, range: siblingRange),
                  siblingMatch.numberOfRanges == 3,
                  let siblingBaseRange = Range(siblingMatch.range(at: 1), in: siblingName),
                  let siblingNumberRange = Range(siblingMatch.range(at: 2), in: siblingName) else {
                continue
            }
            let siblingBase = String(siblingName[siblingBaseRange])
            guard siblingBase.compare(base, options: .caseInsensitive) == .orderedSame else {
                continue
            }
            let siblingNumber = Int(siblingName[siblingNumberRange]) ?? 0
            if siblingNumber == 1 {
                return sibling
            }
            if first == nil || siblingNumber < first!.number {
                first = (siblingNumber, sibling)
            }
        }

        if let first {
            throw RARxError.missingVolume(
                "找不到 \(base).part1.rar。同目录中最早的分卷是 \(first.url.lastPathComponent)。"
            )
        }
        throw RARxError.missingVolume("找不到 \(base).part1.rar。请确认所有分卷都位于同一文件夹。")
    }
}
