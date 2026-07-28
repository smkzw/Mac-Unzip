import SwiftUI

// MARK: - Error Presentation Model

/// Describes the severity level of an archive error for visual styling.
enum ArchiveErrorSeverity {
    case fatal
    case recoverable
    case warning

    var backgroundColor: Color {
        switch self {
        case .fatal: return .red.opacity(0.12)
        case .recoverable: return .orange.opacity(0.12)
        case .warning: return .yellow.opacity(0.15)
        }
    }

    var iconColor: Color {
        switch self {
        case .fatal: return .red
        case .recoverable: return .orange
        case .warning: return .yellow
        }
    }

    var iconName: String {
        switch self {
        case .fatal: return "xmark.octagon.fill"
        case .recoverable: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }
}

/// Structured error presentations for extraction and open failures.
enum ArchiveErrorPresentation: Equatable {
    case missingVolume(needed: String)
    case wrongPassword
    case unsupportedEncryption
    case corruptedArchive
    case diskFull(required: UInt64)
    case permissionDenied
    case cancelled
    case generic(String)

    var severity: ArchiveErrorSeverity {
        switch self {
        case .missingVolume: return .recoverable
        case .wrongPassword: return .recoverable
        case .unsupportedEncryption: return .fatal
        case .corruptedArchive: return .recoverable
        case .diskFull: return .fatal
        case .permissionDenied: return .recoverable
        case .cancelled: return .warning
        case .generic: return .fatal
        }
    }

    var message: String {
        let localization = AppLocalization()
        switch self {
        case .missingVolume(let needed):
            return localization.format("缺少分卷文件：需要 %@", needed)
        case .wrongPassword:
            return localization.string("密码错误")
        case .unsupportedEncryption:
            return localization.string("不支持的加密方式")
        case .corruptedArchive:
            return localization.string("归档数据损坏")
        case .diskFull(let required):
            let formatted = ByteCountFormatter.string(
                fromByteCount: Int64(clamping: required),
                countStyle: .file
            )
            return localization.format("磁盘空间不足（需要 %@）", formatted)
        case .permissionDenied:
            return localization.string("权限不足，请在 Finder 中检查")
        case .cancelled:
            return localization.string("已取消")
        case .generic(let message):
            return message
        }
    }

    /// The label for the primary recovery action button, if any.
    var recoveryActionLabel: String? {
        let localization = AppLocalization()
        switch self {
        case .missingVolume:
            return localization.string("定位")
        default:
            return nil
        }
    }

    /// Whether this error type auto-dismisses after a short delay.
    var autoDismisses: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// Whether this error shows an inline password retry field.
    var showsPasswordRetry: Bool {
        if case .wrongPassword = self { return true }
        return false
    }
}

// MARK: - Conflict Resolution

/// User's choice when a file conflict is detected during extraction.
enum ExtractionConflictResolution: Equatable, Sendable {
    case replace
    case skip
    case replaceAll
    case skipAll
}

/// State for the per-file conflict dialog shown during extraction.
struct ExtractionConflictInfo: Equatable {
    let filePath: String
    var fileName: String {
        filePath.split(separator: "/").last.map(String.init) ?? filePath
    }
}

// MARK: - Error Banner View

/// An inline banner view for displaying extraction/open errors with recovery actions.
struct ArchiveErrorBanner: View {
    let errorType: ArchiveErrorPresentation
    let onRecoveryAction: (() -> Void)?
    let onDismiss: () -> Void
    /// Password retry state
    @Binding var retryPassword: String
    let passwordAttemptCount: Int
    let onRetryPassword: (String) -> Void
    var onResetLockout: (() -> Void)?

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var severity: ArchiveErrorSeverity { errorType.severity }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: severity.iconName)
                    .foregroundStyle(severity.iconColor)
                    .font(.body)
                    .accessibilityHidden(true)

                Text(effectiveMessage)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if let actionLabel = errorType.recoveryActionLabel {
                    Button(actionLabel) {
                        onRecoveryAction?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("错误恢复操作")
                }

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isVisible = false
                    }
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization().string("关闭错误提示"))
                .accessibilityIdentifier("关闭错误提示")
            }

            // Password retry inline UI
            if errorType.showsPasswordRetry {
                passwordRetrySection
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(severity.backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(severity.iconColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -10)
        .onAppear {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = true
                }
            }
            NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .layoutChanged, userInfo: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("错误横幅")
        .accessibilityLabel(effectiveMessage)
    }

    private var effectiveMessage: String {
        if errorType.showsPasswordRetry && passwordAttemptCount >= 3 {
            return AppLocalization().string("密码错误次数过多")
        }
        return errorType.message
    }

    @ViewBuilder
    private var passwordRetrySection: some View {
        if passwordAttemptCount < 3 {
            HStack(spacing: 8) {
                SecureField(AppLocalization().string("输入密码"), text: $retryPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("密码重试输入")
                    .onSubmit {
                        submitPassword()
                    }

                Button(AppLocalization().string("重试")) {
                    submitPassword()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(retryPassword.isEmpty)
                .accessibilityIdentifier("密码重试按钮")
            }
            .padding(.leading, 28)
        } else {
            Button(AppLocalization().string("重新输入")) {
                onResetLockout?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.leading, 28)
            .accessibilityIdentifier("密码重置按钮")
        }
    }

    private func submitPassword() {
        guard !retryPassword.isEmpty else { return }
        onRetryPassword(retryPassword)
        retryPassword = ""
    }
}

// MARK: - Conflict Dialog View

/// Inline conflict resolution dialog shown when extraction encounters an existing file.
struct ExtractionConflictDialog: View {
    let conflictInfo: ExtractionConflictInfo
    let onResolution: (ExtractionConflictResolution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.gearshape")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .accessibilityHidden(true)

                Text(AppLocalization().format("文件 %@ 已存在。", conflictInfo.fileName))
                    .font(.callout)
                    .fontWeight(.medium)
            }

            HStack(spacing: 8) {
                Button(AppLocalization().string("替换")) {
                    onResolution(.replace)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("冲突替换")

                Button(AppLocalization().string("跳过")) {
                    onResolution(.skip)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("冲突跳过")

                Divider()
                    .frame(height: 16)

                Button(AppLocalization().string("全部替换")) {
                    onResolution(.replaceAll)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("冲突全部替换")

                Button(AppLocalization().string("全部跳过")) {
                    onResolution(.skipAll)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("冲突全部跳过")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("冲突对话框")
        .accessibilityLabel(AppLocalization().format("文件 %@ 已存在。", conflictInfo.fileName))
    }
}
