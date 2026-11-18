import Foundation
import XCTest

final class CreationInputMergingTests: XCTestCase {
    private func tempFile(name: String, data: Data = Data("x".utf8)) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreationMerge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func tempDir(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreationMergeDir-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testCancelLeavesExistingInputsUntouched() throws {
        let first = try tempFile(name: "a.txt", data: Data("1".utf8))
        let second = try tempFile(name: "a.txt", data: Data("2".utf8))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let existing = [CreationInput(sourceURL: first)]
        let pending = CreationInputMerging.merge(existing: existing, incoming: [second])
        XCTAssertFalse(pending.pendingConflicts.isEmpty)
        XCTAssertEqual(pending.inputs, existing)

        let cancelled = CreationInputMerging.merge(
            existing: existing,
            incoming: [second],
            conflictResolution: .cancel
        )
        XCTAssertEqual(cancelled.inputs, existing)
        XCTAssertTrue(cancelled.added.isEmpty)
    }

    func testRenameUsesArchiveRootNameWithoutCopyingSource() throws {
        let first = try tempFile(name: "report.txt", data: Data("1".utf8))
        let second = try tempFile(name: "report.txt", data: Data("2".utf8))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let renamed = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: first)],
            incoming: [second],
            conflictResolution: .rename
        )
        XCTAssertEqual(renamed.inputs.count, 2)
        XCTAssertEqual(renamed.inputs[0].sourceURL.path, first.standardizedFileURL.path)
        XCTAssertEqual(renamed.inputs[1].sourceURL.path, second.standardizedFileURL.path)
        XCTAssertNotEqual(renamed.inputs[1].archiveRootName.lowercased(), "report.txt")
        XCTAssertFalse(renamed.inputs[1].sourceURL.path.contains("MacUnzip_create_rename_"))
    }

    func testReplaceSwapsArchiveRootCollision() throws {
        let first = try tempFile(name: "same.txt", data: Data("1".utf8))
        let second = try tempFile(name: "same.txt", data: Data("2".utf8))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let replaced = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: first)],
            incoming: [second],
            conflictResolution: .replace
        )
        XCTAssertEqual(replaced.inputs.count, 1)
        XCTAssertEqual(replaced.inputs[0].sourceURL.path, second.standardizedFileURL.path)
    }

    func testParentChildCoverageUsesRealDirectoriesNotPrefixFalsePositive() throws {
        let parent = try tempDir(name: "docs")
        let child = parent.appendingPathComponent("nested.txt")
        try Data("n".utf8).write(to: child)
        let lookalike = try tempDir(name: "docsBackup")
        defer {
            try? FileManager.default.removeItem(at: parent)
            try? FileManager.default.removeItem(at: lookalike)
        }
        let covered = CreationInputMerging.merge(
            existing: [],
            incoming: [parent, child]
        )
        XCTAssertEqual(covered.inputs.count, 1)
        XCTAssertEqual(covered.skippedDuplicates.count, 1)

        let notCovered = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: parent)],
            incoming: [lookalike]
        )
        XCTAssertEqual(notCovered.inputs.count, 2)
        XCTAssertTrue(notCovered.pendingConflicts.isEmpty)
    }

    func testDirectoryAndFileSameRootNameConflict() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CreationMergeSame-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileParent = root.appendingPathComponent("file-side", isDirectory: true)
        let dirParent = root.appendingPathComponent("dir-side", isDirectory: true)
        try FileManager.default.createDirectory(at: fileParent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirParent, withIntermediateDirectories: true)
        let file = fileParent.appendingPathComponent("payload")
        try Data("f".utf8).write(to: file)
        let folder = dirParent.appendingPathComponent("payload", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let conflict = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: file)],
            incoming: [folder]
        )
        XCTAssertEqual(conflict.pendingConflicts.count, 1)
        XCTAssertEqual(conflict.inputs.count, 1)
    }

    func testStaleConflictResolutionDoesNotMergeIntoNewDraft() throws {
        let first = try tempFile(name: "a.txt", data: Data("1".utf8))
        let second = try tempFile(name: "a.txt", data: Data("2".utf8))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let draft = ArchiveCreationDraft(
            inputs: [CreationInput(sourceURL: first)],
            format: .zip,
            generation: 1
        )
        let staleToken = CreationConflictApplication.Token(
            generation: 0,
            inputsRevision: draft.inputsRevision,
            batchToken: UUID(),
            replaceBaseline: false
        )
        let stale = CreationConflictApplication.apply(
            draft: draft,
            token: staleToken,
            incoming: [CreationInput(sourceURL: second)],
            resolution: .rename,
            format: .zip
        )
        XCTAssertNil(stale)

        let staleRevision = CreationConflictApplication.Token(
            generation: 1,
            inputsRevision: draft.inputsRevision &+ 1,
            batchToken: UUID(),
            replaceBaseline: false
        )
        XCTAssertNil(
            CreationConflictApplication.apply(
                draft: draft,
                token: staleRevision,
                incoming: [CreationInput(sourceURL: second)],
                resolution: .rename,
                format: .zip
            )
        )

        let applied = CreationConflictApplication.apply(
            draft: draft,
            token: CreationConflictApplication.Token(
                generation: 1,
                inputsRevision: draft.inputsRevision,
                batchToken: UUID(),
                replaceBaseline: false
            ),
            incoming: [CreationInput(sourceURL: second)],
            resolution: .rename,
            format: .zip
        )
        XCTAssertEqual(applied?.inputs.count, 2)
        XCTAssertNotEqual(applied?.inputs[1].archiveRootName.lowercased(), "a.txt")
        XCTAssertEqual(applied?.inputsRevision, draft.inputsRevision &+ 1)
    }

    func testMakeDraftSeedsConflictsInsteadOfBypassingMerge() throws {
        let first = try tempFile(name: "same.txt", data: Data("1".utf8))
        let second = try tempFile(name: "same.txt", data: Data("2".utf8))
        defer {
            try? FileManager.default.removeItem(at: first.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: second.deletingLastPathComponent())
        }
        let draft = CreationInputMerging.makeDraft(
            inputs: [first, second],
            format: .zip,
            generation: 9
        )
        XCTAssertTrue(draft.inputs.isEmpty)
        XCTAssertFalse(draft.seededPendingConflicts.isEmpty)
        XCTAssertEqual(draft.seededPendingIncoming.count, 2)
        XCTAssertTrue(draft.seededConflictReplaceBaseline)
    }

    func testPreflightSanitizedCommitDetectsRootCollisionsAndStaleRevision() throws {
        let a = CreationInput(
            sourceURL: URL(fileURLWithPath: "/tmp/a.txt"),
            archiveRootName: "dup.txt"
        )
        let b = CreationInput(
            sourceURL: URL(fileURLWithPath: "/tmp/b.txt"),
            archiveRootName: "dup.txt"
        )
        let conflictPlan = PreflightSanitizedCommit.plan(
            draftGeneration: 1,
            draftRevision: 2,
            expectedGeneration: 1,
            expectedRevision: 2,
            sanitized: [a, b]
        )
        guard case .requireConflictResolution(let conflicts, let incoming) = conflictPlan else {
            return XCTFail("expected conflicts, got \(conflictPlan)")
        }
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(incoming.count, 2)

        let stale = PreflightSanitizedCommit.plan(
            draftGeneration: 1,
            draftRevision: 3,
            expectedGeneration: 1,
            expectedRevision: 2,
            sanitized: [a]
        )
        XCTAssertEqual(stale, .stale)

        let apply = PreflightSanitizedCommit.plan(
            draftGeneration: 1,
            draftRevision: 2,
            expectedGeneration: 1,
            expectedRevision: 2,
            sanitized: [a]
        )
        XCTAssertEqual(apply, .apply([a]))
    }

    func testWindowsFilenameSanitizerFixesIllegalArchiveRootCharacters() {
        XCTAssertEqual(WindowsFilenameSanitizer.sanitize("report:final.txt"), "reportfinal.txt")
        XCTAssertNil(WindowsFilenameSanitizer.sanitize("safe.txt"))
    }
}
