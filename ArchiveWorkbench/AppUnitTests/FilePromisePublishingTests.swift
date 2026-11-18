import Foundation
import XCTest

final class FilePromisePublishingTests: XCTestCase {
    func testResolveDestinationUsesDirectoryMorphologyWithoutAppendingTwice() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromiseDir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = FilePromisePublishing.resolveDestination(
            suppliedURL: root,
            promisedFileName: "README.md"
        )
        XCTAssertEqual(
            resolved.exactURL.standardizedFileURL.path,
            root.appendingPathComponent("README.md").standardizedFileURL.path
        )
    }

    func testResolveDestinationUsesFinderSameNameFileURLMorphology() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromiseFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // TAKEOVER_REPORT v1.1.6: Finder same-name collision supplies .../README.md (not the parent).
        let suppliedFileURL = root.appendingPathComponent("README.md")
        let resolved = FilePromisePublishing.resolveDestination(
            suppliedURL: suppliedFileURL,
            promisedFileName: "README.md"
        )
        XCTAssertEqual(resolved.exactURL.standardizedFileURL.path, suppliedFileURL.standardizedFileURL.path)
        XCTAssertFalse(resolved.exactURL.path.hasSuffix("README.md/README.md"))
    }

    func testFileShapedURLOccupiedByDirectoryIsStillExactTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromiseOccupy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let occupied = root.appendingPathComponent("README.md", isDirectory: true)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        // File-shaped URL (no trailing slash) even though a directory occupies the path.
        let fileShaped = URL(fileURLWithPath: occupied.path, isDirectory: false)
        XCTAssertFalse(fileShaped.hasDirectoryPath)

        let resolved = FilePromisePublishing.resolveDestination(
            suppliedURL: fileShaped,
            promisedFileName: "README.md"
        )
        XCTAssertEqual(resolved.exactURL.standardizedFileURL.path, fileShaped.standardizedFileURL.path)
        let src = root.appendingPathComponent("src.txt")
        try Data("x".utf8).write(to: src)
        XCTAssertThrowsError(
            try FilePromisePublishing.exclusivelyPublishItem(
                at: src,
                toExactDestination: resolved.exactURL
            )
        )
        // Occupying directory unchanged / no nested README.md/README.md write.
        XCTAssertTrue(FilePromisePublishing.isDirectory(occupied))
        XCTAssertFalse(FileManager.default.fileExists(atPath: occupied.appendingPathComponent("README.md").path))
    }

    func testExistingExactTargetUnchangedAndPublishErrors() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromiseExact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let existing = root.appendingPathComponent("report.txt")
        try Data("competitor".utf8).write(to: existing)
        let source = root.appendingPathComponent("source.txt")
        try Data("owned".utf8).write(to: source)

        XCTAssertThrowsError(
            try FilePromisePublishing.exclusivelyPublishItem(
                at: source,
                toExactDestination: existing
            )
        )
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "competitor")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix(".macunzip-publish-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testPublishDirectoryFailureLeavesNoPartialDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromiseDirPub-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingSource = root.appendingPathComponent("missing-folder", isDirectory: true)
        XCTAssertThrowsError(
            try FilePromisePublishing.exclusivelyPublishItem(
                at: missingSource,
                toExactDestination: root.appendingPathComponent("payload", isDirectory: true)
            )
        )
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertFalse(leftovers.contains("payload"))
        XCTAssertTrue(leftovers.filter { $0.hasPrefix(".macunzip-publish-") }.isEmpty)
    }
}
