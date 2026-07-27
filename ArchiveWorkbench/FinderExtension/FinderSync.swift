import Cocoa
import FinderSync

@MainActor
class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            let item = NSMenuItem(
                title: "用 Mac解霸 压缩",
                action: #selector(compressWithArchiveWorkbench(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
            menu.addItem(item)

            let zipItem = NSMenuItem(
                title: "压缩为 ZIP…",
                action: #selector(compressAsZip(_:)),
                keyEquivalent: ""
            )
            zipItem.image = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil)
            menu.addItem(zipItem)
        default:
            break
        }
        return menu
    }

    @objc private func compressWithArchiveWorkbench(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else { return }
        launchMainApp(with: urls, action: "compress")
    }

    @objc private func compressAsZip(_ sender: AnyObject?) {
        let urls = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !urls.isEmpty else { return }
        launchMainApp(with: urls, action: "compress-zip")
    }

    private func launchMainApp(with urls: [URL], action: String) {
        let paths = urls.map { $0.path }
        let joined = paths.joined(separator: "\n")

        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.smkzw.ArchiveWorkbench")
        if !runningApps.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.smkzw.ArchiveWorkbench.finderRequest"),
                object: nil,
                userInfo: ["action": action, "paths": joined],
                deliverImmediately: true
            )
            runningApps.first?.activate()
            return
        }

        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.smkzw.ArchiveWorkbench")
        guard let appURL else {
            let alert = NSAlert()
            alert.messageText = "未找到 Mac解霸"
            alert.informativeText = "请确认 Mac解霸 已安装在「应用程序」文件夹中。"
            alert.runModal()
            return
        }

        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw_finder_\(ProcessInfo.processInfo.globallyUniqueString).txt")
        try? joined.write(to: tempFile, atomically: true, encoding: .utf8)

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["-finder-action", action, "-finder-files", tempFile.path]
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }
}
