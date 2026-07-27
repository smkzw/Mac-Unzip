import AppKit
import Foundation
import SwiftUI

// MARK: - About Panel

struct AboutPanelView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 12)

            Image(systemName: "archivebox.fill")
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Mac Unzip")
                    .font(.title.weight(.semibold))
                Text("Mac解霸")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 2) {
                Text("版本 \(appVersion)（\(buildNumber)）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("架构：\(architecture)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("© 2025 Mac Unzip. 保留所有权利。")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 4)

            Button("组件与许可证…") {
                ComponentsLicensesWindowController.shared.showWindow()
            }
            .buttonStyle(.bordered)

            Spacer().frame(height: 8)
        }
        .frame(width: 320, height: 340)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("关于 Mac解霸")
    }
}

// MARK: - About Window Controller

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: AboutPanelView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "关于 Mac解霸"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
