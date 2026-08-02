import AppKit
import ArchiveProviders
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

private final class URLCollectionBox: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()

    func append(_ url: URL) {
        lock.lock()
        urls.append(url)
        lock.unlock()
    }

    func snapshot() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}

extension Notification.Name {
    static let openArchiveRequest = Notification.Name("openArchiveRequest")
    static let openArchiveURL = Notification.Name("openArchiveURL")
    static let createArchiveRequest = Notification.Name("createArchiveRequest")
    static let removeSelectedRequest = Notification.Name("removeSelectedRequest")
    static let renameSelectedRequest = Notification.Name("renameSelectedRequest")
    static let extractSelectedRequest = Notification.Name("extractSelectedRequest")
    static let finderCompressRequest = Notification.Name("finderCompressRequest")
    static let showLicenseActivationRequest = Notification.Name("showLicenseActivationRequest")
}

/// A menu command issued while no window existed, performed by the next window
/// that appears (menu commands posted as notifications would otherwise be lost).
enum PendingWindowCommand {
    case openArchive
    case createArchive
    case showLicenseActivation
}

final class PendingWindowCommandBox: @unchecked Sendable {
    static let shared = PendingWindowCommandBox()
    private let lock = NSLock()
    private var command: PendingWindowCommand?

    func set(_ command: PendingWindowCommand) {
        lock.lock()
        self.command = command
        lock.unlock()
    }

    func take() -> PendingWindowCommand? {
        lock.lock()
        defer { lock.unlock() }
        let current = command
        command = nil
        return current
    }
}

enum VisualCaptureStyle {
    case standard
    case reduceTransparency
    case increaseContrast
}

@MainActor
private func shouldHandleNotification(for model: AppModel) -> Bool {
    if let keyDelegate = NSApp.keyWindow?.delegate as? UnsavedChangesWindowDelegate {
        return keyDelegate.model === model
    }
    for window in NSApp.orderedWindows {
        if let delegate = window.delegate as? UnsavedChangesWindowDelegate {
            return delegate.model === model
        }
    }
    return true
}

