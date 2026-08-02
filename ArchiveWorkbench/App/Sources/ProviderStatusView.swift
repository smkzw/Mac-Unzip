import AppKit
import ArchiveProviders
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
    /// Human-readable update channel note (bundled vs external).
    let updateNote: String
    /// Non-nil for externally-distributed engines: opens the vendor site so the
    /// user can fetch the latest binary. Nil for engines shipped inside the app
    /// (updated by updating the app itself) — we never download/replace an
    /// external executable from inside the app (supply-chain risk + contradicts
    /// the zero-network privacy promise + RARLAB licensing).
    let updateURL: URL?
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
            role: AppLocalization().string("ZIP 读写引擎"),
            isAvailable: true,
            statusText: AppLocalization().string("✅ 内置"),
            version: "v4.2.1",
            path: AppLocalization().string("内嵌于应用"),
            updateNote: AppLocalization().string("随应用更新"),
            updateURL: nil
        )
    }

    private static func detectSevenZip() -> ProviderStatusInfo {
        if let discovery = SevenZipBinaryDiscovery.discover() {
            let isBundled = discovery.resolvedPath.contains(Bundle.main.resourceURL?.path ?? "\0")
            return ProviderStatusInfo(
                id: "7zz",
                name: "7zz",
                role: AppLocalization().string("7z / RAR 读取"),
                isAvailable: true,
                statusText: isBundled
                    ? AppLocalization().string("✅ 内置")
                    : AppLocalization().string("✅ 已检测到"),
                version: discovery.version,
                path: isBundled ? AppLocalization().string("内嵌于应用") : discovery.resolvedPath,
                updateNote: isBundled
                    ? AppLocalization().string("随应用更新")
                    : AppLocalization().string("前往官网获取最新版"),
                updateURL: isBundled ? nil : URL(string: "https://www.7-zip.org")
            )
        }
        return ProviderStatusInfo(
            id: "7zz",
            name: "7zz",
            role: AppLocalization().string("7z / RAR 读取"),
            isAvailable: false,
            statusText: AppLocalization().string("❌ 未检测到"),
            version: "—",
            path: AppLocalization().string("未检测到"),
            updateNote: AppLocalization().string("前往官网获取最新版"),
            updateURL: URL(string: "https://www.7-zip.org")
        )
    }

    private static func detectRarlab() -> ProviderStatusInfo {
        if let discovery = RARBinaryDiscovery.discover() {
            return ProviderStatusInfo(
                id: "rarlab-rar",
                name: "RARLAB rar",
                role: AppLocalization().string("RAR 创建（外部）"),
                isAvailable: true,
                statusText: AppLocalization().string("✅ 已检测到"),
                version: discovery.version.isEmpty
                    ? AppLocalization().string("已安装")
                    : discovery.version,
                path: discovery.resolvedPath,
                updateNote: AppLocalization().string("前往官网获取最新版"),
                updateURL: URL(string: "https://www.rarlab.com")
            )
        }
        return ProviderStatusInfo(
            id: "rarlab-rar",
            name: "RARLAB rar",
            role: AppLocalization().string("RAR 创建（外部）"),
            isAvailable: false,
            statusText: AppLocalization().string("❌ 未检测到"),
            version: "—",
            path: AppLocalization().string("未检测到"),
            updateNote: AppLocalization().string("前往官网获取最新版"),
            updateURL: URL(string: "https://www.rarlab.com")
        )
    }

    private static func detectLibarchive() -> ProviderStatusInfo {
        ProviderStatusInfo(
            id: "libarchive",
            name: "libarchive",
            role: "tar / gz / xz / zst / ISO",
            isAvailable: true,
            statusText: AppLocalization().string("✅ 内置"),
            version: "3.8.x",
            path: AppLocalization().string("内嵌于应用"),
            updateNote: AppLocalization().string("随应用更新"),
            updateURL: nil
        )
    }
}

// MARK: - Provider Status View

struct ProviderStatusView: View {
    @State private var providers: [ProviderStatusInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("格式支持状态")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("刷新") {
                    providers = ProviderStatusDetector.detectAll()
                }
                .accessibilityIdentifier("刷新引擎状态")
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
                        if let updateURL = provider.updateURL {
                            Button(AppLocalization().string("前往官网")) {
                                NSWorkspace.shared.open(updateURL)
                            }
                            .font(.caption)
                            .buttonStyle(.link)
                            .accessibilityIdentifier("前往\(provider.name)官网")
                        } else {
                            Text(provider.updateNote)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(provider.name)，\(provider.statusText.replacingOccurrences(of: "✅ ", with: "").replacingOccurrences(of: "❌ ", with: ""))")
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(width: 520, height: 380)
        .onAppear {
            providers = ProviderStatusDetector.detectAll()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("格式支持状态")
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
        newWindow.title = AppLocalization().string("格式支持状态")
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
