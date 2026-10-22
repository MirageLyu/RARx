import AppKit
import CoreServices
import UniformTypeIdentifiers

/// LaunchServices integration. The app declares the de-facto RAR UTI and this
/// helper both checks and sets the user's default handler. The installer calls
/// `--set-default` once; the settings window exposes the same action.
enum DefaultHandlerManager {
    static let fallbackBundleIdentifier = "com.miragelyu.rarx"
    static let rarUTI = "com.rarlab.rar-archive"

    static var appBundle: Bundle {
        if Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil {
            return Bundle.main
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidate = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if candidate.pathExtension == "app", let bundle = Bundle(url: candidate) {
            return bundle
        }
        return Bundle.main
    }

    static var bundleIdentifier: String {
        appBundle.bundleIdentifier ?? fallbackBundleIdentifier
    }

    static var appURL: URL {
        appBundle.bundleURL.standardizedFileURL
    }

    static var rarType: UTType? {
        UTType(filenameExtension: "rar")
    }

    static var allRelevantContentTypes: [String] {
        var values: [String] = [rarUTI]
        if let identifier = rarType?.identifier, !identifier.isEmpty {
            values.append(identifier)
        }
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }

    static func currentHandlerBundleIdentifier(for contentType: String) -> String? {
        guard let unmanaged = LSCopyDefaultRoleHandlerForContentType(
            contentType as CFString,
            LSRolesMask.all
        ) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }

    static func currentHandlerURL() -> URL? {
        if let type = rarType, let url = NSWorkspace.shared.urlForApplication(toOpen: type) {
            return url.standardizedFileURL
        }
        if let bundleID = allRelevantContentTypes.compactMap({ currentHandlerBundleIdentifier(for: $0) }).first {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        return nil
    }

    static func currentHandlerName() -> String {
        guard let url = currentHandlerURL() else { return "未设置" }
        if isAppURL(url) { return "RARx" }
        if let bundle = Bundle(url: url) {
            return (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }

    static func isDefault() -> Bool {
        if let url = currentHandlerURL(), isAppURL(url) {
            return true
        }
        return allRelevantContentTypes.contains { contentType in
            currentHandlerBundleIdentifier(for: contentType) == bundleIdentifier
        }
    }

    /// Synchronous LaunchServices write. This is a one-shot user action and is
    /// intentionally verified after a short LaunchServices settling delay.
    @discardableResult
    static func setAsDefault() -> Bool {
        var errors: [String] = []
        for contentType in allRelevantContentTypes {
            let status = LSSetDefaultRoleHandlerForContentType(
                contentType as CFString,
                LSRolesMask.all,
                bundleIdentifier as CFString
            )
            if status != noErr {
                errors.append("\(contentType): OSStatus \(status)")
            }
        }
        if !errors.isEmpty {
            AppLog.warning("Setting default handler reported: \(errors.joined(separator: ", "))")
        }
        Thread.sleep(forTimeInterval: 0.25)
        let result = isDefault()
        AppLog.info("Set default RAR handler to \(bundleIdentifier): \(result ? "success" : "not confirmed")")
        return result
    }

    static func isAppURL(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL
        if candidate.path == appURL.path { return true }
        if let bundle = Bundle(url: candidate), bundle.bundleIdentifier == bundleIdentifier {
            return true
        }
        return false
    }
}