struct RootWindowView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var model: AppModel
    @State private var creationDraft: ArchiveCreationDraft?
    @State private var renameAlertPresented = false
    @State private var renameText = ""
    @State private var pendingOpenURL: URL?
    @State private var pendingCreationInputs: [URL]?
    @State private var licenseSheetFeature: ProFeature?
    @State private var showLicenseSheet = false
    @State private var pendingExtractHereURLs: [URL]?
    @State private var isDropTargeted = false
    private let visualCapture: Bool
    private let visualCaptureStyle: VisualCaptureStyle
    private let minimumWindow: Bool
    private let initialArchiveURL: URL?
    private let extractionDestinationURL: URL?
    private let finderAction: String?
    private let finderFilesPath: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let fixtureIndex = arguments.firstIndex(of: "-fixture")
        let hasMediaValue = fixtureIndex.map { $0 + 1 < arguments.count && arguments[$0 + 1] == "media" } ?? false
        let isMediaFixture = arguments.contains("-ui-testing") && hasMediaValue
        let initialModel = isMediaFixture
            ? AppModel.mediaFixture(includeLongFilename: arguments.contains("-long-filename-fixture"))
            : AppModel()
        if isMediaFixture {
            initialModel.previewCacheURL = FixturePreviewCache.makePDF()
            initialModel.previewCacheEntryID = initialModel.entries.first {
                $0.displayPath == "品牌指南.pdf"
            }?.id
        }
        _model = State(initialValue: initialModel)
        if arguments.contains("-creation-fixture") {
            var fixture = ArchiveCreationDraft(inputs: [
                URL(fileURLWithPath: "/Users/示例/品牌资料", isDirectory: true),
                URL(fileURLWithPath: "/Users/示例/交付说明.pdf"),
            ])
            fixture.outputURL = URL(fileURLWithPath: "/Users/示例/品牌资料.zip")
            _creationDraft = State(initialValue: fixture)
        } else {
            _creationDraft = State(initialValue: nil)
        }
        if arguments.contains("-appearance-dark") {
            initialModel.appearanceMode = .dark
        } else if arguments.contains("-appearance-light") {
            initialModel.appearanceMode = .light
        }
        visualCapture = arguments.contains("-visual-capture")
        minimumWindow = arguments.contains("-minimum-window")
        if let index = arguments.firstIndex(of: "-open-archive"), index + 1 < arguments.count {
            initialArchiveURL = URL(fileURLWithPath: arguments[index + 1])
        } else {
            initialArchiveURL = nil
        }
        if let index = arguments.firstIndex(of: "-extraction-destination"), index + 1 < arguments.count {
            extractionDestinationURL = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else {
            extractionDestinationURL = nil
        }
        if let index = arguments.firstIndex(of: "-finder-action"), index + 1 < arguments.count {
            finderAction = arguments[index + 1]
        } else {
            finderAction = nil
        }
        if let index = arguments.firstIndex(of: "-finder-files"), index + 1 < arguments.count {
            finderFilesPath = arguments[index + 1]
        } else {
            finderFilesPath = nil
        }
        if arguments.contains("-reduce-transparency") {
            visualCaptureStyle = .reduceTransparency
        } else if arguments.contains("-increase-contrast") {
            visualCaptureStyle = .increaseContrast
        } else {
            visualCaptureStyle = .standard
        }
    }

    var body: some View {
        Group {
            if model.hasDocument {
                ArchiveDocumentView(
                    model: model,
                    visualCaptureStyle: visualCapture ? visualCaptureStyle : nil,
                    onAdd: presentAddPanel,
                    onExtract: presentExtractionPanel,
                    onExtractSelected: presentExtractSelectedPanel,
                    onRemove: removeSelectedEntry,
                    onRename: presentRenameAlert,
                    onReplace: presentReplacePanel,
                    onOpenRecent: { url in
                        RecentArchivesManager.shared.noteRecentArchive(url)
                        if model.hasUnsavedChanges {
                            pendingOpenURL = url
                        } else {
                            Task { await model.openArchive(url: url) }
                        }
                    },
                    onOpen: { presentOpenPanel() },
                    onCreate: { presentCreationInputPanel() },
                )
                    .frame(minWidth: 900, minHeight: 560)
            } else {
                if model.isLoading {
                    ProgressView("正在读取压缩包…")
                        .controlSize(.large)
                        .accessibilityIdentifier("正在读取压缩包")
                } else {
                    VStack(spacing: 12) {
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
                        }
                        ContentUnavailableView {
                            Label("MacUnzip", systemImage: "archivebox")
                        } description: {
                            Text(AppLocalization().string(LicenseManager.shared.isProLicensed
                                ? "打开 ZIP、7z、RAR、TAR、DMG、ISO 压缩包，安全查看其中的文件。\n也可以直接将压缩包文件拖放到此窗口。\n\nPro 已激活 · 全部功能可用"
                                : "打开 ZIP、7z、RAR、TAR、DMG、ISO 压缩包，安全查看其中的文件。\n也可以直接将压缩包文件拖放到此窗口。\n\n免费浏览 · 解压缩/创建/编辑需要 Pro"))
                        } actions: {
                            HStack(spacing: 12) {
                                Button("打开压缩包") { presentOpenPanel() }
                                    .buttonStyle(.borderedProminent)
                                    .keyboardShortcut(.defaultAction)
                                    .accessibilityIdentifier("打开压缩包")
                                Button {
                                    presentCreationInputPanel()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("新建压缩包")
                                        if !LicenseManager.shared.isProLicensed {
                                            Text("Pro")
                                                .font(.caption2.weight(.semibold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(.purple.opacity(0.15))
                                                .foregroundStyle(.purple)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                }
                                .help(AppLocalization().string(LicenseManager.shared.isProLicensed
                                    ? "创建 ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST 压缩包"
                                    : "创建 ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST 压缩包（需要 Pro）"))
                                .accessibilityIdentifier("新建压缩包")
                            }
                        }
                        if !model.statusMessage.isEmpty {
                            Text(model.statusMessage)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("欢迎页状态消息")
                        }
                        let recentURLs = RecentArchivesManager.shared.recentURLs
                        let recentMax = UserDefaults.standard.object(forKey: SettingsKeys.recentArchivesCount) == nil
                            ? 10
                            : UserDefaults.standard.integer(forKey: SettingsKeys.recentArchivesCount)
                        if recentMax > 0 && !recentURLs.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("最近打开")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(AppLocalization().string("清除")) {
                                        RecentArchivesManager.shared.clearRecent()
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                                ForEach(recentURLs.prefix(recentMax), id: \.self) { url in
                                    Button {
                                        RecentArchivesManager.shared.noteRecentArchive(url)
                                        Task { await model.openArchive(url: url) }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "archivebox")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(url.lastPathComponent)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                                Text(url.deletingLastPathComponent().lastPathComponent)
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help(url.path)
                                }
                            }
                            .padding(.top, 8)
                            .frame(maxWidth: 320)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization().string(model.hasDocument ? "MacUnzip" : "欢迎"))
        .frame(minWidth: 900, minHeight: 560)
        .focusedValue(\.appModel, model)
        .background(WindowCloseHandler(model: model))
        // Drag-and-drop support for archive files
        .overlay {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.06))
                        )
                    Text("松开以打开压缩包")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openArchiveRequest)) { _ in
            guard shouldHandleNotification(for: model) else { return }
            presentOpenPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createArchiveRequest)) { _ in
            guard shouldHandleNotification(for: model) else { return }
            presentCreationInputPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openArchiveURL)) { notification in
            guard let url = notification.object as? URL else { return }
            guard shouldHandleNotification(for: model) else { return }
            let skipped = (notification.userInfo?["skippedCount"] as? Int) ?? 0
            if skipped > 0 {
                model.transientStatusMessage = AppLocalization().format(
                    "已打开首个压缩包，其余 %ld 个已跳过",
                    skipped
                )
            }
            if model.hasUnsavedChanges {
                pendingOpenURL = url
            } else {
                Task { await model.openArchive(url: url) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .finderCompressRequest)) { notification in
            guard let userInfo = notification.userInfo,
                  let urls = userInfo["urls"] as? [URL], !urls.isEmpty else { return }
            guard shouldHandleNotification(for: model) else { return }
            let action = userInfo["action"] as? String
            if action == "extract-here" {
                guard LicenseGate.requirePro(for: .extract) else { return }
                pendingExtractHereURLs = urls
                return
            }
            guard LicenseGate.requirePro(for: .create) else { return }
            if action == "compress-zip" {
                model.creationFormat = .zip
            }
            if model.hasUnsavedChanges {
                pendingCreationInputs = urls
            } else {
                creationDraft = ArchiveCreationDraft(inputs: urls)
            }
        }
        .task {
            await handleLaunchArguments()
        }
        .modifier(EditNotificationHandler(
            model: model,
            onRemove: removeSelectedEntry,
            onRename: presentRenameAlert,
            onExtractSelected: presentExtractSelectedPanel
        ))
        .modifier(RootAlertsModifier(
            model: model,
            renameAlertPresented: $renameAlertPresented,
            renameText: $renameText,
            pendingOpenURL: $pendingOpenURL,
            pendingCreationInputs: $pendingCreationInputs,
            creationDraft: $creationDraft
        ))
        .sheet(
            isPresented: Binding(
                get: { creationDraft != nil },
                set: { if !$0 { creationDraft = nil } }
            )
        ) {
            if creationDraft != nil {
                CreateArchiveView(
                    model: model,
                    draft: Binding(
                        get: { creationDraft ?? ArchiveCreationDraft(inputs: []) },
                        set: { creationDraft = $0 }
                    ),
                    chooseOutput: presentCreationSavePanel,
                    dismiss: { creationDraft = nil }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LicenseGate.upgradeRequiredNotification)) { notification in
            guard shouldHandleNotification(for: model) else { return }
            licenseSheetFeature = notification.userInfo?["feature"] as? ProFeature
            showLicenseSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLicenseActivationRequest)) { _ in
            guard shouldHandleNotification(for: model) else { return }
            licenseSheetFeature = nil
            showLicenseSheet = true
        }
        .sheet(
            isPresented: Binding(
                get: { showLicenseSheet },
                set: { if !$0 { showLicenseSheet = false; licenseSheetFeature = nil } }
            )
        ) {
            LicenseActivationView(requestedFeature: licenseSheetFeature)
        }
        .alert(
            AppLocalization().string("解压到所在文件夹"),
            isPresented: Binding(
                get: { pendingExtractHereURLs != nil },
                set: { if !$0 { pendingExtractHereURLs = nil } }
            )
        ) {
            Button(AppLocalization().string("解压缩")) {
                guard let urls = pendingExtractHereURLs else { return }
                pendingExtractHereURLs = nil
                Task {
                    for url in urls {
                        await model.openArchive(url: url)
                        if model.hasDocument {
                            model.startExtraction(to: url.deletingLastPathComponent())
                            await model.awaitExtractionCompletion()
                        }
                    }
                }
            }
            Button(AppLocalization().string("取消"), role: .cancel) { pendingExtractHereURLs = nil }
        } message: {
            if let urls = pendingExtractHereURLs {
                Text(AppLocalization().format("即将把 %ld 个压缩包解压到各自所在的文件夹。", urls.count))
            }
        }
        .onAppear {
            MainAppWindowOpener.openWindow = openWindow
            if let pending = PendingWindowCommandBox.shared.take() {
                DispatchQueue.main.async {
                    switch pending {
                    case .openArchive: presentOpenPanel()
                    case .createArchive: presentCreationInputPanel()
                    case .showLicenseActivation:
                        licenseSheetFeature = nil
                        showLicenseSheet = true
                    }
                }
            }
            DispatchQueue.main.async {
                guard let window = NSApp.keyWindow
                    ?? NSApp.windows.first(where: \.isVisible)
                    ?? NSApp.windows.first else { return }
                let localization = AppLocalization()
                let label = localization.string(model.hasDocument ? "MacUnzip" : "欢迎")
                window.setAccessibilityLabel(label)
                window.setAccessibilityIdentifier("MacUnzipMainWindow")
                window.titleVisibility = .hidden
                window.contentView?.setAccessibilityLabel(label)
                window.contentView?.setAccessibilityIdentifier("MacUnzipMainWindowContent")
                if minimumWindow, let screen = window.screen ?? NSScreen.main {
                    let visibleFrame = screen.visibleFrame
                    let size = NSSize(width: 900, height: min(700, visibleFrame.height))
                    window.setFrame(
                        NSRect(
                            x: visibleFrame.midX - size.width / 2,
                            y: visibleFrame.midY - size.height / 2,
                            width: size.width,
                            height: size.height
                        ),
                        display: true
                    )
                } else if visualCapture, let screen = window.screen ?? NSScreen.main {
                    let targetAspect = CGFloat(1_487.0 / 1_058.0)
                    let visibleFrame = screen.visibleFrame
                    var targetHeight = min(872, visibleFrame.height)
                    var targetWidth = targetHeight * targetAspect
                    if targetWidth > visibleFrame.width {
                        targetWidth = visibleFrame.width
                        targetHeight = targetWidth / targetAspect
                    }
                    let origin = NSPoint(
                        x: visibleFrame.midX - targetWidth / 2,
                        y: visibleFrame.midY - targetHeight / 2
                    )
                    window.setFrame(
                        NSRect(origin: origin, size: NSSize(width: targetWidth, height: targetHeight)),
                        display: true
                    )
                }
                if let contentView = window.contentView {
                    labelSplitViewContainers(in: contentView)
                }
            }
        }
        .onChange(of: model.appearanceMode, initial: true) { _, mode in
            switch mode {
            case .system: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
        .onChange(of: model.hasDocument) { _, hasDocument in
            guard let window = NSApp.keyWindow
                ?? NSApp.windows.first(where: \.isVisible)
                ?? NSApp.windows.first else { return }
            let label = AppLocalization().string(hasDocument ? "MacUnzip" : "欢迎")
            window.setAccessibilityLabel(label)
            window.contentView?.setAccessibilityLabel(label)
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        let box = URLCollectionBox()
        let group = DispatchGroup()
        for provider in fileProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let directURL = item as? URL {
                    url = directURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                if let url { box.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let allURLs = box.snapshot()
            let supported = allURLs.filter { ArchiveFileTypes.isSupportedArchive($0) }
            guard let first = supported.first else {
                if let firstURL = allURLs.first {
                    let ext = firstURL.pathExtension
                    let descriptor = ext.isEmpty ? firstURL.lastPathComponent : ext
                    model.statusMessage = AppLocalization().format("不支持的文件类型：%@。请拖入 ZIP、7z、RAR、TAR 等压缩包文件。", descriptor)
                }
                return
            }
            RecentArchivesManager.shared.noteRecentArchive(first)
            let ignoredCount = supported.count - 1
            if model.hasUnsavedChanges {
                pendingOpenURL = first
            } else {
                Task {
                    await model.openArchive(url: first)
                    if ignoredCount > 0, model.hasDocument {
                        model.statusMessage = AppLocalization().format("已打开第一个压缩包，其余 %ld 个文件未处理。", ignoredCount)
                    }
                }
            }
        }
        return true
    }

    private func handleLaunchArguments() async {
        if let finderAction, let finderFilesPath, !model.hasDocument {
            let paths = (try? String(contentsOfFile: finderFilesPath, encoding: .utf8))?
                .split(separator: "\0", omittingEmptySubsequences: true)
                .map(String.init) ?? []
            try? FileManager.default.removeItem(atPath: finderFilesPath)
            if !paths.isEmpty {
                let urls = paths.map { URL(fileURLWithPath: $0) }
                if finderAction == "open" {
                    guard let first = urls.first else { return }
                    RecentArchivesManager.shared.noteRecentArchive(first)
                    await model.openArchive(url: first)
                    let ignoredCount = urls.count - 1
                    if ignoredCount > 0, model.hasDocument {
                        model.statusMessage = AppLocalization().format("已打开第一个压缩包，其余 %ld 个文件未处理。", ignoredCount)
                    }
                } else if finderAction == "extract-here" {
                    guard LicenseGate.requirePro(for: .extract) else { return }
                    pendingExtractHereURLs = urls
                } else {
                    guard LicenseGate.requirePro(for: .create) else { return }
                    if finderAction == "compress-zip" {
                        model.creationFormat = .zip
                    }
                    creationDraft = ArchiveCreationDraft(inputs: urls)
                }
            }
        } else if let initialArchiveURL, !model.hasDocument, !model.isLoading {
            await model.openArchive(url: initialArchiveURL)
        } else if let pendingURL = MacUnzipAppDelegate.pendingLaunchURL, !model.hasDocument, !model.isLoading {
            MacUnzipAppDelegate.pendingLaunchURL = nil
            let skipped = MacUnzipAppDelegate.pendingSkippedOpenCount
            MacUnzipAppDelegate.pendingSkippedOpenCount = 0
            if skipped > 0 {
                model.transientStatusMessage = AppLocalization().format(
                    "已打开首个压缩包，其余 %ld 个已跳过",
                    skipped
                )
            }
            await model.openArchive(url: pendingURL)
        }
    }

    // MARK: - Panels

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = ArchiveShellCopy.openPanelTitle()
        panel.prompt = ArchiveShellCopy.openPanelPrompt()
        panel.message = ArchiveShellCopy.openPanelMessage()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ArchiveFileTypes.contentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        RecentArchivesManager.shared.noteRecentArchive(url)
        if model.hasUnsavedChanges {
            pendingOpenURL = url
        } else {
            Task { await model.openArchive(url: url) }
        }
    }

    private func presentCreationInputPanel() {
        guard LicenseGate.requirePro(for: .create) else { return }
        let panel = NSOpenPanel()
        panel.title = ArchiveCreationCopy.inputPanelTitle()
        panel.prompt = ArchiveCreationCopy.inputPanelPrompt()
        panel.message = ArchiveCreationCopy.inputPanelMessage()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        if model.hasUnsavedChanges {
            pendingCreationInputs = panel.urls
        } else {
            creationDraft = ArchiveCreationDraft(inputs: panel.urls)
        }
    }

    private func presentCreationSavePanel(_ suggestedFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = ArchiveCreationCopy.savePanelTitle()
        panel.prompt = ArchiveCreationCopy.savePanelPrompt()
        panel.message = ArchiveCreationCopy.savePanelMessage()
        panel.nameFieldStringValue = suggestedFilename
        if let firstInput = creationDraft?.inputs.first {
            panel.directoryURL = firstInput.deletingLastPathComponent()
        }
        let ext = URL(fileURLWithPath: suggestedFilename).pathExtension
        if let ut = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [ut]
        }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private func presentAddPanel() {
        guard LicenseGate.requirePro(for: .edit) else { return }
        let panel = NSOpenPanel()
        panel.title = ArchiveShellCopy.addPanelTitle()
        panel.prompt = ArchiveShellCopy.addPanelPrompt()
        panel.message = ArchiveShellCopy.addPanelMessage()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { await model.stageAdditions(from: urls) }
    }

    private func removeSelectedEntry() {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard model.canRemoveSelectedEntry else {
            model.transientStatusMessage = AppLocalization().string(
                model.selectedEntryID == nil && model.selectedFolderPath != nil
                    ? "暂不支持直接移除文件夹"
                    : "此格式为只读，不支持编辑")
            return
        }
        Task { await model.removeSelectedEntry() }
    }

    private func presentRenameAlert() {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard model.canRenameSelectedEntry else {
            model.transientStatusMessage = AppLocalization().string(
                model.selectedEntryID == nil && model.selectedFolderPath != nil
                    ? "暂不支持直接重命名文件夹"
                    : "此格式为只读，不支持编辑")
            return
        }
        renameText = model.selectedEntryFileName ?? ""
        renameAlertPresented = true
    }

    private func presentReplacePanel() {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard let fileName = model.selectedEntryFileName else { return }
        let localization = AppLocalization()
        let panel = NSOpenPanel()
        panel.title = localization.string("替换文件")
        panel.prompt = localization.string("替换")
        panel.message = localization.format("选择用于替换%@的新文件", fileName)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        let originalExtension = (fileName as NSString).pathExtension
        if !originalExtension.isEmpty {
            if let utType = UTType(filenameExtension: originalExtension) {
                panel.allowedContentTypes = [utType]
            }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.replaceSelectedEntry(with: url) }
    }



    private func presentExtractionPanel() {
        guard LicenseGate.requirePro(for: .extract) else { return }
        if let extractionDestinationURL {
            model.startExtraction(to: extractionDestinationURL)
            return
        }
        if let direct = preferredExtractionDirectory {
            model.startExtraction(to: direct)
            return
        }
        let panel = NSOpenPanel()
        panel.title = ArchiveShellCopy.extractionPanelTitle()
        panel.prompt = ArchiveShellCopy.extractionPanelPrompt()
        panel.message = ArchiveShellCopy.extractionPanelMessage()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.startExtraction(to: url)
    }

    private func presentExtractSelectedPanel() {
        guard LicenseGate.requirePro(for: .extract) else { return }
        if let direct = preferredExtractionDirectory {
            model.startExtractSelected(to: direct)
            return
        }
        let panel = NSOpenPanel()
        panel.title = AppLocalization().string("选择解压位置")
        panel.prompt = AppLocalization().string("解压缩到此处")
        panel.message = AppLocalization().string("解压缩所选项目到指定位置。")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.startExtractSelected(to: url)
    }

    /// The directory the user configured as the default extraction destination,
    /// or nil when they chose to be asked each time (or it cannot be resolved).
    private var preferredExtractionDirectory: URL? {
        let setting = UserDefaults.standard.string(forKey: SettingsKeys.extractionDestination) ?? "ask"
        switch setting {
        case "same":
            // In a nested session currentSourceURL is a temporary materialized
            // copy, so "same directory" would point into a temp folder; fall
            // through to the interactive picker instead.
            guard !model.isNestedSession else { return nil }
            return model.currentSourceURL?.deletingLastPathComponent()
        case "desktop":
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        default:
            return nil
        }
    }

    private func labelSplitViewContainers(in view: NSView) {
        let localization = AppLocalization()
        let windowRect = view.convert(view.bounds, to: nil)
        let contentBounds = view.window?.contentView?.bounds ?? .zero
        let existingLabel: String? = view.accessibilityLabel()
        let role: NSAccessibility.Role? = view.accessibilityRole()
        if role == .group,
           existingLabel?.isEmpty != false,
           windowRect.height >= contentBounds.height * 0.75 {
            let semanticLabel: String?
            if windowRect.minX <= 20, windowRect.width <= 320 {
                semanticLabel = "归档目录"
            } else if windowRect.maxX >= contentBounds.width - 20, windowRect.width <= 420 {
                semanticLabel = "归档信息"
            } else if windowRect.width >= 400 {
                semanticLabel = "归档内容"
            } else {
                semanticLabel = nil
            }
            if let semanticLabel {
                view.setAccessibilityLabel(localization.string(semanticLabel))
                view.setAccessibilityIdentifier("\(semanticLabel)容器")
            }
        }
        if let splitView = view as? NSSplitView {
            splitView.setAccessibilityLabel(localization.string("归档分栏"))
            for (index, pane) in splitView.arrangedSubviews.enumerated() {
                let paneLabel: String
                if pane.frame.width <= 320, index == 0 {
                    paneLabel = "归档目录"
                } else if pane.frame.width <= 400, index == splitView.arrangedSubviews.count - 1 {
                    paneLabel = "归档信息"
                } else {
                    paneLabel = "归档内容"
                }
                pane.setAccessibilityLabel(localization.string(paneLabel))
                pane.setAccessibilityIdentifier("\(paneLabel)容器")
            }
        }
        for subview in view.subviews {
            labelSplitViewContainers(in: subview)
        }
    }
}

private struct RootAlertsModifier: ViewModifier {
    let model: AppModel
    @Binding var renameAlertPresented: Bool
    @Binding var renameText: String
    @Binding var pendingOpenURL: URL?
    @Binding var pendingCreationInputs: [URL]?
    @Binding var creationDraft: ArchiveCreationDraft?

    func body(content: Content) -> some View {
        content
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { model.presentedError != nil },
                    set: { if !$0 { model.presentedError = nil } }
                )
            ) {
                Button("好") { model.presentedError = nil }
            } message: {
                Text(model.presentedError ?? "")
            }
            .alert(
                "重命名",
                isPresented: $renameAlertPresented
            ) {
                TextField("新名称：", text: $renameText)
                Button("确定") {
                    let newName = renameText
                    Task { await model.renameSelectedEntry(to: newName) }
                }
                .disabled(renameText.isEmpty || renameText.contains(where: { "/:\\<>|?*\"".contains($0) }))
                .keyboardShortcut(.defaultAction)
                Button("取消", role: .cancel) { }
            } message: {
                Text("请输入新的文件名。不能包含 / : \\ < > | ? * \" 等字符。")
            }
            .alert(
                "此归档有未保存的更改",
                isPresented: Binding(
                    get: { pendingOpenURL != nil },
                    set: { if !$0 { pendingOpenURL = nil } }
                )
            ) {
                Button("保存并打开") {
                    if let url = pendingOpenURL {
                        pendingOpenURL = nil
                        Task {
                            let saved = await model.saveArchiveResolvingNested()
                            guard saved else { return }
                            await model.openArchive(url: url)
                        }
                    }
                }
                Button("不保存并打开") {
                    if let url = pendingOpenURL {
                        pendingOpenURL = nil
                        Task { await model.openArchive(url: url) }
                    }
                }
                Button("取消", role: .cancel) { pendingOpenURL = nil }
            } message: {
                Text("如果不保存，所做的修改将会丢失。")
            }
            .alert(
                "此归档有未保存的更改",
                isPresented: Binding(
                    get: { pendingCreationInputs != nil },
                    set: { if !$0 { pendingCreationInputs = nil } }
                )
            ) {
                Button("保存并继续") {
                    if let inputs = pendingCreationInputs {
                        pendingCreationInputs = nil
                        Task {
                            let saved = await model.saveArchiveResolvingNested()
                            guard saved else { return }
                            creationDraft = ArchiveCreationDraft(inputs: inputs)
                        }
                    }
                }
                Button("不保存并继续") {
                    if let inputs = pendingCreationInputs {
                        pendingCreationInputs = nil
                        creationDraft = ArchiveCreationDraft(inputs: inputs)
                    }
                }
                Button("取消", role: .cancel) { pendingCreationInputs = nil }
            } message: {
                Text("如果不保存，所做的修改将会丢失。")
            }
            .alert(
                "发现未完成的保存操作",
                isPresented: Binding(
                    get: { model.isRecoveryAlertPresented },
                    set: { model.isRecoveryAlertPresented = $0 }
                )
            ) {
                if let journal = model.pendingRecoveryJournals.first {
                    Button("恢复") { model.recoverJournal(journal) }
                    Button("删除", role: .destructive) { model.discardJournal(journal) }
                    Button("稍后", role: .cancel) { model.deferJournal(journal) }
                }
            } message: {
                if let journal = model.pendingRecoveryJournals.first {
                    Text("上次保存 \(URL(fileURLWithPath: journal.sourceArchive).lastPathComponent) 时中断，是否恢复？")
                }
            }
    }
}

