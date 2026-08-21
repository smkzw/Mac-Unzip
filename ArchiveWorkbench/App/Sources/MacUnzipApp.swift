import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Inline constant definitions (moved from UIConstants.swift due to module visibility)
struct MacUnzipUIConstants {
    static let defaultWindowWidth: CGFloat = 1180
    static let defaultWindowHeight: CGFloat = 760
}

/// Lets the AppKit delegate open a new main window from outside SwiftUI.
/// `openWindow` is captured by `RootWindowView` on appear and stays valid for
/// the app's lifetime, so it can reopen a window after all are closed.
@MainActor
enum MainAppWindowOpener {
    static var openWindow: OpenWindowAction?

    static func openMainWindow() {
        // 复用已有主窗口：WindowGroup 的 openWindow 每次调用会开新窗口，
        // 双击/Finder 反复打开会堆积多个窗口，拖拽时内容窗口被淹没。
        if let existing = NSApp.windows.first(where: { $0.delegate is UnsavedChangesWindowDelegate }) {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        openWindow?(id: "main")
        // 冷启动时 openWindow 尚未注入可能为 nil，窗口由 SwiftUI 创建但不会
        // 自动前置；显式激活并置前，保证双击/Finder 打开时窗口到最前。
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.delegate is UnsavedChangesWindowDelegate }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
final class MacUnzipAppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ArchiveServiceProvider()

    /// URL from application(_:openURLs:) that arrived before the view subscribed.
    static var pendingLaunchURL: URL?

    /// Count of archives skipped when a multi-open request opens only the first.
    static var pendingSkippedOpenCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        try? FileManager.default.removeItem(at: ValidatedPreviewCacheURL.cacheRoot)
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("MacUnzipExternal", isDirectory: true)
        )
        cleanStaleFinderTempFiles()
        StaleCopyTempStore.sweep()
        handleLaunchArguments()
        registerFinderIPC()
    }

    private func registerFinderIPC() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderRequest(_:)),
            name: NSNotification.Name("com.smkzw.MacUnzip.finderRequest"),
            object: nil
        )
    }

    @objc private func handleFinderRequest(_ notification: Notification) {
        // SECURITY: DistributedNotificationCenter is unauthenticated; any process running
        // as the current user can post this notification. We require the Finder extension
        // process to actually be running before honoring a request — a running-process
        // check cannot be spoofed by an unrelated app. This blocks opportunistic IPC from
        // processes that are not the extension. It does NOT fully defend against a
        // malicious process running as the same user (which could coexist with a running
        // extension); the complete fix is an authenticated XPC connection, which is the
        // documented upgrade path. Downstream, LicenseGate + confirmation alerts still
        // mediate any privileged action.
        let extensionRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.smkzw.MacUnzip.finder-extension"
        ).isEmpty
        guard extensionRunning else { return }

        guard let userInfo = notification.userInfo,
              let pathsString = userInfo["paths"] as? String else { return }
        let action = userInfo["action"] as? String ?? "compress"
        let paths = pathsString.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
        if action == "open" {
            // Multi-selection open: open the first archive, matching
            // application(_:open urls:) which also honors urls.first.
            Self.deliverOpenURL(urls[0], skippedCount: max(0, urls.count - 1))
        } else {
            NotificationCenter.default.post(
                name: .finderCompressRequest,
                object: nil,
                userInfo: ["urls": urls, "action": action]
            )
        }
    }

    private func cleanStaleFinderTempFiles() {
        let currentFinderFile: String? = {
            let args = ProcessInfo.processInfo.arguments
            guard let index = args.firstIndex(of: "-finder-files"), index + 1 < args.count else { return nil }
            return args[index + 1]
        }()
        let tmpDir = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("aw_finder_") && file.pathExtension == "txt" {
            if file.path == currentFinderFile { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func handleLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        // 深链激活：`MacUnzip -activate-license <key>`（官网/邮件引导与 E2E 共用）。
        if let i = args.firstIndex(of: "-activate-license"), i + 1 < args.count {
            _ = LicenseManager.shared.activateLicense(key: args[i + 1])
        }
        guard let filesIndex = args.firstIndex(of: "-finder-files"),
              filesIndex + 1 < args.count else { return }
        let tempPath = args[filesIndex + 1]
        let action: String = {
            guard let actionIndex = args.firstIndex(of: "-finder-action"),
                  actionIndex + 1 < args.count else { return "open" }
            return args[actionIndex + 1]
        }()
        guard let data = FileManager.default.contents(atPath: tempPath) else { return }
        // Graceful fallback for non-UTF-8 encoded paths from Finder IPC
        let pathsString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) ?? ""
        let paths = pathsString.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
        if action == "open" {
            guard let first = urls.first else { return }
            // RootWindowView parses these same -finder-* arguments and owns the
            // open (deleting the temp file and surfacing the skipped count). Do
            // not post .openArchiveURL here: a live window would open the archive
            // a second time. Just record recency.
            RecentArchivesManager.shared.noteRecentArchive(first)
        } else {
            NotificationCenter.default.post(
                name: .finderCompressRequest,
                object: nil,
                userInfo: ["urls": urls, "action": action]
            )
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let unsavedDelegates = sender.windows.compactMap { window -> UnsavedChangesWindowDelegate? in
            guard let delegate = window.delegate as? UnsavedChangesWindowDelegate,
                  delegate.model.hasUnsavedChanges else { return nil }
            return delegate
        }
        guard !unsavedDelegates.isEmpty else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = AppLocalization().string("此归档有未保存的更改")
        alert.informativeText = AppLocalization().string("如果不保存，所做的修改将会丢失。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLocalization().string("保存"))
        alert.addButton(withTitle: AppLocalization().string("不保存"))
        alert.addButton(withTitle: AppLocalization().string("取消"))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                for d in unsavedDelegates {
                    await d.model.saveArchiveResolvingNested()
                }
                let allSaved = unsavedDelegates.allSatisfy { !$0.model.hasUnsavedChanges }
                sender.reply(toApplicationShouldTerminate: allSaved)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: ValidatedPreviewCacheURL.cacheRoot)
        try? FileManager.default.removeItem(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("MacUnzipExternal", isDirectory: true)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        let skipped = max(0, urls.count - 1)
        // 无论 active 与否都走 deliverOpenURL：app 在运行但主窗口已关闭时，
        // 它会开新窗口并投递 URL；旧实现 inactive 分支只 stash pending 而
        // 无 RootWindowView 消费，导致双击压缩包"毫无反应"。
        Self.deliverOpenURL(url, skippedCount: skipped)
    }

    /// Dock 图标点击（app 在运行但无窗口）：重开主窗口，避免"点了没反应"。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || !Self.hasMainWindow {
            MainAppWindowOpener.openMainWindow()
        }
        return true
    }

    /// 单主窗口 app 的标准行为：最后一个窗口关闭后退出进程。
    /// 根治"app 在运行但无窗口时双击压缩包无反应"——双击将作为新进程
    /// 启动并走 application(_:open:) 启动路径开窗加载归档。未保存更改的
    /// 关窗确认由 UnsavedChangesWindowDelegate.windowShouldClose 先行拦截。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Routes an open-archive request to a live window, or stashes it and opens
    /// a new window when none exists (e.g. app running with all windows closed).
    static func deliverOpenURL(_ url: URL, skippedCount: Int = 0) {
        RecentArchivesManager.shared.noteRecentArchive(url)
        // 统一设 pending + 双通道通知：无论 hasMainWindow 与否都设
        // pendingLaunchURL，供冷启动轮询兜底；post openArchiveURL 供已
        // 挂载视图即时打开（消费时以 pending 去重）。
        pendingLaunchURL = url
        pendingSkippedOpenCount = skippedCount
        NotificationCenter.default.post(
            name: .openArchiveURL,
            object: url,
            userInfo: skippedCount > 0 ? ["skippedCount": skippedCount] : nil
        )
        MainAppWindowOpener.openMainWindow()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pendingOpenRequest, object: nil)
        }
    }

    private static var hasMainWindow: Bool {
        NSApp.windows.contains { $0.delegate is UnsavedChangesWindowDelegate }
    }
}

