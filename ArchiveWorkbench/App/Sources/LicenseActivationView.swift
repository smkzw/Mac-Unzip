import SwiftUI

struct LicenseActivationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""
    @State private var errorMessage: String?
    @State private var isActivated = false

    let requestedFeature: ProFeature?

    var body: some View {
        VStack(spacing: 20) {
            if isActivated {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("激活成功")
                    .font(.title2.bold())
                Text("Pro 功能已解锁，请重新点击该功能以继续。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("激活完成按钮")
            } else {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("MacUnzip Pro")
                        .font(.title2.bold())

                    if let feature = requestedFeature {
                        Text(feature.upgradeDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("激活 Pro 版本以使用全部功能")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("MACUNZIP-XXXX-XXXX-XXXX-...", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .onSubmit { activate() }
                        .accessibilityIdentifier("许可证输入")
                        .accessibilityLabel("许可证密钥")

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(width: 380)

                HStack(spacing: 12) {
                    Button("取消") { dismiss() }
                        .keyboardShortcut(.cancelAction)

                    Button("激活") { activate() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty ? "请先输入授权码" : "验证并激活授权")
                        .accessibilityIdentifier("激活按钮")
                }

                VStack(spacing: 4) {
                    Text("终身授权 · 一次购买 · 免费更新")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Link("购买 Pro →", destination: URL(string: "https://smkzw.github.io/Mac-Unzip/store/")!)
                        .font(.caption)
                }
            }
        }
        .padding(32)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pro 激活")
    }

    private func activate() {
        guard !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let localization = AppLocalization()
        if LicenseManager.shared.activateLicense(key: licenseKey) {
            withAnimation { isActivated = true }
            AccessibilityNotification.Announcement(localization.string("激活成功")).post()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { dismiss() }
        } else {
            errorMessage = localization.string("无效许可证，请检查密钥格式或重新购买。")
            AccessibilityNotification.Announcement(localization.string("激活失败，许可证无效")).post()
        }
    }
}
