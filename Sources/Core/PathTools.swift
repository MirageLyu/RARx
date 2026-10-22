import Foundation
import Darwin

enum PathTools {
    /// realpath(3) resolves APFS firmlinks such as /var -> /private/var, which
    /// Foundation's resolvingSymlinksInPath() intentionally leaves alone.
    static func canonical(_ path: String) -> String {
        path.withCString { pointer in
            guard let resolved = realpath(pointer, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    static func isDescendant(_ candidate: String, of directory: String) -> Bool {
        let canonicalCandidate = canonical(candidate)
        let canonicalDirectory = canonical(directory)
        if canonicalCandidate == canonicalDirectory { return true }
        return canonicalCandidate.hasPrefix(canonicalDirectory.hasSuffix("/") ? canonicalDirectory : canonicalDirectory + "/")
    }
}
