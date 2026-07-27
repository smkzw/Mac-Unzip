import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let openArchiveRequest = Notification.Name("openArchiveRequest")
    static let openArchiveURL = Notification.Name("openArchiveURL")
    static let createArchiveRequest = Notification.Name("createArchiveRequest")
    static let removeSelectedRequest = Notification.Name("removeSelectedRequest")
    static let renameSelectedRequest = Notification.Name("renameSelectedRequest")
    static let extractSelectedRequest = Notification.Name("extractSelectedRequest")
    static let finderCompressRequest = Notification.Name("finderCompressRequest")
}

enum VisualCaptureStyle {
    case standard
    case reduceTransparency
    case increaseContrast
}

struct RootWindowView: View {
    @State private var model: AppModel
    @State private var creationDraft: ArchiveCreationDraft?
    @State private var renameAlertPresented = false
    @State private var renameText = ""
    @State private var pendingOpenURL: URL?
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
                )
                    .frame(minWidth: 900, minHeight: 560)
            } else {
                if model.isLoading {
                    ProgressView("正在读取压缩包…")
                        .controlSize(.large)
                        .accessibilityIdentifier("正在读取压缩包")
                } else {
                    ContentUnavailableView {
                        Label("Mac解霸", systemImage: "archivebox")
                    } description: {
                        Text("Mac解霸 — 打开 ZIP、7z、RAR、TAR、DMG、ISO 压缩包，安全查看其中的文件。\n也可以直接将压缩包文件拖放到此窗口。")
                    } actions: {
                        HStack(spacing: 12) {
                            Button("打开压缩包") { presentOpenPanel() }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                                .accessibilityIdentifier("打开压缩包")
                            Button("创建归档") { presentCreationInputPanel() }
                                .help("创建 ZIP、7z、TAR 或 RAR 压缩包")
                                .accessibilityIdentifier("创建归档")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization().string(model.hasDocument ? "Mac解霸" : "欢迎"))
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
            presentOpenPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .createArchiveRequest)) { _ in
            presentCreationInputPanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openArchiveURL)) { notification in
            guard let url = notification.object as? URL else { return }
            if let keyDelegate = NSApp.keyWindow?.delegate as? UnsavedChangesWindowDelegate,
               keyDelegate.model !== model { return }
            if model.hasUnsavedChanges {
                pendingOpenURL = url
            } else {
                Task { await model.openArchive(url: url) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .finderCompressRequest)) { notification in
            guard let userInfo = notification.userInfo,
                  let urls = userInfo["urls"] as? [URL], !urls.isEmpty else { return }
            let action = userInfo["action"] as? String
            if action == "compress-zip" {
                model.creationFormat = .zip
            }
            creationDraft = ArchiveCreationDraft(inputs: urls)
        }
        .task {
            await handleLaunchArguments()
        }
        .modifier(EditNotificationHandler(
            onRemove: removeSelectedEntry,
            onRename: presentRenameAlert,
            onExtractSelected: presentExtractSelectedPanel
        ))
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
            "无法解压缩",
            isPresented: Binding(
                get: { model.extractionErrorMessage != nil },
                set: { if !$0 { model.extractionErrorMessage = nil } }
            )
        ) {
            Button("好") { model.extractionErrorMessage = nil }
        } message: {
            Text(model.extractionErrorMessage ?? "")
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
            Text("请输入新的文件名")
        }
        .alert(
            "此归档有未保存的更改。",
            isPresented: Binding(
                get: { pendingOpenURL != nil },
                set: { if !$0 { pendingOpenURL = nil } }
            )
        ) {
            Button("保存并打开") {
                if let url = pendingOpenURL {
                    pendingOpenURL = nil
                    Task {
                        await model.saveArchive()
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
        .onAppear {
            DispatchQueue.main.async {
                guard let window = NSApp.keyWindow
                    ?? NSApp.windows.first(where: \.isVisible)
                    ?? NSApp.windows.first else { return }
                let localization = AppLocalization()
                let label = localization.string(model.hasDocument ? "Mac解霸" : "欢迎")
                window.setAccessibilityLabel(label)
                window.setAccessibilityIdentifier("ArchiveWorkbenchMainWindow")
                window.titleVisibility = .hidden
                window.contentView?.setAccessibilityLabel(label)
                window.contentView?.setAccessibilityIdentifier("ArchiveWorkbenchMainWindowContent")
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
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                guard ArchiveFileTypes.isSupportedArchive(url) else {
                    model.statusMessage = "不支持的文件类型：\(url.pathExtension)。请拖入 ZIP、7z、RAR、TAR 等压缩包文件。"
                    return
                }
                RecentArchivesManager.shared.noteRecentArchive(url)
                if model.hasUnsavedChanges {
                    pendingOpenURL = url
                } else {
                    Task { await model.openArchive(url: url) }
                }
            }
        }
        return true
    }

    private func handleLaunchArguments() async {
        if let finderAction, let finderFilesPath, !model.hasDocument {
            let paths = (try? String(contentsOfFile: finderFilesPath, encoding: .utf8))?
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init) ?? []
            try? FileManager.default.removeItem(atPath: finderFilesPath)
            if !paths.isEmpty {
                let urls = paths.map { URL(fileURLWithPath: $0) }
                if finderAction == "open", urls.count == 1 {
                    await model.openArchive(url: urls[0])
                } else {
                    if finderAction == "compress-zip" {
                        model.creationFormat = .zip
                    }
                    creationDraft = ArchiveCreationDraft(inputs: urls)
                }
            }
        } else if let initialArchiveURL, !model.hasDocument, !model.isLoading {
            await model.openArchive(url: initialArchiveURL)
        } else if let pendingURL = ArchiveWorkbenchAppDelegate.pendingLaunchURL, !model.hasDocument, !model.isLoading {
            ArchiveWorkbenchAppDelegate.pendingLaunchURL = nil
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
        let panel = NSOpenPanel()
        panel.title = ArchiveCreationCopy.inputPanelTitle()
        panel.prompt = ArchiveCreationCopy.inputPanelPrompt()
        panel.message = ArchiveCreationCopy.inputPanelMessage()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        creationDraft = ArchiveCreationDraft(inputs: panel.urls)
    }

    private func presentCreationSavePanel(_ suggestedFilename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = ArchiveCreationCopy.savePanelTitle()
        panel.prompt = ArchiveCreationCopy.savePanelPrompt()
        panel.message = ArchiveCreationCopy.savePanelMessage()
        panel.nameFieldStringValue = suggestedFilename
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
        Task { await model.removeSelectedEntry() }
    }

    private func presentRenameAlert() {
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

private struct EditNotificationHandler: ViewModifier {
    let onRemove: () -> Void
    let onRename: () -> Void
    let onExtractSelected: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .removeSelectedRequest)) { _ in
                onRemove()
            }
            .onReceive(NotificationCenter.default.publisher(for: .renameSelectedRequest)) { _ in
                onRename()
            }
            .onReceive(NotificationCenter.default.publisher(for: .extractSelectedRequest)) { _ in
                onExtractSelected()
            }
    }
}

private struct CreateArchiveView: View {
    @Bindable var model: AppModel
    @Binding var draft: ArchiveCreationDraft
    let chooseOutput: (String) -> URL?
    let dismiss: () -> Void

    private var passwordsMatch: Bool {
        !model.creationEncryptionEnabled
            || (!model.creationPassword.isEmpty && model.creationPassword == model.creationPasswordConfirm)
    }

    private var canCreate: Bool {
        draft.canCreate && passwordsMatch && !model.isCreating
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
                if model.creationFormat.supportsSplit {
                    splitSection
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
        .frame(width: 700, height: 680)
        .interactiveDismissDisabled(model.isCreating)
        .onChange(of: model.lastCreatedURL) { _, outputURL in
            if outputURL != nil { dismiss() }
        }
        .onAppear {
            if model.creationFormat == .zip {
                model.runPreflight(inputs: draft.inputs)
            }
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
                Text("创建归档")
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
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("格式选择")

                Text(model.creationFormat.capabilityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
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
                        Text(url.deletingLastPathComponent().path)
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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("最快")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("最小")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $model.creationTARCompressionLevel, in: 1...9, step: 1)
                            .accessibilityIdentifier("TAR压缩级别")
                        Text("级别 \(Int(model.creationTARCompressionLevel))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

                    Picker("加密方式", selection: $model.creationEncryptionMethod) {
                        ForEach(EncryptionMethod.allCases, id: \.self) { method in
                            Text(method.displayName).tag(method)
                        }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("加密方式")
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Split Section (ZIP only)

    private var splitSection: some View {
        GroupBox("分卷") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("分卷", isOn: .constant(false))
                    .disabled(true)
                    .accessibilityIdentifier("分卷开关")

                Text("分卷创建功能即将推出")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("分卷状态")
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
                            let sanitized = model.fixPreflightIssues(inputs: draft.inputs)
                            if !sanitized.isEmpty {
                                draft.inputs = sanitized
                            }
                        }
                        .accessibilityIdentifier("自动修正")
                        Button("仍然创建") {
                            model.preflightIssues = []
                        }
                        .accessibilityIdentifier("仍然创建")
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
        switch model.creationFormat {
        case .zip: return "Windows 11 可直接打开"
        case .sevenZip: return "7-Zip / Keka / The Unarchiver 兼容"
        case .rar: return "WinRAR / 7-Zip / Keka 兼容"
        case .tarGz, .tarXz, .tarZst: return "macOS / Linux / Windows (7-Zip) 兼容"
        }
    }

    private var compatibilityDetail: String {
        switch model.creationFormat {
        case .zip:
            return "使用 UTF-8 文件名，自动排除 macOS 元数据；创建前检查 Windows 保留名、非法字符和名称冲突。"
        case .sevenZip:
            return "AES-256 加密，高压缩率；Windows 需 7-Zip 打开，macOS 可用 Keka 或 The Unarchiver。"
        case .rar:
            return "RARLAB 专有格式，广泛兼容；需已安装并授权 RARLAB rar 命令行工具。"
        case .tarGz, .tarXz, .tarZst:
            return "保留 Unix 权限和符号链接；适合 macOS/Linux 分发，Windows 需 7-Zip 解压。"
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
                Text(ArchiveCreationCopy.verificationNote())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("创建归档") {
                    guard let outputURL = draft.outputURL else { return }
                    model.startCreation(at: outputURL, inputs: draft.inputs)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .accessibilityIdentifier("确认创建归档")
            }
        }
    }
}
