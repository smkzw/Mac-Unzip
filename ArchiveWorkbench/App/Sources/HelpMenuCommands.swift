import AppKit
import Foundation
import SwiftUI

// MARK: - Help Menu Commands

struct HelpMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.appModel) private var model: AppModel?

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("MacUnzip 帮助") {
                HelpWindowController.shared.showWindow()
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])

            Divider()

            Button("激活许可证…") { showLicenseActivation() }

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
            Button("关于 MacUnzip") {
                AboutWindowController.shared.showWindow()
            }
        }
    }

    private func showLicenseActivation() {
        if model != nil {
            NotificationCenter.default.post(name: .showLicenseActivationRequest, object: nil)
        } else {
            // No window is open: defer to the next window that appears.
            PendingWindowCommandBox.shared.set(.showLicenseActivation)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Help Window

struct HelpContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MacUnzip 帮助")
                    .font(.title.weight(.semibold))

                GroupBox("快速开始") {
                    VStack(alignment: .leading, spacing: 8) {
                        helpRow(icon: "folder", title: "打开压缩包", detail: "使用 ⌘O 或点击「打开压缩包」按钮，支持 ZIP、7z、RAR、TAR 等格式。")
                        helpRow(icon: "eye", title: "预览文件", detail: "切换到媒体视图（工具栏右侧）可预览图片和文本内容。")
                        helpRow(icon: "arrow.down.doc", title: "解压缩全部", detail: "工具栏「解压缩全部」按钮导出全部内容；选中文件或文件夹后按 ⌘E 或右键「解压选中」仅导出所选项目。")
                        helpRow(icon: "plus.circle", title: "添加文件", detail: "打开压缩包后，使用「添加」按钮向归档中追加文件。")
                        helpRow(icon: "archivebox", title: "新建压缩包", detail: "在欢迎界面点击「新建压缩包」，支持 ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST。")
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("支持的格式") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• ZIP / ZIPX（读写，内置 minizip-ng 引擎，支持 AES-256 加密）")
                        Text("• 7z（读取 + 创建，需安装 7zz）")
                        Text("• RAR（读取，需安装 7zz）")
                        Text("• TAR / TAR.GZ / TAR.BZ2 / TAR.XZ / TAR.ZST（读取 + 创建，含 TGZ、TBZ2、TXZ 等别名）")
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
                        shortcutRow("⇧⌘N", "新建压缩包")
                        shortcutRow("⌘S", "保存")
                        shortcutRow("⇧⌘S", "另存为")
                        shortcutRow("⌘Z", "撤销修改")
                        shortcutRow("⇧⌘Z", "重做修改")
                        shortcutRow("⌘F", "搜索压缩包内容")
                        shortcutRow("⌘E", "解压选中文件")
                        shortcutRow("⌘↓", "打开选中的嵌套压缩包")
                        shortcutRow("⌫", "移除选中文件")
                        shortcutRow("↩", "重命名选中文件")
                        shortcutRow("⌘1", "列表视图")
                        shortcutRow("⌘2", "媒体预览")
                        shortcutRow("⌘I", "显示/隐藏信息面板")
                        shortcutRow("⌘0", "显示/隐藏侧栏")
                        shortcutRow("⇧⌘?", "打开帮助")
                        Text(AppLocalization().string("编辑类快捷键（⌫ 移除、↩ 重命名、⌘Z 撤销、⇧⌘Z 重做）仅对可编辑格式（如 ZIP）有效；7z、RAR、DMG、ISO 及嵌套压缩包为只读。"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MacUnzip 帮助")
    }

    private func helpRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization().string(title))
                    .fontWeight(.medium)
                Text(AppLocalization().string(detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func shortcutRow(_ key: String, _ action: String) -> some View {
        HStack {
            Text(AppLocalization().string(action))
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
        newWindow.title = AppLocalization().string("MacUnzip 帮助")
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
