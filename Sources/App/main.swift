import AppKit
import Darwin

signal(SIGPIPE, SIG_IGN)

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--set-default") {
    let success = DefaultHandlerManager.setAsDefault()
    print(success ? "RARx is now the default RAR handler." : "RARx could not be confirmed as the default RAR handler.")
    exit(success ? 0 : 1)
}
if arguments.contains("--handler-status") {
    let name = DefaultHandlerManager.currentHandlerName()
    let isDefault = DefaultHandlerManager.isDefault()
    print("default=\(isDefault ? "RARx" : name)")
    print("bundle=\(DefaultHandlerManager.bundleIdentifier)")
    for type in DefaultHandlerManager.allRelevantContentTypes {
        print("\(type)=\(DefaultHandlerManager.currentHandlerBundleIdentifier(for: type) ?? "none")")
    }
    exit(0)
}
if arguments.contains("--verify-default") {
    exit(DefaultHandlerManager.isDefault() ? 0 : 1)
}
if arguments.contains("--version") {
    print(AppSettings.appVersion)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
