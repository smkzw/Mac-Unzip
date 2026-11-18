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
    static let pendingOpenRequest = Notification.Name("pendingOpenRequest")
    static let createArchiveRequest = Notification.Name("createArchiveRequest")
    static let removeSelectedRequest = Notification.Name("removeSelectedRequest")
    static let renameSelectedRequest = Notification.Name("renameSelectedRequest")
    static let extractSelectedRequest = Notification.Name("extractSelectedRequest")
    static let finderCompressRequest = Notification.Name("finderCompressRequest")
}

/// A menu command issued while no window existed, performed by the next window
/// that appears (menu commands posted as notifications would otherwise be lost).
enum PendingWindowCommand {
    case openArchive
    case createArchive
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
    @State private var creationDraftSequence: UInt64 = 0
    @State private var renameAlertPresented = false
    @State private var renameText = ""
    @State private var pendingOpenURL: URL?
    @State private var pendingCreationInputs: [URL]?
    @State private var pendingExtractHereURLs: [URL]?
    @State private var isDropTargeted = false
    @State private var showMixedDropDecision = false
    @State private var mixedDropArchives: [URL] = []
    @State private var mixedDropOthers: [URL] = []
    private let visualCapture: Bool
    private let visualCaptureStyle: VisualCaptureStyle
    private let minimumWindow: Bool
    private let initialArchiveURL: URL?
    private let extractionDestinationURL: URL?
    private let finderAction: String?
    private let finderFilesPath: String?
    private let wantsMediaFixturePreview: Bool
    private let wantsDeferredFixtureDocument: Bool
    private let includeLongFilenameFixture: Bool
    private let wantsCreationFixture: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let fixtureIndex = arguments.firstIndex(of: "-fixture")
        let hasMediaValue = fixtureIndex.map { $0 + 1 < arguments.count && arguments[$0 + 1] == "media" } ?? false
        // Prefer boolean -media-fixture; keep legacy "-fixture media" (requires
        // NSTreatUnknownArgumentsAsOpen=false so "media" is not treated as a file).
        let isMediaFixture = arguments.contains("-ui-testing")
            && (hasMediaValue || arguments.contains("-media-fixture"))
        includeLongFilenameFixture = arguments.contains("-long-filename-fixture")
        // Media fixture is applied in init so the first committed frame is already
        // the browse UI. Creation sheet still opens in onAppear (needs a window).
        let initialModel: AppModel
        if isMediaFixture {
            initialModel = AppModel.mediaFixture(includeLongFilename: includeLongFilenameFixture)
            initialModel.viewMode = .media
        } else {
            initialModel = AppModel()
        }
        if arguments.contains("-appearance-dark") {
            initialModel.appearanceMode = .dark
        } else if arguments.contains("-appearance-light") {
            initialModel.appearanceMode = .light
        }
        _model = State(initialValue: initialModel)
        _creationDraft = State(initialValue: nil)
        wantsMediaFixturePreview = isMediaFixture
        wantsDeferredFixtureDocument = false
        wantsCreationFixture = arguments.contains("-creation-fixture")
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
            // Visual-capture creation fixture: render the panel as the window
            // content. SwiftUI sheets on this multi-display setup are not
            // capturable via screencapture -l/-R (empty / wrong surface).
            if visualCapture, wantsCreationFixture, let draftBinding = creationDraftBindingForCapture {
                CreateArchiveView(
                    model: model,
                    draft: draftBinding,
                    chooseOutput: presentCreationSavePanel,
                    dismiss: { creationDraft = nil }
                )
                .frame(width: UIConstants.createPanelWidth, height: UIConstants.createPanelHeight)
            } else if model.hasDocument {
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
                    WelcomeHomeView(
                        model: model,
                        isDropTargeted: isDropTargeted,
                        onOpen: { presentOpenPanel() },
                        onCreate: { presentCreationInputPanel() }
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization().string(model.hasDocument ? "MacUnzip" : "欢迎"))
        .frame(
            minWidth: (visualCapture && wantsCreationFixture) ? UIConstants.createPanelWidth : 900,
            minHeight: (visualCapture && wantsCreationFixture) ? UIConstants.createPanelHeight : 560
        )
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
                    Text(AppLocalization().string("松开以打开或新建压缩包"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .modifier(NotificationHandlers(
            model: model,
            isDropTargeted: $isDropTargeted,
            pendingOpenURL: $pendingOpenURL,
            pendingCreationInputs: $pendingCreationInputs,
            creationDraft: $creationDraft,
            pendingExtractHereURLs: $pendingExtractHereURLs,
            handleDrop: handleDrop,
            routeDroppedURLs: routeDroppedURLs,
            presentOpenPanel: presentOpenPanel,
            presentCreationInputPanel: presentCreationInputPanel,
            makeCreationDraft: makeCreationDraft
        ))
        .task {
            await handleLaunchArguments()
            await consumeLateOpenEvent()
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
            creationDraft: $creationDraft,
            makeCreationDraft: makeCreationDraft
        ))
        .sheet(
            isPresented: Binding(
                get: { creationDraft != nil && !(visualCapture && wantsCreationFixture) },
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
        .alert(
            AppLocalization().string("混合拖入"),
            isPresented: $showMixedDropDecision
        ) {
            Button(AppLocalization().string("打开其中的压缩包")) {
                showMixedDropDecision = false
                if let first = mixedDropArchives.first {
                    RecentArchivesManager.shared.noteRecentArchive(first)
                    if model.hasUnsavedChanges {
                        pendingOpenURL = first
                    } else {
                        Task { await model.openArchive(url: first) }
                    }
                }
                mixedDropArchives = []
                mixedDropOthers = []
            }
            Button(AppLocalization().string(model.hasDocument ? "全部加入当前压缩包" : "全部作为新建输入")) {
                showMixedDropDecision = false
                let batch = mixedDropArchives + mixedDropOthers
                mixedDropArchives = []
                mixedDropOthers = []
                if model.hasDocument {
                    Task { await model.stageAdditions(from: batch) }
                } else if model.hasUnsavedChanges {
                    pendingCreationInputs = batch
                } else {
                    creationDraft = makeCreationDraft(inputs: batch)
                }
            }
            Button(AppLocalization().string("取消"), role: .cancel) {
                showMixedDropDecision = false
                mixedDropArchives = []
                mixedDropOthers = []
            }
        } message: {
            Text(AppLocalization().format(
                "这次拖入同时包含 %ld 个压缩包和 %ld 个其他项目。请选择打开压缩包，或全部作为文件处理。",
                mixedDropArchives.count,
                mixedDropOthers.count
            ))
        }
        .onAppear {
            MainAppWindowOpener.openWindow = openWindow
            if let pending = PendingWindowCommandBox.shared.take() {
                DispatchQueue.main.async {
                    switch pending {
                    case .openArchive: presentOpenPanel()
                    case .createArchive: presentCreationInputPanel()
                    }
                }
            }
            let deferWindowSizing = wantsDeferredFixtureDocument
                || wantsCreationFixture
                || wantsMediaFixturePreview
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
                if visualCapture || minimumWindow || wantsMediaFixturePreview || wantsCreationFixture {
                    // Prevent autosaved 900×700 frames from overriding capture sizes.
                    window.setFrameAutosaveName("")
                }
                // When fixtures will swap the root view shortly, wait for that
                // pass before the first setFrame — competing sizes during
                // NavigationSplitView / sheet materialization trip Auto Layout.
                if !deferWindowSizing {
                    applyPreferredFrame(to: window)
                }
                if let contentView = window.contentView {
                    labelSplitViewContainers(in: contentView)
                }
            }
            // Apply fixtures after the WindowGroup commits a real window.
            if deferWindowSizing {
                // Use asyncAfter (not Task.sleep) so a brief view identity churn
                // cannot cancel fixture application before capture scripts run.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if wantsMediaFixturePreview, model.previewCacheURL == nil {
                        model.previewCacheURL = FixturePreviewCache.makePDF()
                        model.previewCacheEntryID = model.entries.first {
                            $0.displayPath == "产品指南.pdf"
                        }?.id
                    }
                    // Pin host onto the built-in screen first for media/welcome.
                    // For creation, pin first then present the sheet so it inherits
                    // an on-screen parent — but do not setFrame the parent again
                    // after the sheet appears (that dismisses/detaches it).
                    if let window = NSApp.keyWindow
                        ?? NSApp.windows.first(where: \.isVisible)
                        ?? NSApp.windows.first {
                        applyPreferredFrame(to: window)
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    if wantsCreationFixture, creationDraft == nil {
                        // Use real temp sample files so CreateArchiveView does not
                        // immediately alert "文件不存在" for fictional paths.
                        let sampleRoot = FileManager.default.temporaryDirectory
                            .appendingPathComponent("MacUnzipCreationFixture", isDirectory: true)
                        try? FileManager.default.removeItem(at: sampleRoot)
                        try? FileManager.default.createDirectory(at: sampleRoot, withIntermediateDirectories: true)
                        let assets = sampleRoot.appendingPathComponent("Design Assets", isDirectory: true)
                        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
                        let note = sampleRoot.appendingPathComponent("Launch Notes.pdf")
                        try? Data("%PDF-1.4\n%MacUnzip sample\n".utf8).write(to: note)
                        try? Data("sample asset\n".utf8).write(
                            to: assets.appendingPathComponent("示例主视觉.txt")
                        )
                        var fixture = ArchiveCreationDraft(inputs: [assets, note])
                        // Fictional public destination for screenshots / UI tests —
                        // do not surface host-specific /var/folders paths.
                        fixture.outputURL = URL(fileURLWithPath: "/Users/Sample/Design Assets.zip")
                        // Defer one turn so the parent frame commit lands first.
                        DispatchQueue.main.async {
                            creationDraft = fixture
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        reclaimSheetWindowsOnscreen()
                        if wantsCreationFixture, visualCapture,
                           let window = NSApp.keyWindow
                            ?? NSApp.windows.first(where: \.isVisible)
                            ?? NSApp.windows.first {
                            applyPreferredFrame(to: window)
                        }
                        // Marker for capture scripts — proves fixture UI is up.
                        let kind: String
                        if model.hasDocument {
                            kind = "media:\(model.documentTitle):\(model.entries.count)"
                        } else if creationDraft != nil {
                            kind = "creation"
                        } else {
                            kind = "welcome"
                        }
                        let marker = URL(fileURLWithPath: "/tmp/macunzip_visual_ready")
                        try? kind.write(to: marker, atomically: true, encoding: .utf8)
                    }
                }
            } else if visualCapture {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    try? "welcome".write(
                        to: URL(fileURLWithPath: "/tmp/macunzip_visual_ready"),
                        atomically: true,
                        encoding: .utf8
                    )
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
            guard !allURLs.isEmpty else { return }
            self.routeDroppedURLs(allURLs)
        }
        return true
    }

    /// Routes dropped URLs through the shared decision function.
    private func routeDroppedURLs(_ urls: [URL]) {
        let context: DropRouteContext = model.hasDocument ? .openDocument : .welcome
        guard let decision = DropRouting.decide(
            urls: urls,
            context: context,
            isSupportedArchive: ArchiveFileTypes.isSupportedArchive
        ) else { return }

        switch decision {
        case .openFirstArchive(let first, let ignoredCount):
            RecentArchivesManager.shared.noteRecentArchive(first)
            if model.hasUnsavedChanges {
                pendingOpenURL = first
            } else {
                Task {
                    await model.openArchive(url: first)
                    if ignoredCount > 0, model.hasDocument {
                        model.statusMessage = AppLocalization().format(
                            "已打开第一个压缩包，其余 %ld 个文件未处理。",
                            ignoredCount
                        )
                    }
                }
            }
        case .createArchiveInputs(let batch):
            if model.hasUnsavedChanges {
                pendingCreationInputs = batch
            } else {
                creationDraft = makeCreationDraft(inputs: batch)
            }
        case .addToOpenDocument(let batch):
            Task { await model.stageAdditions(from: batch) }
        case .askMixed(let archives, let others):
            mixedDropArchives = archives
            mixedDropOthers = others
            showMixedDropDecision = true
        }
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
                    bringMainWindowToFront()
                    let ignoredCount = urls.count - 1
                    if ignoredCount > 0, model.hasDocument {
                        model.statusMessage = AppLocalization().format("已打开第一个压缩包，其余 %ld 个文件未处理。", ignoredCount)
                    }
                } else if finderAction == "extract-here" {
                    pendingExtractHereURLs = urls
                } else {
                    if finderAction == "compress-zip" {
                        model.creationFormat = .zip
                    }
                    creationDraft = makeCreationDraft(inputs: urls)
                }
            }
        } else if let initialArchiveURL, !model.hasDocument, !model.isLoading {
            await model.openArchive(url: initialArchiveURL)
            bringMainWindowToFront()
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
            bringMainWindowToFront()
        }
    }

