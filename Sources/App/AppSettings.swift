import Foundation

enum AppSettings {
    private static let showProgressDuringExtractionKey = "showProgressDuringExtraction"
    private static let playCompletionSoundKey = "playCompletionSound"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showProgressDuringExtractionKey: false,
            playCompletionSoundKey: false
        ])
    }

    static var showProgressDuringExtraction: Bool {
        get { UserDefaults.standard.bool(forKey: showProgressDuringExtractionKey) }
        set { UserDefaults.standard.set(newValue, forKey: showProgressDuringExtractionKey) }
    }

    static var playCompletionSound: Bool {
        get { UserDefaults.standard.bool(forKey: playCompletionSoundKey) }
        set { UserDefaults.standard.set(newValue, forKey: playCompletionSoundKey) }
    }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
