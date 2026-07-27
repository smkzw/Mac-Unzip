import AppKit
import Foundation
import SwiftUI

// MARK: - Component Model

struct ThirdPartyComponent: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let licenseName: String
    let copyright: String
    let url: String
    let licenseText: String
}

enum ComponentRegistry {
    static let all: [ThirdPartyComponent] = [
        ThirdPartyComponent(
            id: "minizip-ng",
            name: "minizip-ng",
            version: "4.2.1",
            licenseName: "Zlib License",
            copyright: "Copyright (C) Nathan Moinvaziri",
            url: "https://github.com/zlib-ng/minizip-ng",
            licenseText: """
            zlib-ng/minizip-ng is licensed under the zlib License:

            Copyright (C) Nathan Moinvaziri

            This software is provided 'as-is', without any express or implied
            warranty. In no event will the authors be held liable for any damages
            arising from the use of this software.

            Permission is granted to anyone to use this software for any purpose,
            including commercial applications, and to alter it and redistribute it
            freely, subject to the following restrictions:

            1. The origin of this software must not be misrepresented; you must not
               claim that you wrote the original software. If you use this software
               in a product, an acknowledgment in the product documentation would be
               appreciated but is not required.
            2. Altered source versions must be plainly marked as such, and must not be
               misrepresented as being the original software.
            3. This notice may not be removed or altered from any source distribution.
            """
        ),
        ThirdPartyComponent(
            id: "apple-libcompression",
            name: "Apple libcompression",
            version: "系统版本",
            licenseName: "Apple SDK License",
            copyright: "Copyright (C) Apple Inc.",
            url: "https://developer.apple.com/documentation/compression",
            licenseText: """
            Apple libcompression is part of the Apple SDK.

            Use of this API is governed by the Apple Developer Program License
            Agreement and the applicable SDK license terms.

            Copyright (C) Apple Inc. All rights reserved.

            IMPORTANT: This Apple software is supplied to you by Apple Inc.
            ("Apple") in consideration of your agreement to the following terms,
            and your use, installation, modification or redistribution of this
            Apple software constitutes acceptance of these terms. If you do not
            agree with these terms, please do not use, install, modify or
            redistribute this Apple software.
            """
        ),
    ]
}

// MARK: - Components & Licenses View

struct ComponentsLicensesView: View {
    @State private var selectedComponentID: ThirdPartyComponent.ID?

    private var selectedComponent: ThirdPartyComponent? {
        ComponentRegistry.all.first { $0.id == selectedComponentID }
    }

    var body: some View {
        HSplitView {
            componentList
                .frame(minWidth: 240, idealWidth: 280)
            licenseDetail
                .frame(minWidth: 360, idealWidth: 440)
        }
        .frame(width: 720, height: 480)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("组件与许可证")
    }

    private var componentList: some View {
        List(ComponentRegistry.all, selection: $selectedComponentID) { component in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(component.name)
                        .fontWeight(.medium)
                    Spacer()
                    Text(component.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(component.licenseName)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(component.id)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(component.name) \(component.version)，\(component.licenseName)")
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var licenseDetail: some View {
        if let component = selectedComponent {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(component.name)
                            .font(.title2.weight(.semibold))
                        HStack(spacing: 12) {
                            Label(component.version, systemImage: "tag")
                            Label(component.licenseName, systemImage: "doc.text")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("版权")
                            .font(.headline)
                        Text(component.copyright)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("链接")
                            .font(.headline)
                        if let url = URL(string: component.url) {
                            Link(component.url, destination: url)
                                .font(.callout)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("许可证全文")
                            .font(.headline)
                        Text(component.licenseText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }
        } else {
            ContentUnavailableView(
                "选择组件",
                systemImage: "doc.text.magnifyingglass",
                description: Text("从左侧列表选择一个组件以查看许可证详情。")
            )
        }
    }
}

// MARK: - Window Controller

@MainActor
final class ComponentsLicensesWindowController: NSObject, NSWindowDelegate {
    static let shared = ComponentsLicensesWindowController()

    private var window: NSWindow?

    func showWindow() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: ComponentsLicensesView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "组件与许可证"
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.minSize = NSSize(width: 600, height: 400)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
