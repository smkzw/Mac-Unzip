import AppKit
import ArchiveDomain
import Foundation
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
    let onOpenRecent: (URL) -> Void
    let onOpen: (() -> Void)?
    let onCreate: (() -> Void)?

    /// The window hosting this document, captured so accessibility
    /// notifications target the correct window in multi-window sessions.
    @State private var hostingWindow: NSWindow?

    init(
        model: AppModel,
        visualCaptureStyle: VisualCaptureStyle? = nil,
        onAdd: @escaping () -> Void,
        onExtract: @escaping () -> Void,
        onExtractSelected: @escaping () -> Void = {},
        onRemove: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onReplace: @escaping () -> Void,
        onOpenRecent: @escaping (URL) -> Void = { _ in },
        onOpen: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.model = model
        self.visualCaptureStyle = visualCaptureStyle
        self.onAdd = onAdd
        self.onExtract = onExtract
        self.onExtractSelected = onExtractSelected
        self.onRemove = onRemove
        self.onRename = onRename
        self.onReplace = onReplace
        self.onOpenRecent = onOpenRecent
        self.onOpen = onOpen
        self.onCreate = onCreate
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
                onOpenRecent: onOpenRecent,
                onOpen: onOpen,
                onCreate: onCreate
            )
                .accessibilityIdentifier("归档侧栏")
                .accessibilityElement(children: .contain)
                .accessibilityLabel(AppLocalization().string("归档目录"))
        } detail: {
            VStack(spacing: 0) {
                // 自定义扁平头栏（无 Liquid Glass）：仅覆盖内容列，不入侵侧栏；
                // 文件名占该列顶部 40%，其余按键在剩余 60% 同一高度平均分布
                DocumentToolbar(model: model, onAdd: onAdd, onExtract: onExtract, onExtractSelected: onExtractSelected, onRemove: onRemove, onRename: onRename, onReplace: onReplace)
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
                        .accessibilityLabel(AppLocalization().string("关闭格式警告"))
                        .accessibilityHint(AppLocalization().string("点击此按钮可隐藏当前警告"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.12))
                }

                Group {
                    switch model.viewMode {
                    case .list:
                        ArchiveListView(
                            entries: model.visibleEntries,
                            archiveSourceURL: model.currentSourceURL,
                            isSearching: !model.activeSearchText.isEmpty,
                            metadataByEntryID: model.metadataByEntryID,
                            selection: $model.selectedEntryID,
                            selectedEntryIDs: model.selectedEntryIDs,
                            selectedFolderPaths: model.selectedFolderPaths,
                            onMultiSelectionChange: { entryIDs, folderPaths in
                                model.selectedEntryIDs = entryIDs
                                model.selectedFolderPaths = folderPaths
                                if let primary = model.selectedEntryID {
                                    model.selectedEntryIDs.insert(primary)
                                }
                            },
                            nestedArchiveEntryIDs: model.nestedArchiveEntryIDs,
                            pendingChanges: model.pendingChanges,
                            canEdit: model.canAdd,
                            canExtractSelected: model.canExtractSelected,
                            canExtract: model.canExtract,
                            isExtracting: model.isExtracting,
                            onDelete: onRemove,
                            onRename: onRename,
                            onOpenNestedArchive: { entryID in
                                Task { await model.openNestedArchive(entryID: entryID) }
                            },
                            onOpenFile: { entryID in
                                Task { await model.openFileExternally(entryID: entryID) }
                            },
                            onExtractSelected: onExtractSelected,
                            onExtractFolder: { path in
                                model.selectedEntryID = nil
                                model.selectedFolderPath = path
                                model.selectedEntryIDs = []
                                model.selectedFolderPaths = [path]
                                onExtractSelected()
                            },
                            onFolderSelectionChange: { path in
                                model.selectedFolderPath = path
                            },
                            onCopyPath: { path in
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                                model.transientStatusMessage = AppLocalization().string("已拷贝路径")
                            },
                            onAddFiles: { urls, destinationFolder in
                                Task { await model.stageAdditions(from: urls, toFolder: destinationFolder) }
                            },
                            onMoveEntry: { sourcePath, destinationPath in
                                Task { await model.moveEntry(from: sourcePath, to: destinationPath) }
                            },
                            onMaterializeEntry: { entryID, completion in
                                model.materializeEntryForDrag(entryID: entryID, completion: completion)
                            },
                            onIsSupportedArchive: { ArchiveFileTypes.isSupportedArchive($0) },
                            onMaterializeFolder: { path, stagingDir in
                                try await model.materializeFolderForDrag(folderPath: path, stagingDir: stagingDir)
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
                            increaseContrast: effectiveIncreaseContrast,
                            isSearching: !model.activeSearchText.isEmpty
                        )
                    }
                }
            }
            .overlay {
                if model.isLoading {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor).opacity(0.6)
                        ProgressView("正在读取压缩包…")
                            .controlSize(.large)
                            .accessibilityIdentifier("正在读取压缩包")
                    }
                    .transition(.opacity)
                }
            }
            .animation(accessibilityAnimation, value: model.isLoading)
            .animation(accessibilityAnimation, value: model.activeErrorPresentation)
            .task(id: model.viewMode == .media ? model.selectedEntryID : nil) {
                guard model.viewMode == .media else { return }
                await model.loadSelectedPreview()
            }
            .onChange(of: model.viewMode) { _, newMode in
                guard newMode == .media else { return }
                model.selectFirstPreviewableEntry()
            }
            .onChange(of: model.activeSearchText) { _, _ in
                guard model.viewMode == .media else { return }
                model.selectFirstPreviewableEntry()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("预览区域")
            .inspector(isPresented: $model.inspectorVisible) {
                ArchiveInspectorView(metadata: model.selectedMetadata, folder: model.selectedFolderInfo)
                    .inspectorColumnWidth(min: 265, ideal: 280, max: 340)
            }
        }
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
                if newValue != nil, let hostingWindow {
                    NSAccessibility.post(element: hostingWindow, notification: .layoutChanged, userInfo: nil)
                }
            }
        }
        .background(WindowCaptureView { hostingWindow = $0 })
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

/// Reports the NSWindow hosting the represented view, so callers can target
/// window-specific behavior (e.g. accessibility notifications) correctly in
/// multi-window sessions.
struct WindowCaptureView: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowReportingView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}
