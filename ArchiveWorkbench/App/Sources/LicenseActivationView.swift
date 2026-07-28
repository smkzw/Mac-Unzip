import SwiftUI

struct LicenseActivationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""
    @State private var errorMessage: String?
    @State private var isActivated = false

    let requestedFeature: ProFeature?

    var body: some View {
        VStack(spacing: 20) {
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
            }

            VStack(spacing: 4) {
                Text("终身授权 · 一次购买 · 免费更新")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Link("购买 Pro →", destination: URL(string: "https://smkzw.github.io/Mac-Unzip/store/")!)
                    .font(.caption)
            }
        }
        .padding(32)
        .frame(width: 460)
    }

    private func activate() {
        guard !licenseKey.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if LicenseManager.shared.activateLicense(key: licenseKey) {
            isActivated = true
            dismiss()
        } else {
            errorMessage = "无效许可证，请检查密钥格式或重新购买。"
        }
    }
}