    /// Brings the app and its main window to the front (after a launch-open event).
    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.delegate is UnsavedChangesWindowDelegate }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Consumes an open event that arrived after the launch task ran (cold-start
    /// race between application(_:open:) and SwiftUI view subscription). Polls
    /// briefly until a document opens or the window is past the open-event window.
    private func consumeLateOpenEvent() async {
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline && !model.hasDocument {
            if let pendingURL = MacUnzipAppDelegate.pendingLaunchURL {
                MacUnzipAppDelegate.pendingLaunchURL = nil
                await model.openArchive(url: pendingURL)
                bringMainWindowToFront()
            } else {
                try? await Task.sleep(for: .milliseconds(200))
            }
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


    private func makeCreationDraft(inputs: [URL]) -> ArchiveCreationDraft {
        creationDraftSequence &+= 1
        // Always enter through conflict detection/merge — never bypass for welcome/mixed drops.
        return CreationInputMerging.makeDraft(
            inputs: inputs,
            format: model.creationFormat,
            generation: creationDraftSequence
        )
    }

    private func presentCreationInputPanel() {
        // Show the empty create panel first; Finder selection happens inside the panel.
        if model.hasUnsavedChanges {
            pendingCreationInputs = []
        } else {
            creationDraft = makeCreationDraft(inputs: [])
        }
    }

    private func presentCreationSavePanel(_ suggestedFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = ArchiveCreationCopy.savePanelTitle()
        panel.prompt = ArchiveCreationCopy.savePanelPrompt()
        panel.message = ArchiveCreationCopy.savePanelMessage()
        panel.nameFieldStringValue = suggestedFilename
        if let output = creationDraft?.outputURL {
            panel.directoryURL = output.deletingLastPathComponent()
        } else if let firstInput = creationDraft?.inputs.first {
            panel.directoryURL = firstInput.sourceURL.deletingLastPathComponent()
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
        // 默认定位到压缩包所在目录，减少手动跳转。
        if let sourceURL = model.currentSourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.startExtraction(to: url)
    }

    private func presentExtractSelectedPanel() {
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
        let setting = UserDefaults.standard.string(forKey: SettingsKeys.extractionDestination) ?? "same"
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

    private var creationDraftBindingForCapture: Binding<ArchiveCreationDraft>? {
        guard creationDraft != nil else { return nil }
        return Binding(
            get: { creationDraft ?? ArchiveCreationDraft(inputs: []) },
            set: { creationDraft = $0 }
        )
    }

    /// Prefer the screen that actually owns the window; fall back to intersection, then main.
    private func preferredScreen(for window: NSWindow) -> NSScreen? {
        if let screen = window.screen { return screen }
        let frame = window.frame
        if let hit = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            return hit
        }
        return NSScreen.main
    }

    /// Prefer the zero-origin built-in screen for capture launches.
    private var captureTargetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    /// Creation sheets can inherit an off-screen parent frame; pin ~640 panels back.
    private func reclaimSheetWindowsOnscreen() {
        guard let screen = captureTargetScreen else { return }
        let visible = screen.visibleFrame
        for window in NSApp.windows {
            let frame = window.frame
            let looksLikeCreatePanel =
                abs(frame.width - UIConstants.createPanelWidth) < 40
                && abs(frame.height - UIConstants.createPanelHeight) < 80
            guard looksLikeCreatePanel || !visible.intersects(frame.insetBy(dx: 8, dy: 8)) else {
                continue
            }
            var origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2
            )
            origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
            window.setFrame(NSRect(origin: origin, size: frame.size), display: true)
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                // Best-effort; AppKit may still keep a sheet tied to its parent.
                _ = screenNumber
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Reclaim onto the owning screen. Prefer keeping the WindowGroup launch size
    /// (especially with fixtures) — resizing during NavigationSplitView layout
    /// previously aborted Auto Layout.
    private func applyPreferredFrame(to window: NSWindow) {
        // Capture / fixture launches always use the zero-origin built-in screen.
        // A secondary display above the laptop previously left windows at Y≈-900
        // in CG space and made sheet captures empty.
        let screen: NSScreen?
        if visualCapture || minimumWindow || wantsCreationFixture || wantsMediaFixturePreview {
            screen = captureTargetScreen
        } else {
            screen = preferredScreen(for: window)
        }
        guard let screen else { return }
        let visible = screen.visibleFrame
        let launch = MacUnzipUIConstants.launchWindowSize
        let current = window.frame.size
        let size: NSSize
        if wantsCreationFixture && visualCapture {
            size = NSSize(
                width: UIConstants.createPanelWidth,
                height: min(UIConstants.createPanelHeight, visible.height)
            )
        } else if minimumWindow {
            size = NSSize(width: 900, height: min(700, visible.height))
        } else if visualCapture {
            size = NSSize(
                width: min(launch.width, visible.width),
                height: min(launch.height, visible.height)
            )
        } else if wantsMediaFixturePreview {
            // Media fixture + inspector needs >900pt; 900-wide NavigationSplitView
            // aborts Auto Layout when the inspector column materializes.
            size = NSSize(width: min(1_180, visible.width), height: min(760, visible.height))
        } else if current.width < 800 || current.height < 500 {
            size = NSSize(width: min(1_180, visible.width), height: min(760, visible.height))
        } else {
            size = current
        }
        var origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        let target = NSRect(origin: origin, size: size)
        guard !window.frame.equalTo(target) else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.setFrame(target, display: true)
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
    let makeCreationDraft: ([URL]) -> ArchiveCreationDraft

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
                            creationDraft = makeCreationDraft(inputs)
                        }
                    }
                }
                Button("不保存并继续") {
                    if let inputs = pendingCreationInputs {
                        pendingCreationInputs = nil
                        creationDraft = makeCreationDraft(inputs)
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

private struct NotificationHandlers: ViewModifier {
    let model: AppModel
    @Binding var isDropTargeted: Bool
    @Binding var pendingOpenURL: URL?
    @Binding var pendingCreationInputs: [URL]?
    @Binding var creationDraft: ArchiveCreationDraft?
    @Binding var pendingExtractHereURLs: [URL]?
    let handleDrop: ([NSItemProvider]) -> Bool
    let routeDroppedURLs: ([URL]) -> Void
    let presentOpenPanel: () -> Void
    let presentCreationInputPanel: () -> Void
    let makeCreationDraft: ([URL]) -> ArchiveCreationDraft

    private func isKeyWindow() -> Bool {
        shouldHandleNotification(for: model)
    }

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openArchiveRequest)) { _ in
                guard isKeyWindow() else { return }
                presentOpenPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pendingOpenRequest)) { _ in
                guard isKeyWindow(), !model.hasDocument else { return }
                guard let pendingURL = MacUnzipAppDelegate.pendingLaunchURL else { return }
                MacUnzipAppDelegate.pendingLaunchURL = nil
                let skipped = MacUnzipAppDelegate.pendingSkippedOpenCount
                MacUnzipAppDelegate.pendingSkippedOpenCount = 0
                Task {
                    await model.openArchive(url: pendingURL)
                    if skipped > 0, model.hasDocument {
                        model.statusMessage = AppLocalization().format("已打开首个压缩包，其余 %ld 个已跳过", skipped)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .createArchiveRequest)) { _ in
                guard isKeyWindow() else { return }
                presentCreationInputPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openArchiveURL)) { notification in
                guard let url = notification.object as? URL else { return }
                guard isKeyWindow() else { return }
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.delegate is UnsavedChangesWindowDelegate }) {
                    window.makeKeyAndOrderFront(nil)
                }
                if MacUnzipAppDelegate.pendingLaunchURL == url {
                    MacUnzipAppDelegate.pendingLaunchURL = nil
                }
                let skipped = (notification.userInfo?["skippedCount"] as? Int) ?? 0
                if skipped > 0 {
                    model.transientStatusMessage = AppLocalization().format("已打开首个压缩包，其余 %ld 个已跳过", skipped)
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
                guard isKeyWindow() else { return }
                let action = userInfo["action"] as? String
                if action == "extract-here" {
                    pendingExtractHereURLs = urls
                    return
                }
                if action == "compress-zip" {
                    model.creationFormat = .zip
                }
                if model.hasUnsavedChanges {
                    pendingCreationInputs = urls
                } else {
                    creationDraft = makeCreationDraft(urls)
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
