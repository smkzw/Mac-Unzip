import AppKit
import Foundation
import SwiftUI

// MARK: - Help Menu Commands

struct HelpMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Mac解霸帮助") {
                HelpWindowController.shared.showWindow()
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])

            Divider()

            Button("组件与许可证…") {
                ComponentsLicensesWindowController.shared.showWindow()
            }

            Button("格式支持状态") {
                ProviderStatusWindowController.shared.showWindow()
            }

            Divider()

            Button("导出诊断信息…") {
                DiagnosticsExporter.exportToFile()
            }
        }
        CommandGroup(replacing: .appInfo) {
            Button("关于 Mac解霸") {
                AboutWindowController.shared.showWindow()
            }
        }
    }
}

// MARK: - Help Window

struct HelpContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mac解霸帮助")
                    .font(.title.weight(.semibold))

                GroupBox("快速开始") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpRow(icon: "folder", title: "打开压缩包", detail: "使用 ⌘O 或点击「打开压缩包」按钮，支持 ZIP、7z、RAR、TAR 等格式。")
                        helpRow(icon: "eye", title: "预览文件", detail: "在文件列表中单击条目即可预览内容。")
                        helpRow(icon: "arrow.down.doc", title: "解压", detail: "选择文件后点击工具栏「解压」按钮导出到指定目录。")
                        helpRow(icon: "plus.circle", title: "添加文件", detail: "打开压缩包后，使用「添加」按钮向归档中追加文件。")
                        helpRow(icon: "archivebox", title: "创建归档", detail: "在欢迎界面点击「创建归档」，支持 ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST。")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("支持的格式") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• ZIP（读写，内置 minizip-ng 引擎，支持 AES-256 加密）")
                        Text("• 7z（读取 + 创建，需安装 7zz）")
                        Text("• RAR（读取 + 创建，需安装 7zz 或 rar）")
                        Text("• TAR.GZ / TAR.XZ / TAR.ZST（读取 + 创建）")
                        Text("• DMG / ISO（只读）")
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                }

                GroupBox("安全说明") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• 所有解压操作均经过路径安全检查，防止路径穿越攻击。")
                        Text("• 预览文件有大小限制，防止内存溢出。")
                        Text("• 诊断信息导出已脱敏，不包含用户路径或敏感数据。")
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                }

                GroupBox("快捷键") {
                    VStack(alignment: .leading, spacing: 6) {
                        shortcutRow("⌘O", "打开压缩包")
                        shortcutRow("⇧⌘N", "新建归档")
                        shortcutRow("⌘S", "保存")
                        shortcutRow("⇧⌘S", "另存为")
                        shortcutRow("⌘Z", "撤销修改")
                        shortcutRow("⌘F", "搜索压缩包内容")
                        shortcutRow("⌘E", "解压选中文件")
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mac解霸帮助")
    }

    private func helpRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        HStack {
            Text(action)
            Spacer()
            Text(key)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Help Window Controller

@MainActor
final class HelpWindowController: NSObject, NSWindowDelegate {
    static let shared = HelpWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: HelpContentView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Mac解霸帮助"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 480, height: 400)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