// MARK: - Close Confirmation

/// Delegate that intercepts window close to confirm discarding unsaved changes.
final class UnsavedChangesWindowDelegate: NSObject, NSWindowDelegate {
    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = AppLocalization().string("此归档有未保存的更改")
        alert.informativeText = AppLocalization().string("如果不保存，所做的修改将会丢失。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLocalization().string("保存"))
        alert.addButton(withTitle: AppLocalization().string("不保存"))
        alert.addButton(withTitle: AppLocalization().string("取消"))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = .command
        alert.buttons[2].keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                await self.model.saveArchiveResolvingNested()
                if !self.model.hasUnsavedChanges {
                    sender.close()
                }
            }
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }
}

/// An NSViewRepresentable that installs an UnsavedChangesWindowDelegate on the
/// hosting window and keeps isDocumentEdited in sync with unsaved changes.
struct WindowCloseHandler: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        view.onWindowChange = { window in
            guard let window else { return }
            if context.coordinator.windowDelegate == nil {
                let delegate = UnsavedChangesWindowDelegate(model: model)
                context.coordinator.windowDelegate = delegate
                window.delegate = delegate
            }
            window.isDocumentEdited = model.hasUnsavedChanges
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if context.coordinator.windowDelegate == nil {
            let delegate = UnsavedChangesWindowDelegate(model: model)
            context.coordinator.windowDelegate = delegate
            window.delegate = delegate
        }
        window.isDocumentEdited = model.hasUnsavedChanges
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var windowDelegate: UnsavedChangesWindowDelegate?
    }
}

private final class WindowObservingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

