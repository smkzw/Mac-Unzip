import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Keys

enum SettingsKeys {
    // General
    static let defaultViewMode = "settings.general.defaultViewMode"
    static let defaultLanguage = "settings.general.defaultLanguage"
    static let showInDock = "settings.general.showInDock"
    static let recentArchivesCount = "settings.general.recentArchivesCount"

    // Extraction
    static let extractionDestination = "settings.extraction.destination"
    static let extractionConflictStrategy = "settings.extraction.conflictStrategy"
    static let preserveTimestamps = "settings.extraction.preserveTimestamps"
    static let excludeMacOSMetadataExtraction = "settings.extraction.excludeMacOSMetadata"

    // Creation
    static let defaultFormat = "settings.creation.defaultFormat"
    static let compressionLevel = "settings.creation.compressionLevel"
    static let excludeMacOSMetadataCreation = "settings.creation.excludeMacOSMetadata"
    static let windowsCompatibilityMode = "settings.creation.windowsCompatibilityMode"

    // Compatibility
    static let windowsFilenameChecks = "settings.compatibility.windowsFilenameChecks"
    static let legacyEncodingDetection = "settings.compatibility.legacyEncodingDetection"

    // Privacy
    static let diagnosticDataCollection = "settings.privacy.diagnosticDataCollection"
    static let cacheSizeLimit = "settings.privacy.cacheSizeLimit"

