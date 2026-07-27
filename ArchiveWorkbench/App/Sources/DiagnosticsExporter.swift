import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Diagnostics Exporter

/// Collects sanitized system and app diagnostics for export.
/// SANITIZATION: No absolute user paths, no passwords, no private info.
enum DiagnosticsExporter {
    static func collectReport() -> String {
        var lines: [String] = []
        lines.append("Mac Unzip 诊断报告")
        lines.append("========================")
        lines.append("")

        // App info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        lines.append("应用版本: \(version) (\(build))")
        lines.append("架构: \(architectureString)")
        lines.append("")

        // OS info
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("系统: macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        lines.append("系统版本标识: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        // Locale
        lines.append("语言环境: \(Locale.current.identifier)")
        lines.append("首选语言: \(Locale.preferredLanguages.joined(separator: ", "))")
        lines.append("")

        // Provider status
        lines.append("Provider 状态:")
        let providers = ProviderStatusDetector.detectAll()
        for provider in providers {
            lines.append("  \(provider.name): \(provider.statusText)")
            if provider.version != "—" {
                lines.append("    版本: \(provider.version)")
            }
            // Sanitize path: only show basename, not full path
            if provider.path != "内嵌于应用" && provider.path != "未检测到"
                && provider.path != "未安装" && provider.path != "计划中" {
                let basename = (provider.path as NSString).lastPathComponent
                lines.append("    路径: <已脱敏>/\(basename)")
            }
        }
        lines.append("")

        // Components
        lines.append("组件:")
        for component in ComponentRegistry.all {
            lines.append("  \(component.name) \(component.version) (\(component.licenseName))")
        }
        lines.append("")

        // Timestamp (UTC only, no timezone-identifying info)
        let formatter = ISO8601DateFormatter()
        lines.append("生成时间: \(formatter.string(from: Date()))")
        lines.append("")
        lines.append("--- 报告结束 ---")

        return lines.joined(separator: "\n")
    }

    private static var architectureString: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Presents an NSSavePanel and writes the sanitized report.
    @MainActor
    static func exportToFile() {
        let panel = NSSavePanel()
        panel.title = "导出诊断信息"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "MacUnzip-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let report = collectReport()
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}
