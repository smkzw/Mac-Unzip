import XCTest

final class AppLaunchTests: XCTestCase {
    @MainActor
    func testWelcomeWindowHasChinesePrimaryActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["打开压缩包"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["创建归档"].exists)
    }

    @MainActor
    func testWelcomeWindowUsesEnglishCatalogWhenEnglishIsSelected() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-testing"]
        app.launch()

        let open = app.buttons["打开压缩包"]
        let create = app.buttons["创建归档"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertEqual(open.label, "Open Archive")
        XCTAssertTrue(create.exists)
        XCTAssertEqual(create.label, "Create Archive")
        XCTAssertTrue(app.staticTexts["Open ZIP archives and inspect their files safely."].exists)
    }
}
