import AppKit
import ArchiveProviders
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Keys

enum SettingsKeys {
    // General
    static let recentArchivesCount = "settings.general.recentArchivesCount"
    // Extraction
    static let extractionDestination = "settings.extraction.destination"
    static let extractionConflictStrategy = "settings.extraction.conflictStrategy"
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("通用", systemImage: "gearshape") }
            ExtractionSettingsTab()
                .tabItem { Label("解压", systemImage: "arrow.down.doc") }
            ProviderSettingsTab()
                .tabItem { Label("引擎", systemImage: "puzzlepiece.extension") }
            AdvancedSettingsTab()
                .tabItem { Label("高级", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage(SettingsKeys.recentArchivesCount) private var recentArchivesCount = 10
    @State private var isDefaultHandler = false

    private static let archiveUTIs = [
        "public.zip-archive",
        "org.7-zip.7-zip-archive",
        "com.rarlab.rar-archive",
        "public.tar-archive",
        "public.gzip-archive",
    ]

    var body: some View {
        Form {
            Picker("最近打开的压缩包", selection: $recentArchivesCount) {
                Text("无").tag(0)
                Text("5 个").tag(5)
                Text("10 个").tag(10)
                Text("20 个").tag(20)
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("默认解压缩软件")
                        Text(isDefaultHandler ? "Mac解霸 已是默认解压缩工具" : "设为默认后，双击压缩包将自动用 Mac解霸 打开")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isDefaultHandler {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("设为默认") { setAsDefaultHandler() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear { checkDefaultHandler() }
    }

    private func checkDefaultHandler() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        isDefaultHandler = Self.archiveUTIs.allSatisfy { uti in
            guard let handler = LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)?.takeRetainedValue() else {
                return false
            }
            return handler as String == bundleID
        }
    }

    private func setAsDefaultHandler() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let bundleCF = bundleID as CFString
        for uti in Self.archiveUTIs {
            LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleCF)
        }
        checkDefaultHandler()
    }
}

// MARK: - Extraction Tab

struct ExtractionSettingsTab: View {
    @AppStorage(SettingsKeys.extractionDestination) private var destination = "ask"

    var body: some View {
        Form {
            Picker("默认解压位置", selection: $destination) {
                Text("每次询问").tag("ask")
                Text("与归档同目录").tag("same")
                Text("桌面").tag("desktop")
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Provider Tab

struct ProviderSettingsTab: View {
    @State private var cachedDiscovery: SevenZipBinaryDiscovery?
    @State private var discoveryLoaded = false

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
        .task {
            guard !discoveryLoaded else { return }
            discoveryLoaded = true
            cachedDiscovery = SevenZipBinaryDiscovery.discover()
        }
    }

    private var sevenZZPath: String {
        cachedDiscovery?.resolvedPath ?? "未检测到"
    }

    private var sevenZZStatus: String {
        cachedDiscovery != nil ? "可用" : "未安装"
    }

    private var sevenZZVersion: String {
        cachedDiscovery?.version ?? "—"
    }

    private var rarlabPath: String {
        let candidates = [
            "/opt/homebrew/bin/rar",
            "/usr/local/bin/rar",
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

// MARK: - Advanced Tab

struct AdvancedSettingsTab: View {
    @State private var showResetConfirmation = false
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section {
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
            SettingsKeys.recentArchivesCount,
            SettingsKeys.extractionDestination,
            "appearanceMode",
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