private struct EditNotificationHandler: ViewModifier {
    let model: AppModel
    let onRemove: () -> Void
    let onRename: () -> Void
    let onExtractSelected: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .removeSelectedRequest)) { _ in
                guard shouldHandleNotification(for: model) else { return }
                onRemove()
            }
            .onReceive(NotificationCenter.default.publisher(for: .renameSelectedRequest)) { _ in
                guard shouldHandleNotification(for: model) else { return }
                onRename()
            }
            .onReceive(NotificationCenter.default.publisher(for: .extractSelectedRequest)) { _ in
                guard shouldHandleNotification(for: model) else { return }
                onExtractSelected()
            }
    }
}

private struct CreateArchiveView: View {
    @Bindable var model: AppModel
    @Binding var draft: ArchiveCreationDraft
    let chooseOutput: (String) -> URL?
    let dismiss: () -> Void
    @State private var showRARLicenseConfirmation = false
    @State private var rarRevertFormat: CreationFormat?

    private var passwordsMatch: Bool {
        !model.creationEncryptionEnabled
            || !model.creationFormat.supportsEncryption
            || (!model.creationPassword.isEmpty && model.creationPassword == model.creationPasswordConfirm)
    }

    private var canCreate: Bool {
        draft.canCreate && passwordsMatch && !model.isCreating
            && model.engineInstalled(for: model.creationFormat)
            && (model.creationFormat != .zip || (model.preflightIssues.isEmpty && !model.isRunningPreflight))
    }

