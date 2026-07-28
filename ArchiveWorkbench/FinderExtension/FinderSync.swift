import Cocoa
import FinderSync
import UniformTypeIdentifiers

@MainActor
class FinderSync: FIFinderSync {
    nonisolated private static let archiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz", "zst", "dmg", "iso",
    ]

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let hasArchives = selectedURLs.contains { Self.archiveExtensions.contains($0.pathExtension.lowercased()) }
        let hasAnyItems = !selectedURLs.isEmpty

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            if hasArchives {
                let extractItem = NSMenuItem(
                    title: "用 Mac解霸 打开",
                    action: #selector(extractWithApp(_:)),
                    keyEquivalent: ""
                )
                extractItem.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
                menu.addItem(extractItem)

                let extractHereItem = NSMenuItem(
                    title: "解压到当前文件夹",
                    action: #selector(extractHere(_:)),
                    keyEquivalent: ""
                )
                extractHereItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                menu.addItem(extractHereItem)

                menu.addItem(.separator())
            }

            if hasAnyItems {
                let compressItem = NSMenuItem(
                    title: "用 Mac解霸 压缩",
                    action: #selector(compressWithApp(_:)),
                    keyEquivalent: ""
                )
                compressItem.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
                menu.addItem(compressItem)

                let zipItem = NSMenuItem(
                    title: "压缩为 ZIP…",
                    action: #selector(compressAsZip(_:)),
                    keyEquivalent: ""
                )
                zipItem.image = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil)
                menu.addItem(zipItem)
            }
        default:
            break
        }
        return menu
    }

    @objc private func extractWithApp(_ sender: AnyObject?) {
        let urls = (FIFinderSyncController.default().selectedItemURLs() ?? [])
            .filter { Self.archiveExtensions.contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else { return }
        launchMainApp(with: urls, action: "open")
    }

    @objc private func extractHere(_ sender: AnyObject?) {
        let urls = (FIFinderSyncController.default().selectedItemURLs() ?? [])
            .filter { Self.archiveExtensions.contains($0.pathExtension.lowercased()) }
        guard !urls.isEmpty else { return }
        launchMainApp(with: urls, action: "extract-here")
    }

    @objc private func compressWithApp(_ sender: AnyObject?) {
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
        let joined = paths.joined(separator: "\0")

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
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempFile.path)

        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["-finder-action", action, "-finder-files", tempFile.path]
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }
}
