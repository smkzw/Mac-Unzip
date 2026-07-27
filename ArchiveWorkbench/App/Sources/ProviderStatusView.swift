import AppKit
import Foundation
import SwiftUI

// MARK: - Provider Status Model

struct ProviderStatusInfo: Identifiable {
    let id: String
    let name: String
    let role: String
    let isAvailable: Bool
    let statusText: String
    let version: String
    let path: String
}

enum ProviderStatusDetector {
    static func detectAll() -> [ProviderStatusInfo] {
        [
            detectMinizipNG(),
            detectSevenZip(),
            detectRarlab(),
            detectLibarchive(),
        ]
    }

    private static func detectMinizipNG() -> ProviderStatusInfo {
        ProviderStatusInfo(
            id: "minizip-ng",
            name: "MinizipNG",
            role: "ZIP 读写引擎",
            isAvailable: true,
            statusText: "✅ 内置",
            version: "v4.2.1",
            path: "内嵌于应用"
        )
    }

    private static func detectSevenZip() -> ProviderStatusInfo {
        let candidates = [
            "/opt/homebrew/bin/7zz",
            "/usr/local/bin/7zz",
            "/usr/bin/7zz",
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            let version = queryVersion(path: candidate, arguments: ["i"])
            return ProviderStatusInfo(
                id: "7zz",
                name: "7zz",
                role: "7z / RAR 读取",
                isAvailable: true,
                statusText: "✅ 已检测到",
                version: version ?? "已安装",
                path: candidate
            )
        }
        return ProviderStatusInfo(
            id: "7zz",
            name: "7zz",
            role: "7z / RAR 读取",
            isAvailable: false,
            statusText: "❌ 未安装",
            version: "—",
            path: "未检测到"
        )
    }

    private static func detectRarlab() -> ProviderStatusInfo {
        let candidates = [
            "/opt/homebrew/bin/rar",
            "/usr/local/bin/rar",
            "/usr/bin/rar",
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            let version = queryVersion(path: candidate, arguments: ["--version"])
            return ProviderStatusInfo(
                id: "rarlab-rar",
                name: "RARLAB rar",
                role: "RAR 创建（外部）",
                isAvailable: true,
                statusText: "✅ 已检测到",
                version: version ?? "已安装",
                path: candidate
            )
        }
        return ProviderStatusInfo(
            id: "rarlab-rar",
            name: "RARLAB rar",
            role: "RAR 创建（外部）",
            isAvailable: false,
            statusText: "❌ 未安装",
            version: "—",
            path: "未安装"
        )
    }

    private static func detectLibarchive() -> ProviderStatusInfo {
        ProviderStatusInfo(
            id: "libarchive",
            name: "libarchive",
            role: "tar / gz / xz / ISO",
            isAvailable: false,
            statusText: "❌ 未实现",
            version: "—",
            path: "计划中"
        )
    }

    private static func queryVersion(path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            let lines = output.components(separatedBy: .newlines)
            // Look for a line containing a version-like pattern (digits and dots)
            for line in lines {
                if line.rangeOfCharacter(from: .decimalDigits) != nil,
                   line.contains(".") {
                    return line.trimmingCharacters(in: .whitespaces)
                }
            }
            return lines.first(where: { !$0.isEmpty })
        } catch {
            return nil
        }
    }
}

// MARK: - Provider Status View

struct ProviderStatusView: View {
    @State private var providers: [ProviderStatusInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Provider 状态")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("刷新") {
                    providers = ProviderStatusDetector.detectAll()
                }
            }
            .padding(20)
            .padding(.bottom, 8)

            List(providers) { provider in
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.name)
                            .fontWeight(.medium)
                        Text(provider.role)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(provider.statusText)
                            .font(.callout)
                            .foregroundStyle(provider.isAvailable ? .green : .secondary)
                        if provider.version != "—" {
                            Text(provider.version)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(provider.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(provider.name)，\(provider.statusText)")
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(width: 520, height: 380)
        .onAppear {
            providers = ProviderStatusDetector.detectAll()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider 状态")
    }
}

// MARK: - Window Controller

@MainActor
final class ProviderStatusWindowController: NSObject, NSWindowDelegate {
    static let shared = ProviderStatusWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: ProviderStatusView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Provider 状态"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 440, height: 300)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
