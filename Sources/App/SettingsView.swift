import SwiftUI
import AppKit

@MainActor
final class SettingsModel: ObservableObject {
    @Published var showProgressDuringExtraction: Bool {
        didSet { AppSettings.showProgressDuringExtraction = showProgressDuringExtraction }
    }
    @Published var playCompletionSound: Bool {
        didSet { AppSettings.playCompletionSound = playCompletionSound }
    }
    @Published private(set) var isDefault = false
    @Published private(set) var currentHandlerName = L("Checking…")
    @Published private(set) var isApplying = false
    @Published private(set) var statusMessage: String?

    let version = AppSettings.appVersion

    init() {
        showProgressDuringExtraction = AppSettings.showProgressDuringExtraction
        playCompletionSound = AppSettings.playCompletionSound
        refreshHandler()
    }

    func refreshHandler() {
        isDefault = DefaultHandlerManager.isDefault()
        currentHandlerName = DefaultHandlerManager.currentHandlerName()
    }

    func applyDefaultHandler() {
        guard !isApplying else { return }
        isApplying = true
        statusMessage = nil
        AppLog.info("User requested default RAR handler registration")
        let success = DefaultHandlerManager.setAsDefault()
        isApplying = false
        isDefault = success
        currentHandlerName = DefaultHandlerManager.currentHandlerName()
        statusMessage = success
            ? L("RARx is now the default handler. Finder will extract .rar files silently.")
            : L("macOS did not confirm the change. Try again later.")
    }

    func openLogs() {
        UserPrompts.openLogs()
    }

    func openLicenses() {
        openBundledText(named: "THIRD_PARTY_NOTICES")
    }

    func openAppLicense() {
        openBundledText(named: "LICENSE")
    }

    private func openBundledText(named name: String) {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "txt"),
            DefaultHandlerManager.appBundle.url(forResource: name, withExtension: "txt")
        ].compactMap { $0 }
        if let url = candidates.first {
            NSWorkspace.shared.open(url)
        } else {
            UserPrompts.showNotice(title: L("Could not find the license file"), message: L("Reinstall RARx."))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            defaultHandlerCard
            behaviorSection
            privacyNote
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        .frame(width: 600, height: 530)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refreshHandler() }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 86, height: 86)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text("RARx")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(L("Double-click a RAR archive in Finder to extract it."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(L("Version %@ · macOS 13+", model.version))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private var defaultHandlerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.isDefault ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: model.isDefault ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(model.isDefault ? Color.green : Color.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.isDefault ? L("RARx is the default RAR handler") : L("RARx is not the default RAR handler"))
                    .font(.system(size: 14, weight: .semibold))
                Text(model.isDefault
                     ? L("Finder extracts .rar files silently without opening a main window.")
                     : L("Current default: %@", model.currentHandlerName))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = model.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(model.isDefault ? .green : .orange)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Button(model.isDefault ? L("Re-register") : L("Set as Default")) {
                model.applyDefaultHandler()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isApplying)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Behavior"))
                .font(.headline)

            VStack(spacing: 0) {
                settingRow(
                    icon: "rectangle.bottomthird.inset.filled",
                    title: L("Show extraction progress panel"),
                    subtitle: L("Floating progress and cancel after one second. Off by default.")
                ) {
                    Toggle("", isOn: $model.showProgressDuringExtraction)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Divider().padding(.leading, 42)
                settingRow(
                    icon: "speaker.wave.2",
                    title: L("Play a sound when extraction finishes"),
                    subtitle: L("Played in the background without opening a window.")
                ) {
                    Toggle("", isOn: $model.playCompletionSound)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L("Extraction runs entirely on this Mac. Passwords are passed to the engine through a protected process pipe and are never written to command-line arguments, logs, or the network. Existing files are kept and conflicting items are renamed."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(L("Open Logs")) { model.openLogs() }
                .buttonStyle(.link)
            Button(L("RARx License")) { model.openAppLicense() }
                .buttonStyle(.link)
            Button(L("Third-Party Notices")) { model.openLicenses() }
                .buttonStyle(.link)
            Spacer()
            Text("UnRAR 7.13 · © Alexander Roshal")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func settingRow<Accessory: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            accessory()
        }
        .padding(.vertical, 10)
    }
}
