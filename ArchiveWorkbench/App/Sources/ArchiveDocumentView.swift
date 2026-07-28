import AppKit
import ArchiveDomain
import SwiftUI

struct ArchiveDocumentView: View {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Bindable var model: AppModel
    let visualCaptureStyle: VisualCaptureStyle?
    let onAdd: () -> Void
    let onExtract: () -> Void
    let onExtractSelected: () -> Void
    let onRemove: () -> Void
    let onRename: () -> Void
    let onReplace: () -> Void

    init(
        model: AppModel,
        visualCaptureStyle: VisualCaptureStyle? = nil,
        onAdd: @escaping () -> Void,
        onExtract: @escaping () -> Void,
        onExtractSelected: @escaping () -> Void = {},
        onRemove: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onReplace: @escaping () -> Void
    ) {
        self.model = model
        self.visualCaptureStyle = visualCaptureStyle
        self.onAdd = onAdd
        self.onExtract = onExtract
        self.onExtractSelected = onExtractSelected
        self.onRemove = onRemove
        self.onRename = onRename
        self.onReplace = onReplace
    }

    /// Bridges the model's sidebar visibility flag to NavigationSplitView.
    private var sidebarColumnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { model.sidebarVisible ? .all : .detailOnly },
            set: { model.sidebarVisible = ($0 != .detailOnly) }
        )
    }

    /// Animation style that respects the Reduce Motion accessibility setting.
    private var accessibilityAnimation: Animation? {
        effectiveReduceMotion ? nil : .default
    }

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarColumnVisibility) {
            ArchiveSidebarView(
                model: model,
                onExtract: onExtract,
                onAdd: onAdd,
                onOpenRecent: { url in
                    RecentArchivesManager.shared.noteRecentArchive(url)
                    Task { await model.openArchive(url: url) }
                }
            )
                .accessibilityIdentifier("归档侧栏")
                .accessibilityElement(children: .contain)
                .accessibilityLabel(AppLocalization().string("归档目录"))
        } detail: {
            VStack(spacing: 0) {
                // Inline error banner
                if let errorPresentation = model.activeErrorPresentation {
                    ArchiveErrorBanner(
                        errorType: errorPresentation,
                        onRecoveryAction: errorPresentation.recoveryActionLabel != nil
                            ? { model.performErrorRecoveryAction() }
                            : nil,
                        onDismiss: { model.dismissError() },
                        retryPassword: $model.passwordRetryText,
                        passwordAttemptCount: model.passwordAttemptCount,
                        onRetryPassword: { password in model.retryWithPassword(password) },
                        onResetLockout: { model.passwordAttemptCount = 0 }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Format mismatch warning (persistent until dismissed)
                if let mismatchWarning = model.formatMismatchWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text(mismatchWarning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.formatMismatchWarning = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭格式警告")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.08))
                }

                Group {
                    switch model.viewMode {
                    case .list:
                        ArchiveListView(
                            entries: model.visibleEntries,
                            metadataByEntryID: model.metadataByEntryID,
                            selection: $model.selectedEntryID,
                            nestedArchiveEntryIDs: model.nestedArchiveEntryIDs,
                            canEdit: model.canAdd,
                            canExtractSelected: model.canExtractSelected,
                            onDelete: onRemove,
                            onRename: onRename,
                            onOpenNestedArchive: { entryID in
                                Task { await model.openNestedArchive(entryID: entryID) }
                            },
                            onOpenFile: { entryID in
                                Task { await model.openFileExternally(entryID: entryID) }
                            },
                            onExtractSelected: onExtractSelected,
                            onCopyPath: { path in
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }
                        )
                    case .media:
                        MediaPreviewView(
                            entries: model.visibleEntries,
                            selection: $model.selectedEntryID,
                            metadataByEntryID: model.metadataByEntryID,
                            previewCacheURL: model.selectedPreviewCacheURL,
                            isPreviewLoading: model.isPreviewLoading,
                            previewErrorMessage: model.previewErrorMessage,
                            isVisualCapture: visualCaptureStyle != nil,
                            isCompact: model.compactToolbar,
                            reduceMotion: effectiveReduceMotion,
                            reduceTransparency: effectiveReduceTransparency,
                            increaseContrast: effectiveIncreaseContrast
                        )
                    }
                }
            }
            .animation(accessibilityAnimation, value: model.activeErrorPresentation)
            .task(id: model.viewMode == .media ? model.selectedEntryID : nil) {
                guard model.viewMode == .media else { return }
                await model.loadSelectedPreview()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("预览区域")
            .accessibilityLabel(previewAreaLabel)
            .animation(accessibilityAnimation, value: model.viewMode)
            .inspector(isPresented: $model.inspectorVisible) {
                ArchiveInspectorView(metadata: model.selectedMetadata)
                    .inspectorColumnWidth(min: 265, ideal: 280, max: 340)
            }
        }
        .toolbar { DocumentToolbar(model: model, onAdd: onAdd, onExtract: onExtract, onExtractSelected: onExtractSelected, onRemove: onRemove, onRename: onRename, onReplace: onReplace) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            statusBarContent
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(statusBackground)
            .overlay(alignment: .top) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("状态栏")
            .accessibilityLabel(statusBarLabel)
            .onChange(of: model.lastExtractionURL) { _, newValue in
                if newValue != nil {
                    NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .layoutChanged, userInfo: nil)
                }
            }
        }
        .background(
            effectiveReduceTransparency
                ? Color(nsColor: .windowBackgroundColor)
                : Color.clear
        )
        .overlay {
            if visualCaptureStyle == .increaseContrast {
                GeometryReader { proxy in
                    Path { path in
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                    }
                    .stroke(.primary.opacity(0.75), lineWidth: 2)
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var statusBarContent: some View {
        if model.isExtracting {
            HStack(spacing: 10) {
                ProgressView(value: model.extractionProgress)
                    .frame(width: 140)
                    .accessibilityIdentifier("解压缩进度")
                    .accessibilityLabel(AppLocalization().string("解压缩进度"))
                    .accessibilityValue(model.extractionProgress.formatted(.percent.precision(.fractionLength(0))))
                Text(model.extractionProgress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                Spacer()
                Button("取消") { model.cancelExtraction() }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("取消解压缩")
            }
            .padding(.horizontal, 32)
        } else if let outputURL = model.lastExtractionURL {
            HStack {
                Text(model.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("在 Finder 中显示")
            }
            .padding(.horizontal, 32)
        } else {
            Text(model.statusMessage)
                .accessibilityIdentifier("状态栏消息")
                .font(.callout)
                .foregroundStyle(.primary)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
        }
    }

    private var statusBackground: AnyShapeStyle {
        AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    }

    private var effectiveReduceTransparency: Bool {
        systemReduceTransparency || visualCaptureStyle == .reduceTransparency
    }

    private var effectiveReduceMotion: Bool {
        systemReduceMotion
    }

    private var effectiveIncreaseContrast: Bool {
        systemContrast == .increased || visualCaptureStyle == .increaseContrast
    }

    /// VoiceOver label for the detail/preview region describing what is shown.
    private var previewAreaLabel: String {
        let localization = AppLocalization()
        if model.viewMode == .media, let entry = model.visibleEntries.first(where: { $0.id == model.selectedEntryID }) {
            return localization.format("预览区域，正在预览 %@", entry.displayPath)
        }
        return localization.string("归档内容")
    }

    /// VoiceOver label for the bottom status bar; includes progress while extracting.
    private var statusBarLabel: String {
        let localization = AppLocalization()
        if model.isExtracting {
            return localization.format(
                "%@，解压缩进度 %@",
                model.statusMessage,
                model.extractionProgress.formatted(.percent.precision(.fractionLength(0)))
            )
        }
        return localization.format("状态栏：%@", model.statusMessage)
    }
}
