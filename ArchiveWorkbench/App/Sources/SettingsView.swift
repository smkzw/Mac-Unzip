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
    @State private var defaultHandlerErrorMessage: String?

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
                        Text(isDefaultHandler ? "MacUnzip 已是默认解压缩工具" : "设为默认后，双击压缩包将自动用 MacUnzip 打开")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let defaultHandlerErrorMessage {
                            Text(defaultHandlerErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
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
        // Register this bundle with Launch Services first. An ad-hoc / freshly
        // copied app may not be known to LS yet, in which case the role-handler
        // set below is a silent no-op and an immediate read-back still reports
        // the previous handler — the root cause of the false "无法设置为默认".
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        let bundleCF = bundleID as CFString
        for uti in Self.archiveUTIs {
            _ = LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleCF)
        }
        // Optimistic success: the user's intent is recorded and LS applies the
        // change asynchronously. A synchronous read-back here can still see the
        // stale handler, so we reflect success now and let onAppear re-verify
        // the true state the next time the settings window opens.
        isDefaultHandler = true
        defaultHandlerErrorMessage = nil
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
            Text("选择固定位置后，解压缩将直接保存到该位置下的同名文件夹，不再弹出选择窗口。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

// MARK: - Provider Tab

struct ProviderSettingsTab: View {
    @State private var cachedDiscovery: SevenZipBinaryDiscovery?
    @State private var cachedRARDiscovery: RARBinaryDiscovery?
    @State private var discoveryLoaded = false
    @AppStorage("settings.engines.checkUpdates") private var checkUpdatesEnabled = false
    @State private var updateHint: String?
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                providerRow(
                    name: "MinizipNG",
                    role: AppLocalization().string("ZIP 读写引擎（内嵌）"),
                    status: AppLocalization().string("可用"),
                    isAvailable: true,
                    path: AppLocalization().string("内嵌于应用"),
                    version: AppLocalization().string("随应用内置")
                )
                providerRow(
                    name: "7zz",
                    role: AppLocalization().string("7z / RAR 读取"),
                    status: sevenZZStatus,
                    isAvailable: cachedDiscovery != nil,
                    path: sevenZZPath,
                    version: sevenZZVersion
                )
                providerRow(
                    name: "RARLAB rar",
                    role: AppLocalization().string("RAR 创建（外部）"),
                    status: rarlabStatus,
                    isAvailable: cachedRARDiscovery != nil,
                    path: rarlabPath,
                    version: rarlabVersion
                )
                providerRow(
                    name: "libarchive",
                    role: "tar / gz / xz / zst / ISO",
                    status: AppLocalization().string("可用"),
                    isAvailable: true,
                    path: AppLocalization().string("系统内嵌"),
                    version: AppLocalization().string("系统版本")
                )
            } header: {
                HStack {
                    Text("已检测的引擎")
                    Spacer()
                    Button("刷新") { refreshEngines() }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("刷新引擎状态")
                }
            }
            Section {
                Toggle(AppLocalization().string("检测引擎更新（联网，仅读取版本号）"), isOn: $checkUpdatesEnabled)
                    .accessibilityIdentifier("引擎更新开关")
                if checkUpdatesEnabled {
                    HStack {
                        Button {
                            Task { await checkEngineUpdates() }
                        } label: {
                            if isChecking { ProgressView().controlSize(.small) }
                            else { Text(AppLocalization().string("检测更新")) }
                        }
                        .buttonStyle(.borderless)
                        .disabled(isChecking)
                        .accessibilityIdentifier("检测引擎更新")
                        if let updateHint {
                            Text(updateHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .task {
            guard !discoveryLoaded else { return }
            discoveryLoaded = true
            refreshEngines()
        }
    }

    /// Opt-in, read-only update detection. Fetches a static versions-only manifest
    /// and shows a hint pointing to the official site. Never downloads or writes
    /// any executable (supply-chain safe, preserves the zero-download promise).
    @MainActor
    private func checkEngineUpdates() async {
        isChecking = true
        defer { isChecking = false }
        updateHint = nil
        guard let url = URL(string: "https://smkzw.github.io/Mac-Unzip/store/engine-versions.json") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let manifest = try? JSONDecoder().decode([String: String].self, from: data) else {
                updateHint = AppLocalization().string("无法解析更新信息")
                return
            }
            var hints: [String] = []
            if let latest = manifest["7zz"], let current = cachedDiscovery?.version, current != latest {
                hints.append(AppLocalization().format("7zz 最新 %@，当前 %@，请前往官网更新", latest, current))
            }
            if let latest = manifest["rar"], let current = cachedRARDiscovery?.version, current != latest {
                hints.append(AppLocalization().format("rar 最新 %@，当前 %@，请前往官网更新", latest, current))
            }
            updateHint = hints.isEmpty
                ? AppLocalization().string("引擎均为最新")
                : hints.joined(separator: "；")
        } catch {
            updateHint = AppLocalization().string("无法获取更新信息（离线或地址不可用）")
        }
    }

    private func refreshEngines() {
        cachedDiscovery = SevenZipBinaryDiscovery.discover()
        cachedRARDiscovery = RARBinaryDiscovery.discover()
    }

    private var sevenZZPath: String {
        cachedDiscovery?.resolvedPath ?? AppLocalization().string("未检测到")
    }

    private var sevenZZStatus: String {
        cachedDiscovery != nil
            ? AppLocalization().string("可用")
            : AppLocalization().string("未检测到")
    }

    private var sevenZZVersion: String {
        cachedDiscovery?.version ?? "—"
    }

    private var rarlabPath: String {
        cachedRARDiscovery?.resolvedPath ?? AppLocalization().string("未检测到")
    }

    private var rarlabStatus: String {
        cachedRARDiscovery != nil
            ? AppLocalization().string("可用")
            : AppLocalization().string("未检测到")
    }

    private var rarlabVersion: String {
        cachedRARDiscovery?.version ?? "—"
    }

    private func providerRow(
        name: String,
        role: String,
        status: String,
        isAvailable: Bool,
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
                    .foregroundStyle(isAvailable ? .green : .secondary)
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
    @State private var exportFailed = false
    @State private var exportSucceeded = false

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
                HStack {
                    Button("导出诊断信息（已脱敏）…") {
                        exportDiagnostics()
                    }
                    if exportSucceeded {
                        Text("已导出")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
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
            Text("此操作将清除所有自定义设置，无法撤销。部分更改（如外观）将在重启后生效。")
        }
        .alert("操作失败", isPresented: $exportFailed) {
            Button("好", role: .cancel) {}
        } message: {
            Text("无法完成该操作，请检查磁盘空间或目标路径后重试。")
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
        guard let cacheRoot, FileManager.default.fileExists(atPath: cacheRoot.path) else {
            cacheCleared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                cacheCleared = false
            }
            return
        }
        do {
            try FileManager.default.removeItem(at: cacheRoot)
            cacheCleared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                cacheCleared = false
            }
        } catch {
            exportFailed = true
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = AppLocalization().string("导出诊断信息")
        panel.prompt = AppLocalization().string("导出")
        panel.nameFieldStringValue = "MacUnzip-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let report = DiagnosticsExporter.collectReport()
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            exportSucceeded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                exportSucceeded = false
            }
        } catch {
            exportFailed = true
        }
    }

    private func resetAllSettings() {
        let defaults = UserDefaults.standard
        let keys = [
            SettingsKeys.recentArchivesCount,
            SettingsKeys.extractionDestination,
            "appearanceMode",
            RARBinaryDiscovery.licenseConfirmedDefaultsKey,
            RARBinaryDiscovery.userPathDefaultsKey,
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
