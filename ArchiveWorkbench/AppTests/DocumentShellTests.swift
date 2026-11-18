import XCTest

@MainActor
final class DocumentShellTests: XCTestCase {
    private func documentToolbar(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["归档工具栏"]
    }

    private func sidebar(in app: XCUIApplication) -> XCUIElement {
        app.outlines["归档侧栏"]
    }

    /// Scenario A: one launch covers real ZIP open → list/preview → toolbar extract → output check.
    func testRealZIPOpenPreviewAndExtractInOneLaunch() throws {
        continueAfterFailure = false
        let fixture = try RealZIPFixture(entries: [
            "文档/说明.txt": Data("真实解压内容".utf8),
            "根目录.txt": Data("root".utf8),
            "图片/封面.png": Data([
                0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
                0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
                0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
                0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
                0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
                0x00, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0xFE,
                0xD4, 0xEF, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
                0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
            ]),
        ])
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipUIExtract-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }

        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-ui-testing",
            "-open-archive", fixture.archiveURL.path,
            "-extraction-destination", destination.path,
        ]
        app.launch()

        let toolbar = documentToolbar(in: app)
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5), "Document toolbar missing after -open-archive")
        let title = toolbar.descendants(matching: .any)["归档标题"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Archive title missing after -open-archive")
        XCTAssertTrue((title.value as? String)?.contains("真实压缩包.zip") ?? false)

        let list = app.outlines["归档文件列表"]
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Archive file list missing")
        XCTAssertFalse(app.buttons["检测完整性"].exists)

        // Scope view toggles to the toolbar so sidebar/menu twins cannot collide.
        let mediaToggle = toolbar.buttons["媒体预览"]
        XCTAssertTrue(mediaToggle.waitForExistence(timeout: 3))
        mediaToggle.click()
        XCTAssertTrue(app.groups["媒体条带"].waitForExistence(timeout: 5), "Media strip missing after preview switch")
        let imageItem = app.buttons["图片/封面.png"]
        XCTAssertTrue(imageItem.waitForExistence(timeout: 5), "Preview media item missing")
        imageItem.click()
        XCTAssertTrue(app.images["封面.png"].waitForExistence(timeout: 5), "Image preview did not appear")

        toolbar.buttons["列表视图"].click()
        XCTAssertTrue(list.waitForExistence(timeout: 5), "List view did not return after preview")

        let extractButton = toolbar.buttons["解压缩全部"]
        XCTAssertTrue(extractButton.waitForExistence(timeout: 5))
        let enabled = expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: extractButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [enabled], timeout: 8),
            .completed,
            "解压缩按钮未在超时内变为可用"
        )
        XCTAssertTrue(extractButton.isEnabled, "Toolbar extract remains disabled after ZIP open")
        extractButton.click()

        XCTAssertTrue(app.staticTexts["解压缩完成：真实压缩包"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["在 Finder 中显示"].waitForExistence(timeout: 3))
        XCTAssertEqual(
            try String(
                contentsOf: destination.appending(path: "真实压缩包/文档/说明.txt"),
                encoding: .utf8
            ),
            "真实解压内容"
        )
        XCTAssertEqual(
            try String(
                contentsOf: destination.appending(path: "真实压缩包/根目录.txt"),
                encoding: .utf8
            ),
            "root"
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: destination.path)
                .contains { $0.hasSuffix(".partial") }
        )
    }

    /// Scenario C: one media-shell launch covers toolbar container, non-overlap, and core labels.
    func testDocumentShellToolbarLayoutAndCoreAccessibilitySmoke() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-ui-testing", "-fixture", "media"]
        app.launch()

        XCTAssertEqual(app.outlines.matching(identifier: "归档侧栏").count, 1)
        let shellSidebar = sidebar(in: app)
        XCTAssertTrue(shellSidebar.waitForExistence(timeout: 5), "Sidebar missing")

        let toolbar = documentToolbar(in: app)
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5), "Missing document toolbar container")

        let add = toolbar.buttons["添加"]
        let extract = toolbar.buttons["解压缩全部"]
        let search = toolbar.searchFields["搜索框"]
        let listToggle = toolbar.buttons["列表视图"]
        let mediaToggle = toolbar.buttons["媒体预览"]
        let operation = toolbar.menuButtons["操作"]
        let title = toolbar.descendants(matching: .any)["归档标题"]

        for control in [add, extract, listToggle, mediaToggle] as [XCUIElement] {
            XCTAssertTrue(control.waitForExistence(timeout: 3), "Missing toolbar control: \(control)")
            XCTAssertFalse(control.frame.isEmpty)
        }
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(operation.waitForExistence(timeout: 3))
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(add.label, "添加")
        XCTAssertEqual(extract.label, "解压缩全部")
        XCTAssertEqual(search.placeholderValue, "搜索")
        XCTAssertFalse(app.buttons["检测完整性"].exists)
        XCTAssertFalse(app.buttons["更多"].exists)
        XCTAssertFalse(app.buttons["更多工具"].exists)
        XCTAssertFalse(app.groups["归档信息检查器"].exists)

        // Sidebar twins share labels; assert they exist under the sidebar only.
        XCTAssertTrue(shellSidebar.buttons["新建压缩包"].exists)
        XCTAssertTrue(shellSidebar.buttons["解压缩全部"].exists)

        let controls = [add, extract, search]
        for firstIndex in controls.indices {
            for secondIndex in controls.indices where secondIndex > firstIndex {
                let intersection = controls[firstIndex].frame.intersection(controls[secondIndex].frame)
                XCTAssertTrue(
                    intersection.isNull || intersection.width == 0 || intersection.height == 0,
                    "Toolbar controls overlap: \(controls[firstIndex]) and \(controls[secondIndex])"
                )
            }
        }

        XCTAssertTrue(app.images["示例主视觉.png"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.groups["媒体条带"].exists)
    }
}

private final class RealZIPFixture {
    let archiveURL: URL
    private let rootURL: URL

    init(entries: [String: Data]) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipUI-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        let contentsURL = rootURL.appending(path: "contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        for (path, data) in entries {
            let url = contentsURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        archiveURL = rootURL.appending(path: "真实压缩包.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archiveURL.path, "."]
        process.currentDirectoryURL = contentsURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
