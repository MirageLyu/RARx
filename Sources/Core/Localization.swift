import Foundation

/// Looks up a user-facing string. English text is used as the source key; the
/// Simplified Chinese translation lives in zh-Hans.lproj/Localizable.strings.
/// If no localization is available, the English key is returned unchanged.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    guard !arguments.isEmpty else { return format }
    return String(format: format, locale: Locale.current, arguments: arguments)
}
