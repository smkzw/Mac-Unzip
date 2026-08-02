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

    var localizedVersion: String { AppLocalization().string(version) }
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
        ThirdPartyComponent(
            id: "7-zip",
            name: "7-Zip (7zz)",
            version: "24.x",
            licenseName: "LGPL-2.1+",
            copyright: "Copyright (C) 1999-2024 Igor Pavlov",
            url: "https://7-zip.org",
            licenseText: """
            7-Zip Copyright (C) 1999-2024 Igor Pavlov.

            The licenses for files are:
              1) 7z.dll: GNU LGPL + unRAR restriction
              2) All other files: GNU LGPL

            The GNU LGPL + unRAR restriction means that you must follow both
            GNU LGPL rules and unRAR restriction rules.

            GNU LGPL information:
            This library is free software; you can redistribute it and/or
            modify it under the terms of the GNU Lesser General Public
            License as published by the Free Software Foundation; either
            version 2.1 of the License, or (at your option) any later version.

            This library is distributed in the hope that it will be useful,
            but WITHOUT ANY WARRANTY; without even the implied warranty of
            MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
            Lesser General Public License for more details.

            You can receive a copy of the GNU Lesser General Public License from
            http://www.gnu.org/

            unRAR restriction:
            The decompression engine for RAR archives was developed using source
            code of unRAR program. All copyrights to original unRAR code are
            owned by Alexander Roshal. The license for original unRAR code has
            the following restriction: The unRAR sources cannot be used to
            re-create the RAR compression algorithm, which is proprietary.
            """
        ),
        ThirdPartyComponent(
            id: "libarchive",
            name: "libarchive",
            version: "3.8.x",
            licenseName: "BSD-2-Clause",
            copyright: "Copyright (C) 2003-2024 Tim Kientzle",
            url: "https://www.libarchive.org",
            licenseText: """
            The libarchive distribution as a whole is Copyright by Tim Kientzle
            and is subject to the copyright notice reproduced at the bottom of
            this file.

            Redistribution and use in source and binary forms, with or without
            modification, are permitted provided that the following conditions
            are met:

            1. Redistributions of source code must retain the above copyright
               notice, this list of conditions and the following disclaimer.

            2. Redistributions in binary form must reproduce the above copyright
               notice, this list of conditions and the following disclaimer in
               the documentation and/or other materials provided with the
               distribution.

            THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS
            OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
            WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
            ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY
            DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
            DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
            GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
            INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
            IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
            OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
            IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
                    Text(component.localizedVersion)
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
            .accessibilityLabel("\(component.name) \(component.localizedVersion)，\(component.licenseName)")
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
                            Label(component.localizedVersion, systemImage: "tag")
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
        newWindow.title = AppLocalization().string("组件与许可证")
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
