import XCTest

final class AppLaunchTests: XCTestCase {
    @MainActor
    func testWelcomeWindowHasChinesePrimaryActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["打开压缩包"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["新建压缩包"].exists)
    }

    @MainActor
    func testWelcomeWindowUsesEnglishCatalogWhenEnglishIsSelected() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui-testing"]
        app.launch()

        let open = app.buttons["打开压缩包"]
        let create = app.buttons["新建压缩包"]
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertEqual(open.label, "Open Archive")
        XCTAssertTrue(create.exists)
        XCTAssertEqual(create.label, "New Archive")
        let subtitle = "Open ZIP, 7z, RAR, TAR, DMG, and ISO archives and safely browse their files.\nYou can also drag archive files directly onto this window.\n\nPro activated · All features available"
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", subtitle)).firstMatch.exists)
    }
}
