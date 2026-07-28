import AppKit
import ArchiveOperations
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ArchiveWorkbenchAppDelegate: NSObject, NSApplicationDelegate {
    private let serviceProvider = ArchiveServiceProvider()

    /// URL from application(_:openURLs:) that arrived before the view subscribed.
    static var pendingLaunchURL: URL?

    /// Journals found during launch scan, before AppModel exists to observe the notification.
    static var pendingRecoveryJournals: [(journalURL: URL, journal: CrashRecoveryJournal)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = serviceProvider
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing") else { return }
        try? FileManager.default.removeItem(at: ValidatedPreviewCacheURL.cacheRoot)
        cleanStaleFinderTempFiles()
        handleLaunchArguments()
        registerFinderIPC()
        scanForCrashRecoveryJournals()
    }

    private func registerFinderIPC() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleFinderRequest(_:)),
            name: NSNotification.Name("com.smkzw.ArchiveWorkbench.finderRequest"),
            object: nil
        )
    }

    @objc private func handleFinderRequest(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let pathsString = userInfo["paths"] as? String else { return }
        let action = userInfo["action"] as? String ?? "compress"
        let paths = pathsString.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
        if action == "open", urls.count == 1 {
            RecentArchivesManager.shared.noteRecentArchive(urls[0])
            NotificationCenter.default.post(name: .openArchiveURL, object: urls[0])
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
        guard let filesIndex = args.firstIndex(of: "-finder-files"),
              filesIndex + 1 < args.count else { return }
        let tempPath = args[filesIndex + 1]
        let action: String = {
            guard let actionIndex = args.firstIndex(of: "-finder-action"),
                  actionIndex + 1 < args.count else { return "open" }
            return args[actionIndex + 1]
        }()
        guard let data = FileManager.default.contents(atPath: tempPath) else { return }
        try? FileManager.default.removeItem(atPath: tempPath)
        let pathsString = String(decoding: data, as: UTF8.self)
        let paths = pathsString.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return }
        if action == "open", urls.count == 1 {
            Self.pendingLaunchURL = urls[0]
            RecentArchivesManager.shared.noteRecentArchive(urls[0])
            NotificationCenter.default.post(name: .openArchiveURL, object: urls[0])
        } else {
            NotificationCenter.default.post(
                name: .finderCompressRequest,
                object: nil,
                userInfo: ["urls": urls, "action": action]
            )
        }
    }

    /// Scans common user directories for unfinished crash-recovery journals
    /// and posts Notification/Name/crashRecoveryJournalsFound if any are
    /// discovered. Recovery is never automatic; the UI presents the user with
    /// a choice to recover or discard.
    private func scanForCrashRecoveryJournals() {
        let searchDirectories = [
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
        let unfinished = CrashRecoveryJournalStore.scanForUnfinishedJournals(in: searchDirectories)
        guard !unfinished.isEmpty else { return }
        Self.pendingRecoveryJournals = unfinished
        NotificationCenter.default.post(
            name: .crashRecoveryJournalsFound,
            object: unfinished
        )
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
        alert.messageText = AppLocalization().string("此归档有未保存的更改。")
        alert.informativeText = AppLocalization().string("如果不保存，所做的修改将会丢失。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLocalization().string("保存"))
        alert.addButton(withTitle: AppLocalization().string("不保存"))
        alert.addButton(withTitle: AppLocalization().string("取消"))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                for d in unsavedDelegates {
                    await d.model.saveArchive()
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
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        RecentArchivesManager.shared.noteRecentArchive(url)
        if application.isActive {
            NotificationCenter.default.post(name: .openArchiveURL, object: url)
        } else {
            Self.pendingLaunchURL = url
        }
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
        alert.messageText = AppLocalization().string("此归档有未保存的更改。")
        alert.informativeText = AppLocalization().string("如果不保存，所做的修改将会丢失。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLocalization().string("保存"))
        alert.addButton(withTitle: AppLocalization().string("不保存"))
        alert.addButton(withTitle: AppLocalization().string("取消"))
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = "\u{1b}"
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task { @MainActor in
                await self.model.saveArchive()
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
struct ArchiveWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(ArchiveWorkbenchAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { RootWindowView() }
            .defaultSize(width: 1180, height: 760)
            .windowToolbarStyle(.unified(showsTitle: false))
            .commands {
                CommandGroup(after: .newItem) {
                    Button("打开压缩包…") {
                        NotificationCenter.default.post(name: .openArchiveRequest, object: nil)
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Button("新建压缩包…") {
                        NotificationCenter.default.post(name: .createArchiveRequest, object: nil)
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                CommandGroup(after: .saveItem) {
                    SaveCommands()
                }
                CommandGroup(replacing: .undoRedo) {
                    UndoArchiveCommand()
                }
                CommandGroup(after: .textEditing) {
                    Button("搜索压缩包内容") {
                        NotificationCenter.default.post(name: .focusArchiveSearch, object: nil)
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
                EditArchiveCommands()
                ViewNavigationCommands()
                HelpMenuCommands()
            }
        Settings { SettingsView() }
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
        .disabled(model?.hasUnsavedChanges != true)

        Button("另存为…") {
            guard let model else { return }
            presentSaveAsPanel(model: model)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(model?.hasDocument != true)
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

struct UndoArchiveCommand: View {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some View {
        Button("撤销修改") {
            guard let model else { return }
            Task { await model.undoLastChange() }
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(model?.hasUnsavedChanges != true)
    }
}

// MARK: - Edit Archive Commands

struct EditArchiveCommands: Commands {
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button(AppLocalization().string("移除选中")) {
                NotificationCenter.default.post(name: .removeSelectedRequest, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(model?.canRemoveSelectedEntry != true)

            Button(AppLocalization().string("重命名…")) {
                NotificationCenter.default.post(name: .renameSelectedRequest, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(model?.canRenameSelectedEntry != true)

            Divider()

            Button(AppLocalization().string("解压选中…")) {
                NotificationCenter.default.post(name: .extractSelectedRequest, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model?.canExtractSelected != true)
        }
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
