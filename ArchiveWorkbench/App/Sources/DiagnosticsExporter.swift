import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Diagnostics Exporter

/// Collects sanitized system and app diagnostics for export.
/// SANITIZATION: No absolute user paths, no passwords, no private info.
enum DiagnosticsExporter {
    static func collectReport() -> String {
        var lines: [String] = []
        lines.append("MacUnzip Diagnostics Report")
        lines.append("========================")
        lines.append("")

        // App info
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        lines.append("App Version: \(version) (\(build))")
        lines.append("Architecture: \(architectureString)")
        lines.append("")

        // OS info
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("System: macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        lines.append("OS Version String: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        // Locale
        lines.append("Locale: \(Locale.current.identifier)")
        lines.append("Preferred Languages: \(Locale.preferredLanguages.joined(separator: ", "))")
        lines.append("")

        // Engine status
        lines.append("Engine Status:")
        let providers = ProviderStatusDetector.detectAll()
        for provider in providers {
            lines.append("  \(provider.name): \(provider.statusText)")
            if provider.version != "—" {
                lines.append("    Version: \(provider.version)")
            }
            // Sanitize path: only show basename, and only for real filesystem paths
            // (localized display strings like "Embedded in app" never start with "/").
            if provider.path.hasPrefix("/") {
                let basename = (provider.path as NSString).lastPathComponent
                lines.append("    Path: <sanitized>/\(basename)")
            }
        }
        lines.append("")

        // Components
        lines.append("Components:")
        for component in ComponentRegistry.all {
            lines.append("  \(component.name) \(component.version) (\(component.licenseName))")
        }
        lines.append("")

        // Timestamp (UTC only, no timezone-identifying info)
        let formatter = ISO8601DateFormatter()
        lines.append("Generated: \(formatter.string(from: Date()))")
        lines.append("")
        lines.append("--- End of Report ---")

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
        panel.title = AppLocalization().string("导出诊断信息")
        panel.prompt = AppLocalization().string("导出")
        panel.nameFieldStringValue = "MacUnzip-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let report = collectReport()
        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            let alert = NSAlert()
            alert.messageText = AppLocalization().string("已导出诊断信息")
            alert.informativeText = AppLocalization().format("诊断报告已保存到「%@」。", url.lastPathComponent)
            alert.alertStyle = .informational
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = AppLocalization().string("导出失败")
            alert.informativeText = AppLocalization().string("无法写入诊断报告文件，请检查磁盘空间或目标路径。")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
