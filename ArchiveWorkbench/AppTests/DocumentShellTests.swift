import XCTest

@MainActor
final class DocumentShellTests: XCTestCase {
    private func makeApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-ui-testing", "-fixture", "media"]
        return app
    }

    private func assertEssentialToolbarFramesDoNotIntersect(_ app: XCUIApplication) {
        let controls: [XCUIElement] = [
            app.buttons["返回"],
            app.buttons["前进"],
            app.buttons["添加"],
            app.buttons["解压缩"],
            app.searchFields["搜索框"]
        ]
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 3), "Missing essential toolbar control: \(control)")
            XCTAssertFalse(control.frame.isEmpty)
        }
        for firstIndex in controls.indices {
            for secondIndex in controls.indices where secondIndex > firstIndex {
                let intersection = controls[firstIndex].frame.intersection(controls[secondIndex].frame)
                XCTAssertTrue(
                    intersection.isNull || intersection.width == 0 || intersection.height == 0,
                    "Toolbar controls overlap: \(controls[firstIndex]) and \(controls[secondIndex])"
                )
            }
        }
    }

    private func assertToolbarOrderAndLabels(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        let title = app.descendants(matching: .any)["归档标题"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(title.frame.minX, window.frame.minX + 90)
        XCTAssertLessThanOrEqual(title.frame.maxX, window.frame.maxX)

        for label in ["添加", "解压缩"] {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            XCTAssertEqual(button.label, label)
        }
        XCTAssertFalse(app.buttons["检测完整性"].exists)
        XCTAssertFalse(app.buttons["更多"].exists)
        XCTAssertFalse(app.buttons["更多工具"].exists)

        var ordered: [XCUIElement] = [
            title,
            app.buttons["返回"], app.buttons["前进"],
            app.buttons["添加"], app.buttons["解压缩"],
            app.buttons["列表视图"], app.buttons["媒体预览"], app.buttons["信息"]
        ]
        let operationMenu = app.menuButtons["操作"]
        XCTAssertTrue(operationMenu.waitForExistence(timeout: 3))
        ordered.append(operationMenu)
        ordered.append(app.searchFields["搜索框"])
        for element in ordered { XCTAssertTrue(element.exists, "Missing ordered toolbar element: \(element)") }
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.frame.maxX, pair.1.frame.minX, "Toolbar order/spacing changed")
        }
    }

    func testMediaShellHasOneSidebarAndNoRejectedControls() {
        let app = makeApp()
        app.launch()

        XCTAssertEqual(app.outlines.matching(identifier: "归档侧栏").count, 1)
        XCTAssertTrue(app.images["首页主视觉.png"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.groups["媒体条带"].exists)
        XCTAssertFalse(app.staticTexts["附近的项目"].exists)
        XCTAssertFalse(app.staticTexts["更多文件…"].exists)
        XCTAssertFalse(app.buttons["创建归档"].exists)
    }

    func testLaunchArgumentOpensRealUTF8ZIPWithProviderMetadata() throws {
        let fixture = try RealZIPFixture(entries: [
            "文档/说明.txt": Data("真实压缩包内容".utf8),
            "图片/封面.png": Data([0x89, 0x50, 0x4e, 0x47]),
        ])
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-ui-testing",
            "-open-archive", fixture.archiveURL.path,
        ]

        app.launch()

        let title = app.descendants(matching: .any)["归档标题"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.tables["归档文件列表"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["说明.txt"].exists)
        XCTAssertFalse(app.staticTexts["封面.png"].exists)
        XCTAssertFalse(app.buttons["检测完整性"].exists)
        XCTAssertTrue(app.menuButtons["操作"].exists)
    }

    func testRealZIPExtractionPublishesFilesThroughToolbarWorkflow() throws {
        let fixture = try RealZIPFixture(entries: [
            "文档/说明.txt": Data("真实解压内容".utf8),
            "根目录.txt": Data("root".utf8),
        ])
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "ArchiveWorkbenchUIExtract-" + UUID().uuidString,
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
        let extractButton = app.buttons["解压缩"]
        XCTAssertTrue(extractButton.waitForExistence(timeout: 5))
        let enabled = expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: extractButton
        )
        wait(for: [enabled], timeout: 3)

        extractButton.click()

        XCTAssertTrue(app.staticTexts["解压缩完成：真实压缩包"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["在 Finder 中显示"].waitForExistence(timeout: 3))
        keepScreenshot(of: app.windows.firstMatch, named: "解压缩-完成状态")
        XCTAssertEqual(
            try String(
                contentsOf: destination.appending(path: "真实压缩包/文档/说明.txt"),
                encoding: .utf8
            ),
            "真实解压内容"
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: destination.path)
                .contains { $0.hasSuffix(".partial") }
        )
    }

    func testToolbarHasChineseAccessibleControls() {
        let app = makeApp()
        app.launch()

        for label in ["返回", "前进", "列表视图", "媒体预览", "信息", "添加", "解压缩"] {
            XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 3), "Missing toolbar button: \(label)")
        }
        XCTAssertFalse(app.buttons["返回"].isEnabled)
        XCTAssertFalse(app.buttons["前进"].isEnabled)
        XCTAssertTrue(app.searchFields["搜索框"].exists)
        XCTAssertTrue(app.groups["归档信息检查器"].exists)
        XCTAssertFalse(app.staticTexts["Mac解霸"].exists)
        assertEssentialToolbarFramesDoNotIntersect(app)
        assertToolbarOrderAndLabels(app)
        keepScreenshot(of: app.windows.firstMatch, named: "工具栏-默认宽度")
    }

    func testMediaShellUsesEnglishLabels() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-ui-testing", "-fixture", "media",
        ]
        app.launch()

        let add = app.descendants(matching: .any)["Add"]
        let extract = app.descendants(matching: .any)["Extract"]
        let search = app.searchFields["搜索框"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertTrue(extract.waitForExistence(timeout: 3))
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(add.label, "Add")
        XCTAssertEqual(extract.label, "Extract")
        XCTAssertEqual(search.label, "Search Archive Contents")
        XCTAssertEqual(search.placeholderValue, "Search")
        let inspector = app.groups["归档信息检查器"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 3))
        XCTAssertEqual(inspector.label, "Archive Inspector")
        let title = app.descendants(matching: .any)["归档标题"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.value as? String, "品牌素材与文档.zip, 5 items shown")
    }

    func testOperationMenuDoesNotExposeUnimplementedIntegrityCheck() {
        let app = makeApp()
        app.launch()

        let operationMenu = app.menuButtons["操作"]
        XCTAssertTrue(operationMenu.waitForExistence(timeout: 3))
        operationMenu.click()
        XCTAssertFalse(app.menuItems["检测完整性"].exists)
    }

    func testEssentialToolbarControlsDoNotOverlapAtMinimumWidth() {
        let app = makeApp()
        app.launchArguments.append("-minimum-window")
        app.launch()

        let window = app.windows.firstMatch
        let resized = expectation(
            for: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.frame.width <= 900.5
            },
            evaluatedWith: window
        )
        wait(for: [resized], timeout: 3)
        XCTAssertLessThanOrEqual(window.frame.width, 900.5)
        assertEssentialToolbarFramesDoNotIntersect(app)
        assertToolbarOrderAndLabels(app)
        XCTAssertEqual(app.searchFields["搜索框"].placeholderValue, "搜索")
        keepScreenshot(of: window, named: "工具栏-最小宽度")
    }

    private func keepScreenshot(of element: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLongMultilingualFilenameStaysSingleLineAndKeepsExtensionDiscoverable() {
        let app = makeApp()
        app.launchArguments.append("-long-filename-fixture")
        app.launch()
        let filename = "季度Campaign_国际化视觉资产_最终批准版本_v12.heic"

        let item = app.buttons[filename]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        XCTAssertTrue(item.label.contains(filename))
        let filenameLabel = app.staticTexts["文件名：\(filename)"]
        XCTAssertTrue(filenameLabel.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(filenameLabel.frame.height, 20)
        XCTAssertTrue(filenameLabel.frame.intersection(item.frame).isNull)
        let sizeLabel = app.staticTexts["文件大小：14.8 MB"]
        XCTAssertTrue(sizeLabel.exists)
        XCTAssertTrue(filenameLabel.frame.intersection(sizeLabel.frame).isNull)
    }

    func testViewSwitchingPreservesSelectionAndInspectorCanToggle() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.images["首页主视觉.png"].waitForExistence(timeout: 3))

        app.buttons["列表视图"].click()
        XCTAssertTrue(app.tables["归档文件列表"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["首页主视觉.png"].exists)

        app.buttons["媒体预览"].click()
        XCTAssertTrue(app.images["首页主视觉.png"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.groups["归档信息检查器"].exists)
        app.buttons["信息"].click()
        XCTAssertFalse(app.groups["归档信息检查器"].waitForExistence(timeout: 1))
        app.buttons["信息"].click()
        XCTAssertTrue(app.groups["归档信息检查器"].waitForExistence(timeout: 3))
    }

    func testDefaultMediaStripShowsAllPrimaryItemsWithoutEdgeClipping() {
        let app = makeApp()
        app.launchArguments.append("-visual-capture")
        app.launch()

        let strip = app.groups["媒体条带"]
        XCTAssertTrue(strip.waitForExistence(timeout: 3))
        for filename in ["首页主视觉.png", "深色标志.svg", "产品截图.heic", "演示视频.mp4", "品牌指南.pdf"] {
            let item = app.buttons[filename]
            XCTAssertTrue(item.waitForExistence(timeout: 3), "Missing media item: \(filename)")
            XCTAssertGreaterThanOrEqual(item.frame.minX, strip.frame.minX, "Media item clips the leading edge: \(filename)")
            XCTAssertLessThanOrEqual(item.frame.maxX, strip.frame.maxX, "Media item clips the trailing edge: \(filename)")
        }
    }

    func testSearchAndCurrentOperationPopoverWork() {
        let app = makeApp()
        app.launch()

        let searchField = app.searchFields["搜索框"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.click()
        searchField.typeText("指南")
        XCTAssertTrue(app.staticTexts["品牌指南.pdf"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["首页主视觉.png"].exists)

        app.menuButtons["操作"].click()
        XCTAssertFalse(app.menuItems["检测完整性"].exists)
        app.menuItems["当前操作"].click()
        XCTAssertTrue(app.popovers["当前操作面板"].waitForExistence(timeout: 3))
    }

    func testSelectingPDFUsesPDFKitPreviewState() {
        let app = makeApp()
        app.launch()

        let pdfItem = app.buttons["品牌指南.pdf"]
        XCTAssertTrue(pdfItem.waitForExistence(timeout: 3))
        pdfItem.click()
        XCTAssertTrue(app.groups["PDFKit 预览"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["PDF 文档已加载，2 页"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["PDF 文档"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["6.3 MB (6,606,028 字节)"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["图片素材/品牌指南.pdf"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已选择 1 项 · 6.3 MB"].waitForExistence(timeout: 3))
    }

    func testRealZIPPreviewsImageVideoPDFWordExcelAndPowerPoint() throws {
        let names = ["示例.png", "示例.mp4", "示例.pdf", "示例.docx", "示例.xlsx", "示例.pptx"]
        let entries = try Dictionary(uniqueKeysWithValues: names.map { name in
            let url = URL(fileURLWithPath: name)
            let source = try XCTUnwrap(Bundle(for: Self.self).url(
                forResource: url.deletingPathExtension().lastPathComponent,
                withExtension: url.pathExtension
            ))
            return ("预览/" + name, try Data(contentsOf: source))
        })
        let fixture = try RealZIPFixture(entries: entries)
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(zh-Hans)",
            "-ui-testing",
            "-open-archive", fixture.archiveURL.path,
        ]
        app.launch()
        let dismissCrashRecovery = app.dialogs.buttons["不重新打开"].firstMatch
        if dismissCrashRecovery.waitForExistence(timeout: 1) {
            dismissCrashRecovery.click()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 3))
            app.launch()
        }

        XCTAssertTrue(app.tables["归档文件列表"].waitForExistence(timeout: 5))
        app.buttons["媒体预览"].click()

        // Wait for the media strip to confirm the view switch completed.
        XCTAssertTrue(app.groups["媒体条带"].waitForExistence(timeout: 5))

        // Close the inspector so it cannot overlap media item click targets.
        let inspector = app.groups["归档信息检查器"]
        if inspector.waitForExistence(timeout: 2) {
            app.buttons["信息"].click()
            XCTAssertFalse(inspector.waitForExistence(timeout: 2))
        }

        let imageItem = app.buttons["预览/示例.png"]
        XCTAssertTrue(imageItem.waitForExistence(timeout: 5))
        imageItem.click()
        XCTAssertTrue(app.images["示例.png"].waitForExistence(timeout: 5))

        let videoItem = app.buttons["预览/示例.mp4"]
        XCTAssertTrue(videoItem.waitForExistence(timeout: 5))
        videoItem.click()
        XCTAssertTrue(app.descendants(matching: .any)["原生视频预览"].waitForExistence(timeout: 5))

        let pdfItem = app.buttons["预览/示例.pdf"]
        XCTAssertTrue(pdfItem.waitForExistence(timeout: 5))
        pdfItem.click()
        XCTAssertTrue(app.groups["PDFKit 预览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["PDF 文档已加载，1 页"].waitForExistence(timeout: 5))

        for (filename, label) in [
            ("示例.docx", "Word 文档 Quick Look 预览"),
            ("示例.xlsx", "Excel 表格 Quick Look 预览"),
            ("示例.pptx", "PowerPoint 演示文稿 Quick Look 预览"),
        ] {
            let item = app.buttons["预览/" + filename]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Media item not hittable: \(filename)")
            item.click()
            XCTAssertTrue(
                app.descendants(matching: .any)[label].waitForExistence(timeout: 5),
                "Missing real preview for \(filename)"
            )
        }
    }

    func testKeyboardReachabilityAndAccessibilityAudit() throws {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["添加"].waitForExistence(timeout: 3))

        app.typeKey("f", modifierFlags: .command)
        app.typeText("品牌")
        XCTAssertEqual(app.searchFields["搜索框"].value as? String, "品牌")
        try app.performAccessibilityAudit { issue in
            let element = issue.element
            print("ACCESSIBILITY_AUDIT type=\(issue.auditType.rawValue) compact=\(issue.compactDescription) detailed=\(issue.detailedDescription) elementTypeRaw=\(element?.elementType.rawValue ?? UInt.max) identifier=\(element?.identifier ?? "") label=\(element?.label ?? "") title=\(element?.title ?? "") frame=\(String(describing: element?.frame)) debug=\(element?.debugDescription ?? "")")
            if let element,
               element.elementType.rawValue == 81,
               element.identifier.isEmpty,
               element.label.isEmpty,
               element.title.isEmpty,
               element.debugDescription.contains("TouchBar"),
               element.frame.minY == 0 {
                XCTContext.runActivity(named: "记录 macOS 虚拟 Touch Bar 结构元素") { activity in
                    activity.add(XCTAttachment(string: element.debugDescription))
                }
                return true
            }
            if let element,
               issue.compactDescription == "Parent/Child mismatch",
               element.elementType == .group,
               element.frame.size == CGSize(width: 14, height: 14),
               ["_XCUI:CloseWindow", "_XCUI:MinimizeWindow", "_XCUI:FullScreenWindow"]
                .contains(where: element.debugDescription.contains) {
                XCTContext.runActivity(named: "记录 macOS 标准窗口按钮内部 glyph") { activity in
                    activity.add(XCTAttachment(string: element.debugDescription))
                }
                return true
            }
            if let element,
               issue.compactDescription == "Element has no description",
               element.elementType == .other,
               element.identifier.isEmpty,
               element.label.isEmpty,
               element.title.isEmpty,
               element.debugDescription.contains("PDF 页面容器，共 "),
               element.debugDescription.contains(" 页") {
                XCTContext.runActivity(named: "记录 PDFKit 原生页面容器") { activity in
                    activity.add(XCTAttachment(string: element.debugDescription))
                }
                return true
            }
            if let element,
               issue.compactDescription == "Action is missing",
               element.elementType == .menuButton,
               element.identifier == "操作",
               element.label == "操作" {
                XCTContext.runActivity(named: "记录 macOS 原生 MenuButton 审计误报") { activity in
                    activity.add(XCTAttachment(string: element.debugDescription))
                }
                return true
            }
            return false
        }
    }
}

private final class RealZIPFixture {
    let archiveURL: URL
    private let rootURL: URL

    init(entries: [String: Data]) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "ArchiveWorkbenchUI-" + UUID().uuidString,
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
