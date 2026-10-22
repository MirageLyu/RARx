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
    @Published private(set) var currentHandlerName = "正在检查…"
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
            ? "已设为默认打开方式。Finder 双击 .rar 会静默解压。"
            : "macOS 没有确认这次更改，请稍后重试。"
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
            UserPrompts.showNotice(title: "找不到许可文件", message: "请重新安装 RARx。")
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
                Text("双击 RAR，直接从 Finder 解压")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("版本 \(model.version)  ·  macOS 13+")
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
                Text(model.isDefault ? "RARx 是默认 RAR 打开方式" : "尚未设为默认 RAR 打开方式")
                    .font(.system(size: 14, weight: .semibold))
                Text(model.isDefault
                     ? "Finder 双击 .rar 会静默解压，不打开主窗口。"
                     : "当前默认：\(model.currentHandlerName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let message = model.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(model.isDefault ? .green : .orange)
                        .padding(.top, 2)
                }
            }
            Spacer()
            Button(model.isDefault ? "重新注册" : "设为默认") {
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
            Text("行为")
                .font(.headline)

            VStack(spacing: 0) {
                settingRow(
                    icon: "rectangle.bottomthird.inset.filled",
                    title: "显示解压进度小窗",
                    subtitle: "解压超过 1 秒时显示悬浮进度和取消按钮；默认关闭。"
                ) {
                    Toggle("", isOn: $model.showProgressDuringExtraction)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                Divider().padding(.leading, 42)
                settingRow(
                    icon: "speaker.wave.2",
                    title: "解压完成后播放提示音",
                    subtitle: "只在后台播放，不会弹出窗口。"
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
            Text("解压全程在本机完成。密码只通过受保护的进程管道传给引擎，不会写入命令行参数、日志或网络。同名文件会保留两者，不覆盖原文件。")
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
            Button("打开日志") { model.openLogs() }
                .buttonStyle(.link)
            Button("RARx 许可") { model.openAppLicense() }
                .buttonStyle(.link)
            Button("第三方许可") { model.openLicenses() }
                .buttonStyle(.link)
            Spacer()
            Text("UnRAR 7.13  ·  © Alexander Roshal")
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
            }
            Spacer()
            accessory()
        }
        .padding(.vertical, 10)
    }
}
