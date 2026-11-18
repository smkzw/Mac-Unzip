import XCTest

/// Scenario B: welcome → New Archive opens the create panel with primary actions visible.
@MainActor
final class AppLaunchTests: XCTestCase {
    func testWelcomeOpensCreatePanelWithPrimaryActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-ui-testing"]
        app.launch()

        let open = app.buttons["打开压缩包"]
        let create = app.buttons["新建压缩包"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "Welcome open action missing")
        XCTAssertTrue(create.exists, "Welcome create action missing")

        let subtitle = app.staticTexts["欢迎页副文案"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 3), "Welcome subtitle missing")
        let observed = (subtitle.value as? String) ?? subtitle.label
        XCTAssertFalse(
            observed.localizedCaseInsensitiveContains("Pro"),
            "Retired Pro activated copy must not appear on welcome"
        )

        create.click()

        let panel = app.descendants(matching: .any)["创建归档面板"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Create panel did not appear from welcome")
        XCTAssertTrue(panel.buttons["从访达选择"].waitForExistence(timeout: 3), "Add-from-Finder action missing")
        XCTAssertTrue(panel.buttons["确认创建归档"].exists, "Primary create/save action missing")
        XCTAssertTrue(panel.buttons["取消"].exists, "Cancel action missing")
        XCTAssertTrue(panel.descendants(matching: .any)["格式选择"].exists, "Format picker missing")
        XCTAssertTrue(panel.descendants(matching: .any)["创建拖放区"].exists, "Create drop zone missing")
    }
}
