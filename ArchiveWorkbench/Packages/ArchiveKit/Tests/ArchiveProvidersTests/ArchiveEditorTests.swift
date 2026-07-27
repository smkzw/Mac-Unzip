import ArchiveDomain
import ArchiveOperations
@testable import ArchiveProviders
import Foundation
import XCTest

final class ArchiveEditorTests: XCTestCase {
    func testAddFileToArchive() async throws {
        let fixture = try EditorZIPFixture(entries: ["keep.txt": Data("keep".utf8)])
        let newFile = try fixture.writeSidecar(name: "added.txt", data: Data("hello add".utf8))
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)

        try await editor.stage(.add(sourceURL: newFile, destinationPath: "added.txt"))
        let pendingAfterStage = await editor.hasPendingChanges
        XCTAssertTrue(pendingAfterStage)
        let output = fixture.rootURL.appending(path: "out-add.zip")
        try await editor.saveAs(to: output)

        let contents = try await fileContents(of: output)
        XCTAssertEqual(contents["keep.txt"], Data("keep".utf8))
        XCTAssertEqual(contents["added.txt"], Data("hello add".utf8))
        let pendingAfterSave = await editor.hasPendingChanges
        XCTAssertFalse(pendingAfterSave)
    }

    func testRemoveEntry() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "a.txt": Data("A".utf8),
            "b.txt": Data("B".utf8),
        ])
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)

        try await editor.stage(.remove(entryPath: "a.txt"))
        let output = fixture.rootURL.appending(path: "out-remove.zip")
        try await editor.saveAs(to: output)

        let contents = try await fileContents(of: output)
        XCTAssertNil(contents["a.txt"])
        XCTAssertEqual(contents["b.txt"], Data("B".utf8))
    }

    func testRenameEntry() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "docs/readme.txt": Data("R".utf8),
        ])
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)

        try await editor.stage(.rename(from: "docs/readme.txt", to: "manual/readme.txt"))
        let output = fixture.rootURL.appending(path: "out-rename.zip")
        try await editor.saveAs(to: output)

        let contents = try await fileContents(of: output)
        XCTAssertNil(contents["docs/readme.txt"])
        XCTAssertEqual(contents["manual/readme.txt"], Data("R".utf8))
    }

    func testReplaceEntry() async throws {
        let fixture = try EditorZIPFixture(entries: ["a.txt": Data("original".utf8)])
        let replacement = try fixture.writeSidecar(name: "replacement.txt", data: Data("replaced content".utf8))
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)

        try await editor.stage(.replace(entryPath: "a.txt", sourceURL: replacement))
        let output = fixture.rootURL.appending(path: "out-replace.zip")
        try await editor.saveAs(to: output)

        let contents = try await fileContents(of: output)
        XCTAssertEqual(contents["a.txt"], Data("replaced content".utf8))
    }

    func testUndoPendingChange() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "a.txt": Data("A".utf8),
            "b.txt": Data("B".utf8),
        ])
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)

        try await editor.stage(.remove(entryPath: "a.txt"))
        let staged = await editor.pendingChanges
        XCTAssertEqual(staged.count, 1)

        let removed = await editor.undo(id: staged[0].id)
        XCTAssertTrue(removed)
        let pendingAfterUndo = await editor.hasPendingChanges
        XCTAssertFalse(pendingAfterUndo)

        let output = fixture.rootURL.appending(path: "out-undo.zip")
        try await editor.saveAs(to: output)
        let contents = try await fileContents(of: output)
        XCTAssertEqual(contents["a.txt"], Data("A".utf8))
        XCTAssertEqual(contents["b.txt"], Data("B".utf8))
    }

    func testSaveCreatesValidZIPAndAppliesMixedChangesInPlace() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "keep.txt": Data("keep".utf8),
            "drop.txt": Data("drop".utf8),
            "move.txt": Data("move".utf8),
        ])
        let newFile = try fixture.writeSidecar(name: "brand.txt", data: Data("brand".utf8))
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)

        try await editor.stage(.remove(entryPath: "drop.txt"))
        try await editor.stage(.rename(from: "move.txt", to: "nested/moved.txt"))
        try await editor.stage(.add(sourceURL: newFile, destinationPath: "brand.txt"))

        let published = try await editor.save()
        XCTAssertEqual(published, fixture.archiveURL)

        let contents = try await fileContents(of: fixture.archiveURL)
        XCTAssertEqual(contents["keep.txt"], Data("keep".utf8))
        XCTAssertEqual(contents["nested/moved.txt"], Data("move".utf8))
        XCTAssertEqual(contents["brand.txt"], Data("brand".utf8))
        XCTAssertNil(contents["drop.txt"])
        XCTAssertNil(contents["move.txt"])

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
            .filter { $0.contains(".editing-") }
        XCTAssertEqual(leftovers, [])
        let pendingAfterPublish = await editor.hasPendingChanges
        XCTAssertFalse(pendingAfterPublish)
    }

    func testUnchangedEntriesPreserveRawNameBytes() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "aa.txt": Data("X".utf8),
            "other.txt": Data("Y".utf8),
        ])
        let rawName: [UInt8] = [0x61, 0xe9, 0x2e, 0x74, 0x78, 0x74]
        try fixture.replaceArchiveNameBytes(matching: Array("aa.txt".utf8), with: rawName)

        let beforeReader = try ZIPBridgeReader(url: fixture.archiveURL)
        let before = try beforeReader.allEntries(maximumCount: 100)
        let original = try XCTUnwrap(before.first { $0.nameBytes == rawName })

        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)
        try await editor.stage(.remove(entryPath: "other.txt"))
        let output = fixture.rootURL.appending(path: "out-raw.zip")
        try await editor.saveAs(to: output)

        let afterReader = try ZIPBridgeReader(url: output)
        let after = try afterReader.allEntries(maximumCount: 100)
        let preserved = try XCTUnwrap(after.first { $0.nameBytes == rawName })
        XCTAssertEqual(preserved.usesUTF8FileName, original.usesUTF8FileName)
        XCTAssertEqual(preserved.uncompressedSize, 1)
        XCTAssertNil(after.first { $0.nameBytes == Array("other.txt".utf8) })
    }


    // MARK: - Crash Recovery Journal Integration

    func testJournalDeletedAfterSuccessfulSave() async throws {
        let fixture = try EditorZIPFixture(entries: ["a.txt": Data("A".utf8)])
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)
        try await editor.stage(.remove(entryPath: "a.txt"))

        _ = try await editor.save()

        // No journal should remain after successful save.
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: fixture.archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))

        // No staging files should remain either.
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: fixture.rootURL.path)
            .filter { $0.contains(".editing-") || $0.hasSuffix(".awb-journal") }
        XCTAssertEqual(leftovers, [])
    }

    func testJournalDeletedAfterSaveAs() async throws {
        let fixture = try EditorZIPFixture(entries: ["a.txt": Data("A".utf8)])
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)
        try await editor.stage(.remove(entryPath: "a.txt"))

        let output = fixture.rootURL.appending(path: "out.zip")
        _ = try await editor.saveAs(to: output)

        // No journal should remain for either the source or the target.
        let sourceJournal = CrashRecoveryJournalStore.journalURL(forArchiveAt: fixture.archiveURL)
        let targetJournal = CrashRecoveryJournalStore.journalURL(forArchiveAt: output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetJournal.path))
    }

    func testSimulatedCrashLeavesJournalForRecovery() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "keep.txt": Data("keep".utf8),
            "remove.txt": Data("remove".utf8),
        ])

        // Simulate a crash: manually create a staging file and journal
        // as if the editor crashed mid-save after writing the staging archive
        // but before the atomic publish.
        let stagingURL = fixture.rootURL.appending(path: ".fixture.zip.editing-crash")
        try FileManager.default.copyItem(at: fixture.archiveURL, to: stagingURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: fixture.archiveURL,
            stagingFile: stagingURL,
            pendingChanges: [.remove(entryPath: "remove.txt")]
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: fixture.archiveURL)

        // Verify journal is found by scanning.
        let found = CrashRecoveryJournalStore.scanForUnfinishedJournals(in: [fixture.rootURL])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].journal.state, .inProgress)
        XCTAssertEqual(found[0].journal.pendingChanges, ["remove:remove.txt"])

        // Verify staging file is detected.
        XCTAssertTrue(CrashRecoveryJournalStore.stagingFileExists(for: journal))

        // Recovery should complete the save (rename staging over original).
        try CrashRecoveryJournalStore.recover(journal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: fixture.archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testRecoveryWithValidStagingSucceeds() async throws {
        let fixture = try EditorZIPFixture(entries: [
            "a.txt": Data("original-a".utf8),
            "b.txt": Data("original-b".utf8),
        ])

        // Build a valid staging archive with modifications using the editor.
        let tempOutput = fixture.rootURL.appending(path: "temp-modified.zip")
        let editor = ArchiveEditor()
        try await editor.open(url: fixture.archiveURL)
        try await editor.stage(.remove(entryPath: "b.txt"))
        try await editor.saveAs(to: tempOutput)

        // Move it to a staging-style path to simulate a crash after staging.
        let stagingURL = fixture.rootURL.appending(path: ".fixture.zip.editing-valid")
        try FileManager.default.moveItem(at: tempOutput, to: stagingURL)

        // Write a journal as if we crashed after staging but before publish.
        let journal = CrashRecoveryJournal(
            sourceArchive: fixture.archiveURL,
            stagingFile: stagingURL,
            pendingChanges: [.remove(entryPath: "b.txt")]
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: fixture.archiveURL)

        // Staging is a valid ZIP.
        XCTAssertTrue(CrashRecoveryJournalStore.stagingFileExists(for: journal))

        // Recover: atomically replace original with staging.
        try CrashRecoveryJournalStore.recover(journal)

        // Verify the archive now has the staging content.
        let contents = try await fileContents(of: fixture.archiveURL)
        XCTAssertEqual(contents["a.txt"], Data("original-a".utf8))
        XCTAssertNil(contents["b.txt"])
    }

    func testRecoveryWithCorruptStagingOffersOnlyDeletion() async throws {
        let fixture = try EditorZIPFixture(entries: ["a.txt": Data("A".utf8)])

        // Create a corrupt staging file (not a valid ZIP).
        let stagingURL = fixture.rootURL.appending(path: ".fixture.zip.editing-corrupt")
        try Data("this is not a zip file".utf8).write(to: stagingURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: fixture.archiveURL,
            stagingFile: stagingURL,
            pendingChanges: [.remove(entryPath: "a.txt")]
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: fixture.archiveURL)

        // Staging file exists but is corrupt.
        XCTAssertTrue(CrashRecoveryJournalStore.stagingFileExists(for: journal))

        // Trying to open it as a ZIP should fail.
        XCTAssertThrowsError(try ZIPBridgeReader(url: stagingURL))

        // Only deletion should be offered (not recovery).
        CrashRecoveryJournalStore.discard(journal)

        // Original archive should be untouched.
        let contents = try await fileContents(of: fixture.archiveURL)
        XCTAssertEqual(contents["a.txt"], Data("A".utf8))

        // Staging and journal should be gone.
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: fixture.archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    private func fileContents(of url: URL) async throws -> [String: Data] {
        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: url)
        var result: [String: Data] = [:]
        for entry in snapshot.entries where !entry.isDirectory {
            result[entry.entry.displayPath] = try await provider.readEntry(
                id: entry.entry.id,
                maximumBytes: 1 << 20
            )
        }
        return result
    }
}

private final class EditorZIPFixture {
    let archiveURL: URL
    let rootURL: URL

    init(entries: [String: Data]) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "ArchiveEditorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        archiveURL = rootURL.appending(path: "fixture.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archiveURL.path, "."]
        process.currentDirectoryURL = contentsURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func writeSidecar(name: String, data: Data) throws -> URL {
        let url = rootURL.appending(path: name)
        try data.write(to: url)
        return url
    }

    func replaceArchiveNameBytes(matching needle: [UInt8], with replacement: [UInt8]) throws {
        precondition(needle.count == replacement.count)
        var bytes = [UInt8](try Data(contentsOf: archiveURL))
        var replacements = 0
        var index = 0
        while index + needle.count <= bytes.count {
            if Array(bytes[index..<(index + needle.count)]) == needle {
                bytes.replaceSubrange(index..<(index + needle.count), with: replacement)
                replacements += 1
                index += replacement.count
            } else {
                index += 1
            }
        }
        guard replacements >= 2 else { throw CocoaError(.fileReadCorruptFile) }
        try Data(bytes).write(to: archiveURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