    private var createDisabledReason: String {
        let localization = AppLocalization()
        if draft.inputs.isEmpty { return localization.string("请先添加要压缩的文件") }
        if draft.outputURL == nil { return localization.string("请选择保存位置") }
        if !model.engineInstalled(for: model.creationFormat) { return missingEngineMessage(for: model.creationFormat) }
        if model.creationEncryptionEnabled && model.creationFormat.supportsEncryption && model.creationPassword.isEmpty { return localization.string("请输入密码") }
        if !passwordsMatch { return localization.string("两次输入的密码不一致") }
        if model.creationFormat == .zip {
            if model.isRunningPreflight { return localization.string("正在检查文件名兼容性…") }
            if !model.preflightIssues.isEmpty { return localization.string("请先自动修正文件名兼容性问题") }
        }
        if model.isCreating { return localization.string("正在创建中…") }
        return ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                formatPicker
                inputList
                compressionSection
                if model.creationFormat.supportsEncryption {
                    encryptionSection
                }
                if model.creationFormat == .zip {
                    preflightSection
                }
                compatibility
                destination
                Divider()
                footer
            }
            .padding(24)
        }
        .alert(
            "无法创建压缩包",
            isPresented: Binding(
                get: { model.creationErrorMessage != nil },
                set: { if !$0 { model.creationErrorMessage = nil } }
            )
        ) {
            Button("好") { model.creationErrorMessage = nil }
        } message: {
            Text(model.creationErrorMessage ?? "")
        }
        .alert(
            AppLocalization().string(RARLicenseConfirmation.confirmationTitle),
            isPresented: $showRARLicenseConfirmation
        ) {
            Button(AppLocalization().string(RARLicenseConfirmation.confirmButton)) {
                RARLicenseConfirmation().confirm()
            }
            Button(AppLocalization().string(RARLicenseConfirmation.cancelButton), role: .cancel) {
                model.creationFormat = rarRevertFormat ?? .zip
            }
        } message: {
            Text(AppLocalization().string(RARLicenseConfirmation.confirmationMessage))
        }
        .alert(
            AppLocalization().string("文件已存在"),
            isPresented: Binding(
                get: { model.pendingOverwriteURL != nil },
                set: { if !$0 { model.resolveOverwriteConfirmation(replace: false) } }
            )
        ) {
            Button(AppLocalization().string("替换"), role: .destructive) {
                model.resolveOverwriteConfirmation(replace: true)
            }
            Button(AppLocalization().string("取消"), role: .cancel) {
                model.resolveOverwriteConfirmation(replace: false)
            }
        } message: {
            Text(AppLocalization().format(
                "“%@”已存在。继续创建将替换原有文件。",
                model.pendingOverwriteURL?.lastPathComponent ?? ""
            ))
        }
        .frame(width: 700, height: 680)
        .interactiveDismissDisabled(model.isCreating)
        .onChange(of: model.lastCreatedURL) { _, outputURL in
            if outputURL != nil { dismiss() }
        }
        .onAppear {
            if model.creationFormat == .zip {
                Task { await model.runPreflight(inputs: draft.inputs) }
            }
        }
        .onChange(of: model.creationFormat) { oldFormat, newFormat in
            if let current = draft.outputURL {
                let retagged = ArchiveCreationDraft.retaggedFilename(current.lastPathComponent, for: newFormat)
                draft.outputURL = current.deletingLastPathComponent().appendingPathComponent(retagged)
            }
            if newFormat == .zip {
                Task { await model.runPreflight(inputs: draft.inputs) }
            } else {
                model.resetPreflight()
            }
            if newFormat == .rar, model.engineInstalled(for: .rar),
               !RARLicenseConfirmation().isConfirmed {
                rarRevertFormat = oldFormat == .rar ? rarRevertFormat : oldFormat
                showRARLicenseConfirmation = true
            }
        }
        .onDisappear {
            model.resetCreationState()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("创建归档面板")
        .accessibilityIdentifier("创建归档面板")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text("新建压缩包")
                    .font(.title2.weight(.semibold))
                Text(ArchiveCreationCopy.subtitle())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Format Picker

    private var formatPicker: some View {
        GroupBox("格式") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("格式", selection: $model.creationFormat) {
                    ForEach(CreationFormat.allCases, id: \.self) { format in
                        Text(model.engineInstalled(for: format)
                            ? format.displayName
                            : format.displayName + AppLocalization().string("（未安装）")
                        ).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("格式选择")

                Text(model.creationFormat.capabilityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.engineInstalled(for: model.creationFormat) {
                    Text(missingEngineMessage(for: model.creationFormat))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("引擎缺失提示")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func missingEngineMessage(for format: CreationFormat) -> String {
        let localization = AppLocalization()
        switch format {
        case .sevenZip: return localization.string("创建 7z 需要免费的 7zz 工具。可在「终端」运行 brew install 7zip，或从 7-zip.org 下载，安装后在「设置 → 引擎」确认已检测到。")
        case .rar: return localization.string("创建 RAR 需要 RARLAB 官方 rar 工具。请从 rarlab.com 下载 macOS 版并安装，然后在「设置 → 引擎」确认已检测到。")
        default: return ""
        }
    }

    private func inputSubtitle(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let tempRoot = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if parent.hasPrefix(tempRoot) {
            return AppLocalization().string("已为 Windows 兼容性自动修正")
        }
        return parent
    }

    private var inputList: some View {
        GroupBox(ArchiveCreationCopy.inputCount(draft.inputs.count)) {
            List(draft.inputs, id: \.self) { url in
                HStack(spacing: 10) {
                    Image(systemName: url.hasDirectoryPath ? "folder.fill" : "doc.fill")
                        .foregroundStyle(url.hasDirectoryPath ? .blue : .secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(inputSubtitle(for: url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .frame(height: 120)
        }
    }

    // MARK: - Compression Section

    private var compressionSection: some View {
        GroupBox("压缩") {
            VStack(alignment: .leading, spacing: 10) {
                if model.creationFormat == .zip {
                    Picker("压缩级别", selection: $model.creationCompressionLevel) {
                        ForEach(ZIPCompressionLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("ZIP压缩级别")
                } else {
                    Text("默认压缩")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Encryption Section (ZIP only)

    private var encryptionSection: some View {
        GroupBox("加密") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("加密", isOn: $model.creationEncryptionEnabled)
                    .accessibilityIdentifier("加密开关")

                if model.creationEncryptionEnabled {
                    SecureField("密码", text: $model.creationPassword)
                        .accessibilityIdentifier("加密密码")
                    SecureField("确认密码", text: $model.creationPasswordConfirm)
                        .accessibilityIdentifier("确认密码")

                    if !model.creationPassword.isEmpty
                        && model.creationPassword != model.creationPasswordConfirm {
                        Text("密码不一致")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("密码不一致")
                    }

                    if model.creationFormat == .zip {
                        Picker("加密方式", selection: $model.creationEncryptionMethod) {
                            ForEach(EncryptionMethod.allCases, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("加密方式")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preflight Section (ZIP only)

    @ViewBuilder
    private var preflightSection: some View {
        if !model.preflightIssues.isEmpty {
            GroupBox("Windows 兼容性检查") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.preflightIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.filename)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                Text("\(issue.issue) — \(issue.suggestion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button("自动修正") {
                            Task {
                                let sanitized = await model.fixPreflightIssues(inputs: draft.inputs)
                                if !sanitized.isEmpty {
                                    draft.inputs = sanitized
                                }
                                await model.runPreflight(inputs: draft.inputs)
                            }
                        }
                        .accessibilityIdentifier("自动修正")
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("预检问题列表")
        }
    }

    private var compatibility: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(compatibilityTitle)
                    .fontWeight(.semibold)
                Text(compatibilityDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("兼容性摘要")
    }

    private var compatibilityTitle: String {
        let localization = AppLocalization()
        switch model.creationFormat {
        case .zip: return localization.string("Windows 11 可直接打开")
        case .sevenZip: return localization.string("7-Zip / Keka / The Unarchiver 兼容")
        case .rar: return localization.string("WinRAR / 7-Zip / Keka 兼容")
        case .tarGz, .tarXz, .tarZst: return localization.string("macOS / Linux / Windows (7-Zip) 兼容")
        }
    }

    private var compatibilityDetail: String {
        let localization = AppLocalization()
        switch model.creationFormat {
        case .zip:
            return localization.string("使用 UTF-8 文件名，自动排除 macOS 元数据；创建前检查 Windows 保留名、非法字符和名称冲突。")
        case .sevenZip:
            return localization.string("AES-256 加密，高压缩率；Windows 需 7-Zip 打开，macOS 可用 Keka 或 The Unarchiver。")
        case .rar:
            return localization.string("RARLAB 专有格式，广泛兼容；需已安装并授权 RARLAB rar 命令行工具。")
        case .tarGz, .tarXz, .tarZst:
            return localization.string("保留 Unix 权限；适合 macOS/Linux 分发，Windows 需 7-Zip 解压。符号链接出于安全考虑不予包含。")
        }
    }

    private var destination: some View {
        GroupBox("保存位置") {
            HStack(spacing: 12) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(draft.outputURL?.path ?? ArchiveCreationCopy.noSelection())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(draft.outputURL == nil ? .secondary : .primary)
                Spacer()
                Button("选择…") {
                    if let url = chooseOutput(draft.suggestedFilename(for: model.creationFormat)) {
                        draft.outputURL = url
                    }
                }
                .disabled(model.isCreating)
                .help(model.isCreating ? "正在创建中，暂不能更改保存位置" : "选择压缩包的保存位置")
                .accessibilityIdentifier("选择保存位置")
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isCreating {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.operationMessage)
                    Spacer()
                    Text(model.creationProgress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                ProgressView(value: model.creationProgress)
                    .accessibilityIdentifier("创建进度")
                HStack {
                    Spacer()
                    Button("取消") { model.cancelCreation() }
                        .accessibilityIdentifier("取消创建")
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ArchiveCreationCopy.verificationNote())
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !canCreate {
                        Text(createDisabledReason)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("新建压缩包") {
                    guard let outputURL = draft.outputURL else { return }
                    model.startCreation(at: outputURL, inputs: draft.inputs)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .help(canCreate ? AppLocalization().string("创建压缩包") : createDisabledReason)
                .accessibilityIdentifier("确认创建归档")
            }
        }
    }
}
