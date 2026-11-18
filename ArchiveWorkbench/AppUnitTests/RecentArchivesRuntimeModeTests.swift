import XCTest

final class RecentArchivesRuntimeModeTests: XCTestCase {
    func testVisualCaptureWinsOverUITesting() {
        let mode = RecentArchivesRuntimeMode.resolve(arguments: [
            "-ui-testing", "-visual-capture", "-appearance-light",
        ])
        XCTAssertEqual(mode, .visualCaptureFictional)
    }

    func testUITestingAloneIsEmpty() {
        let mode = RecentArchivesRuntimeMode.resolve(arguments: ["-ui-testing"])
        XCTAssertEqual(mode, .uiTestingEmpty)
    }

    func testDefaultIsLive() {
        let mode = RecentArchivesRuntimeMode.resolve(arguments: ["/path/to/MacUnzip"])
        XCTAssertEqual(mode, .live)
    }

    func testFictionalPathsAreHostAgnostic() {
        for url in RecentArchivesRuntimeMode.fictionalURLs {
            XCTAssertTrue(url.path.hasPrefix("/Users/Sample/"))
            XCTAssertFalse(url.path.contains("smkzw"))
            XCTAssertFalse(url.path.contains("/var/folders"))
        }
    }
}
