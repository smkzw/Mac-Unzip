import Foundation
import XCTest

@MainActor
final class PreflightArchiveRootTests: XCTestCase {
    func testFixPreflightIssuesSanitizesCustomArchiveRootName() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreflightRoot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("safe.txt")
        try Data("ok".utf8).write(to: source)
        let input = CreationInput(sourceURL: source, archiveRootName: "bad:name.txt")

        let model = AppModel()
        let fixed = await model.fixPreflightIssues(inputs: [input])
        XCTAssertEqual(fixed.count, 1)
        XCTAssertEqual(fixed[0].archiveRootName, "badname.txt")
        XCTAssertEqual(fixed[0].sourceURL.standardizedFileURL.path, source.standardizedFileURL.path)

        await model.runPreflight(inputs: fixed)
        XCTAssertTrue(model.preflightIssues.isEmpty)
    }

    func testFixPreflightIssuesSanitizesAutoRenamedIllegalRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreflightAuto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("notes.txt")
        try Data("ok".utf8).write(to: source)
        // Conflict rename can produce a still-illegal Windows root that must be fixed.
        let input = CreationInput(sourceURL: source, archiveRootName: "notes 2?.txt")

        let model = AppModel()
        let fixed = await model.fixPreflightIssues(inputs: [input])
        XCTAssertEqual(fixed[0].archiveRootName, "notes 2.txt")
        await model.runPreflight(inputs: fixed)
        XCTAssertTrue(model.preflightIssues.isEmpty)
    }

    func testSanitizedDuplicateRootsRequireConflictBeforeCanCreate() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreflightDup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("one.txt")
        let second = root.appendingPathComponent("two.txt")
        try Data("1".utf8).write(to: first)
        try Data("2".utf8).write(to: second)
        let inputs = [
            CreationInput(sourceURL: first, archiveRootName: "a:1.txt"),
            CreationInput(sourceURL: second, archiveRootName: "a?1.txt")
        ]
        let model = AppModel()
        let fixed = await model.fixPreflightIssues(inputs: inputs)
        // Both sanitize to a1.txt → collision must block create until resolved.
        XCTAssertEqual(fixed.map(\.archiveRootName), ["a1.txt", "a1.txt"])
        let plan = PreflightSanitizedCommit.plan(
            draftGeneration: 1,
            draftRevision: 0,
            expectedGeneration: 1,
            expectedRevision: 0,
            sanitized: fixed
        )
        guard case .requireConflictResolution = plan else {
            return XCTFail("expected conflict plan, got \(plan)")
        }
        XCTAssertTrue(CreationInputMerging.hasDuplicateArchiveRoots(fixed))
    }
}