@main
struct MacUnzipApp: App {
    @NSApplicationDelegateAdaptor(MacUnzipAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") { RootWindowView() }
            .defaultSize(width: MacUnzipUIConstants.defaultWindowWidth, height: MacUnzipUIConstants.defaultWindowHeight)
            .windowToolbarStyle(.unified)
            .commands {
                OpenCreateCommands()
                CommandGroup(after: .saveItem) {
                    SaveCommands()
                }
                CommandGroup(replacing: .undoRedo) {
                    UndoArchiveCommand()
                    RedoArchiveCommand()
                }
                CommandGroup(after: .textEditing) {
                    SearchArchiveCommand()
                }
                EditArchiveCommands()
                ViewNavigationCommands()
                HelpMenuCommands()
            }
        Settings { SettingsView() }
    }
}

// MARK: - Open / Create Commands

struct OpenCreateCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("打开压缩包…") { perform(.openArchive) }
                .keyboardShortcut("o", modifiers: .command)

            Button(AppLocalization().string("新建压缩包…") + proSuffix) { perform(.createArchive) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }

    private var proSuffix: String {
        LicenseManager.shared.isProLicensed ? "" : " · Pro"
    }

    private func perform(_ command: PendingWindowCommand) {
        if model != nil {
            let name: Notification.Name = command == .openArchive
                ? .openArchiveRequest
                : .createArchiveRequest
            NotificationCenter.default.post(name: name, object: nil)
        } else {
            // No window is open: remember the command and open a fresh window,
            // which performs it on appear.
            PendingWindowCommandBox.shared.set(command)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Save / Save As Menu Commands

struct SaveCommands: View {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some View {
        Button("保存") {
            guard let model else { return }
            Task { await model.saveArchive() }
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(model?.hasUnsavedChanges != true || model?.isNestedSession == true)

        Button("另存为…") {
            guard let model else { return }
            presentSaveAsPanel(model: model)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(model?.hasDocument != true || model?.isNestedSession == true)
    }

    private func presentSaveAsPanel(model: AppModel) {
        let panel = NSSavePanel()
        panel.title = AppLocalization().string("另存为")
        panel.prompt = AppLocalization().string("保存")
        panel.nameFieldStringValue = model.documentTitle
        panel.allowedContentTypes = ArchiveFileTypes.contentTypes
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.saveArchiveAs(to: url) }
    }
}

// MARK: - Undo Command

/// Routes the Edit menu undo/redo key equivalents to the focused text editor
/// when one is active, so ⌘Z/⌘⇧Z edit text (search field, rename alert, license
/// or password fields) instead of undoing archive changes. Returns true when
/// the action was handled by a text editor.
@MainActor
enum EditMenuTextRouter {
    static func forwardIfEditingText(_ selector: Selector) -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder,
              responder is NSTextView,
              responder.responds(to: selector) else { return false }
        return responder.tryToPerform(selector, with: nil)
    }
}

struct UndoArchiveCommand: View {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some View {
        Button("撤销修改") {
            if EditMenuTextRouter.forwardIfEditingText(NSSelectorFromString("undo:")) { return }
            guard let model, model.hasUnsavedChanges, !model.isNestedSession else { return }
            Task { await model.undoLastChange() }
        }
        .keyboardShortcut("z", modifiers: .command)
    }
}

struct RedoArchiveCommand: View {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some View {
        Button("重做修改") {
            if EditMenuTextRouter.forwardIfEditingText(NSSelectorFromString("redo:")) { return }
            guard let model, model.canRedo else { return }
            Task { await model.redoLastChange() }
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
    }
}

struct SearchArchiveCommand: View {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some View {
        Button("搜索压缩包内容") {
            NotificationCenter.default.post(name: .focusArchiveSearch, object: nil)
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(model?.hasDocument != true)
    }
}

// MARK: - Edit Archive Commands

struct EditArchiveCommands: Commands {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(AppLocalization().string("移除选中") + proSuffix) {
                NotificationCenter.default.post(name: .removeSelectedRequest, object: nil)
            }
            .disabled(model?.canRemoveSelectedEntry != true)

            Button(AppLocalization().string("重命名…") + proSuffix) {
                NotificationCenter.default.post(name: .renameSelectedRequest, object: nil)
            }
            .disabled(model?.canRenameSelectedEntry != true)

            Divider()

            Button(AppLocalization().string("解压选中…") + proSuffix) {
                NotificationCenter.default.post(name: .extractSelectedRequest, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model?.canExtractSelected != true)
        }
    }

    private var proSuffix: String {
        LicenseManager.shared.isProLicensed ? "" : " · Pro"
    }
}


// MARK: - View Navigation Commands

/// Keyboard navigation for the document shell: Cmd+1/2 switch list/media,
/// Cmd+I toggles the inspector, and Cmd+0 toggles the sidebar.
struct ViewNavigationCommands: Commands {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button(AppLocalization().string("列表视图")) {
                model?.viewMode = .list
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(model?.hasDocument != true)

            Button(AppLocalization().string("媒体预览")) {
                model?.viewMode = .media
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(model?.hasDocument != true)

            Divider()

            Button(AppLocalization().string("信息")) {
                model?.inspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(model?.hasDocument != true)

            Button(AppLocalization().string(model?.sidebarVisible == true ? "隐藏侧栏" : "显示侧栏")) {
                model?.sidebarVisible.toggle()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(model?.hasDocument != true)
        }
    }
}
