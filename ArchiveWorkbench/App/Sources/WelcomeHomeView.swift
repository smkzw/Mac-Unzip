import SwiftUI

/// Native, quiet welcome surface: drop zone as primary, two clear actions, recent list.
struct WelcomeHomeView: View {
    @Bindable var model: AppModel
    let isDropTargeted: Bool
    let onOpen: () -> Void
    let onCreate: () -> Void

    private var recentURLs: [URL] {
        // Manager already isolates visual-capture / ui-testing from real prefs.
        RecentArchivesManager.shared.recentURLs
    }

    var body: some View {
        ScrollView {
            VStack(spacing: UIConstants.space24) {
                if let errorPresentation = model.activeErrorPresentation {
                    ArchiveErrorBanner(
                        errorType: errorPresentation,
                        onRecoveryAction: nil,
                        onDismiss: { model.dismissError() },
                        retryPassword: $model.passwordRetryText,
                        passwordAttemptCount: model.passwordAttemptCount,
                        onRetryPassword: { password in model.retryWithPassword(password) },
                        onResetLockout: { model.passwordAttemptCount = 0 }
                    )
                    .frame(maxWidth: UIConstants.welcomeContentMaxWidth)
                }

                VStack(spacing: UIConstants.space20) {
                    dropZone
                    actions
                    if !model.statusMessage.isEmpty {
                        Text(model.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("欢迎页状态消息")
                    }
                    recentSection
                }
                .frame(maxWidth: UIConstants.welcomeContentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, UIConstants.space24)
                .padding(.vertical, UIConstants.space32)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dropZone: some View {
        VStack(spacing: UIConstants.space12) {
            Image(systemName: "archivebox")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(UIConstants.accent)
                .accessibilityHidden(true)
            Text("MacUnzip")
                .font(.title2.weight(.semibold))
            Text(AppLocalization().string("打开 ZIP、7z、RAR、TAR、DMG、ISO 压缩包，安全查看其中的文件。\n也可以直接将压缩包文件拖放到此窗口。"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("欢迎页副文案")
            Text(AppLocalization().string("将压缩包拖放到此处"))
                .font(.callout.weight(.medium))
                .foregroundStyle(isDropTargeted ? UIConstants.accent : .secondary)
        }
        .padding(UIConstants.space24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: UIConstants.welcomeDropMinHeight)
        .background {
            RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous)
                .fill(isDropTargeted ? UIConstants.accent.opacity(UIConstants.dropFillOpacity) : Color.primary.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.cornerRadius, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? UIConstants.accent : Color.primary.opacity(0.14),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: isDropTargeted ? [] : [7, 5])
                )
        }
        // Keep child StaticTexts queryable (subtitle assertions / VoiceOver reading).
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization().string("拖放区域"))
        .accessibilityIdentifier("欢迎页拖放区")
    }

    private var actions: some View {
        HStack(spacing: UIConstants.space12) {
            Button("打开压缩包", action: onOpen)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("打开压缩包")
            Button {
                onCreate()
            } label: {
                Label("新建压缩包", systemImage: "plus.rectangle.on.folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help(AppLocalization().string("创建 ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST 压缩包"))
            .accessibilityIdentifier("新建压缩包")
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: UIConstants.space8) {
            HStack {
                Text(AppLocalization().string("最近打开"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !recentURLs.isEmpty {
                    Button(AppLocalization().string("清除")) {
                        RecentArchivesManager.shared.clearRecent()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("清除最近打开")
                }
            }

            if recentURLs.isEmpty {
                Text(AppLocalization().string("暂无最近打开的压缩包"))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, UIConstants.space8)
                    .accessibilityIdentifier("最近打开空状态")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentURLs.enumerated()), id: \.element) { index, url in
                        Button {
                            RecentArchivesManager.shared.noteRecentArchive(url)
                            Task { await model.openArchive(url: url) }
                        } label: {
                            HStack(spacing: UIConstants.space12) {
                                Image(systemName: "doc.zipper")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, UIConstants.space12)
                            .padding(.vertical, UIConstants.space10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(url.path)
                        if index < recentURLs.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: UIConstants.cornerRadiusSmall, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: UIConstants.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(UIConstants.hairline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization().string("最近打开"))
    }
}