    // Advanced
    static let verboseLogging = "settings.advanced.verboseLogging"
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            ExtractionSettingsTab()
                .tabItem { Label("解压", systemImage: "arrow.down.doc") }
            CreationSettingsTab()
                .tabItem { Label("创建", systemImage: "archivebox") }
            CompatibilitySettingsTab()
                .tabItem { Label("兼容性", systemImage: "checkmark.shield") }
            ProviderSettingsTab()
                .tabItem { Label("Provider", systemImage: "puzzlepiece.extension") }
            PrivacySettingsTab()
                .tabItem { Label("隐私", systemImage: "hand.raised") }
            AdvancedSettingsTab()
                .tabItem { Label("高级", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage(SettingsKeys.defaultViewMode) private var defaultViewMode = "list"
    @AppStorage(SettingsKeys.defaultLanguage) private var defaultLanguage = "system"
    @AppStorage(SettingsKeys.showInDock) private var showInDock = true
    @AppStorage(SettingsKeys.recentArchivesCount) private var recentArchivesCount = 10

    var body: some View {
        Form {
            Picker("默认视图模式", selection: $defaultViewMode) {
                Text("列表").tag("list")
                Text("媒体预览").tag("media")
            }
            .pickerStyle(.segmented)

            Picker("默认语言", selection: $defaultLanguage) {
                Text("跟随系统").tag("system")
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
            }

            Toggle("在 Dock 中显示", isOn: $showInDock)

            Picker("最近打开的压缩包", selection: $recentArchivesCount) {
                Text("无").tag(0)
                Text("5 个").tag(5)
                Text("10 个").tag(10)
                Text("20 个").tag(20)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Extraction Tab

struct ExtractionSettingsTab: View {
    @AppStorage(SettingsKeys.extractionDestination) private var destination = "ask"
    @AppStorage(SettingsKeys.extractionConflictStrategy) private var conflictStrategy = "ask"
    @AppStorage(SettingsKeys.preserveTimestamps) private var preserveTimestamps = true
    @AppStorage(SettingsKeys.excludeMacOSMetadataExtraction) private var excludeMetadata = true

    var body: some View {
        Form {
            Picker("默认解压位置", selection: $destination) {
                Text("每次询问").tag("ask")
                Text("与归档同目录").tag("same")
                Text("桌面").tag("desktop")
                Text("自定义…").tag("custom")
            }

            Picker("文件冲突策略", selection: $conflictStrategy) {
                Text("不覆盖").tag("skip")
                Text("覆盖").tag("overwrite")
                Text("每次询问").tag("ask")
            }

            Toggle("保留文件时间戳", isOn: $preserveTimestamps)

            Toggle("排除 macOS 元数据（.DS_Store、._*、__MACOSX）", isOn: $excludeMetadata)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Creation Tab

struct CreationSettingsTab: View {
    @AppStorage(SettingsKeys.defaultFormat) private var defaultFormat = "zip"
    @AppStorage(SettingsKeys.compressionLevel) private var compressionLevel = "default"
    @AppStorage(SettingsKeys.excludeMacOSMetadataCreation) private var excludeMetadata = true
    @AppStorage(SettingsKeys.windowsCompatibilityMode) private var windowsCompat = true

    var body: some View {
        Form {
            Picker("默认格式", selection: $defaultFormat) {
                Text("ZIP").tag("zip")
            }
            .pickerStyle(.segmented)

            Picker("压缩级别", selection: $compressionLevel) {
                Text("最快").tag("fastest")
                Text("默认").tag("default")
                Text("最小").tag("smallest")
            }
            .pickerStyle(.segmented)

            Toggle("排除 macOS 元数据", isOn: $excludeMetadata)

            Toggle("Windows 兼容模式", isOn: $windowsCompat)

            Text("开启后自动检查 Windows 保留名、非法字符和路径长度限制。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Compatibility Tab

struct CompatibilitySettingsTab: View {
    @AppStorage(SettingsKeys.windowsFilenameChecks) private var windowsFilenameChecks = true
    @AppStorage(SettingsKeys.legacyEncodingDetection) private var legacyEncoding = "auto"

    var body: some View {
        Form {
            Section {
                Toggle("Windows 文件名检查", isOn: $windowsFilenameChecks)

                Text("检查保留名（CON、PRN 等）、非法字符和大小写冲突。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("旧版编码检测", selection: $legacyEncoding) {
                    Text("自动").tag("auto")
                    Text("UTF-8").tag("utf8")
                    Text("GBK").tag("gbk")
                    Text("Shift-JIS").tag("shiftjis")
                }

                Text("用于读取非 UTF-8 编码创建的旧压缩包中的文件名。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("跨平台验证提示")
                            .fontWeight(.medium)
                        Text("创建归档时会自动验证文件名在 Windows、macOS 和 Linux 上的兼容性。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Provider Tab

struct ProviderSettingsTab: View {
    var body: some View {
        Form {
            Section("已检测的 Provider") {
                providerRow(
                    name: "MinizipNG",
                    role: "ZIP 读写引擎（内嵌）",
                    status: "可用",
                    path: "内嵌于应用",
                    version: "4.0.x"
                )
                providerRow(
                    name: "7zz",
                    role: "7z / RAR 读取",
                    status: sevenZZStatus,
                    path: sevenZZPath,
                    version: sevenZZVersion
                )
                providerRow(
                    name: "RARLAB rar",
                    role: "RAR 创建（外部）",
                    status: rarlabStatus,
                    path: rarlabPath,
                    version: rarlabVersion
                )
                providerRow(
                    name: "libarchive",
                    role: "tar / gz / xz / ISO",
                    status: "可用",
                    path: "系统内嵌",
                    version: "系统版本"
                )
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var sevenZZPath: String {
        let candidates = [
            "/opt/homebrew/bin/7zz",
            "/usr/local/bin/7zz",
            "/usr/bin/7zz",
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return "未检测到"
    }

    private var sevenZZStatus: String {
        sevenZZPath == "未检测到" ? "未安装" : "可用"
    }

    private var sevenZZVersion: String {
        sevenZZPath == "未检测到" ? "—" : "已安装"
    }

    private var rarlabPath: String {
        let candidates = [
            "/opt/homebrew/bin/rar",
            "/usr/local/bin/rar",
            "/usr/bin/rar",
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return "未安装"
    }

    private var rarlabStatus: String {
        rarlabPath == "未安装" ? "未安装" : "可用"
    }

    private var rarlabVersion: String {
        rarlabPath == "未安装" ? "—" : "已安装"
    }

    private func providerRow(
        name: String,
        role: String,
        status: String,
        path: String,
        version: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                Text(role)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(status == "可用" ? .green : .secondary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if version != "—" {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Privacy Tab

struct PrivacySettingsTab: View {
    @AppStorage(SettingsKeys.diagnosticDataCollection) private var diagnosticCollection = false
    @AppStorage(SettingsKeys.cacheSizeLimit) private var cacheSizeLimit = 512
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section {
                Toggle("收集诊断数据", isOn: $diagnosticCollection)

                Text("所有数据仅存储在本地，不会通过网络发送。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("预览缓存上限", selection: $cacheSizeLimit) {
                    Text("128 MB").tag(128)
                    Text("256 MB").tag(256)
                    Text("512 MB").tag(512)
                    Text("1 GB").tag(1024)
                }

                HStack {
                    Button("清除预览缓存") {
                        clearPreviewCache()
                    }
                    if cacheCleared {
                        Text("已清除")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func clearPreviewCache() {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacUnzip", isDirectory: true)
            .appendingPathComponent("PreviewCache", isDirectory: true)
        if let cacheRoot {
            try? FileManager.default.removeItem(at: cacheRoot)
        }
        cacheCleared = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            cacheCleared = false
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @AppStorage(SettingsKeys.verboseLogging) private var verboseLogging = false
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section {
                Toggle("启用详细日志", isOn: $verboseLogging)

                Text("记录 provider 调用细节，用于排查问题。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("导出诊断信息（已脱敏）") {
                    exportDiagnostics()
                }
            }

            Section("构建信息") {
                LabeledContent("版本") {
                    Text(buildVersion)
                }
                LabeledContent("架构") {
                    Text(architecture)
                }
                LabeledContent("系统") {
                    Text(osVersion)
                }
            }

            Section {
                Button("恢复默认设置", role: .destructive) {
                    showResetConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .confirmationDialog(
            "确认恢复默认设置？",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复默认", role: .destructive) {
                resetAllSettings()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作将清除所有自定义设置，无法撤销。")
        }
    }

    private var buildVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "导出诊断信息"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "MacUnzip-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var report = "Mac Unzip 诊断报告\n"
        report += "========================\n\n"
        report += "版本: \(buildVersion)\n"
        report += "架构: \(architecture)\n"
        report += "系统: \(osVersion)\n"
        report += "日期: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        report += "Provider 状态:\n"
        report += "  MinizipNG: 内嵌\n"
        report += "  libarchive: 系统内嵌\n"
        report += "  7zz: \(sevenZZDetected ? "已安装" : "未安装")\n"
        report += "  RARLAB rar: \(rarlabDetected ? "已安装" : "未安装")\n"
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }

    private var sevenZZDetected: Bool {
        let candidates = ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/usr/bin/7zz"]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private var rarlabDetected: Bool {
        let candidates = ["/opt/homebrew/bin/rar", "/usr/local/bin/rar", "/usr/bin/rar"]
        return candidates.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func resetAllSettings() {
        let defaults = UserDefaults.standard
        let keys = [
            SettingsKeys.defaultViewMode,
            SettingsKeys.defaultLanguage,
            SettingsKeys.showInDock,
            SettingsKeys.recentArchivesCount,
            SettingsKeys.extractionDestination,
            SettingsKeys.extractionConflictStrategy,
            SettingsKeys.preserveTimestamps,
            SettingsKeys.excludeMacOSMetadataExtraction,
            SettingsKeys.defaultFormat,
            SettingsKeys.compressionLevel,
            SettingsKeys.excludeMacOSMetadataCreation,
            SettingsKeys.windowsCompatibilityMode,
            SettingsKeys.windowsFilenameChecks,
            SettingsKeys.legacyEncodingDetection,
            SettingsKeys.diagnosticDataCollection,
            SettingsKeys.cacheSizeLimit,
            SettingsKeys.verboseLogging,
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
