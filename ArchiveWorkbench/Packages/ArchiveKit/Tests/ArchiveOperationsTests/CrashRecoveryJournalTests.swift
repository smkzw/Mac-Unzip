import ArchiveDomain
import ArchiveOperations
import Foundation
import XCTest

final class CrashRecoveryJournalTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appending(path: "CrashRecoveryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Model

    func testJournalCodableRoundTrip() throws {
        let archiveURL = tempDir.appending(path: "test.zip")
        let stagingURL = tempDir.appending(path: ".test.zip.editing-123")
        let changes: [PendingChange] = [
            .add(sourceURL: URL(fileURLWithPath: "/tmp/source.txt"), destinationPath: "added.txt"),
            .remove(entryPath: "removed.txt"),
            .rename(from: "old.txt", to: "new.txt"),
            .replace(entryPath: "replaced.txt", sourceURL: URL(fileURLWithPath: "/tmp/replacement.txt")),
        ]
        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: stagingURL,
            pendingChanges: changes
        )

        let data = try JSONEncoder().encode(journal)
        let decoded = try JSONDecoder().decode(CrashRecoveryJournal.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.operation, "save")
        XCTAssertEqual(decoded.sourceArchive, archiveURL.path)
        XCTAssertEqual(decoded.stagingFile, stagingURL.path)
        XCTAssertEqual(decoded.state, .inProgress)
        XCTAssertEqual(decoded.pendingChanges.count, 4)
        XCTAssertFalse(decoded.startedAt.isEmpty)
    }

    func testSanitizeOmitsSourceURLs() {
        let changes: [PendingChange] = [
            .add(sourceURL: URL(fileURLWithPath: "/Users/secret/file.txt"), destinationPath: "added.txt"),
            .remove(entryPath: "gone.txt"),
            .rename(from: "a.txt", to: "b.txt"),
            .replace(entryPath: "doc.pdf", sourceURL: URL(fileURLWithPath: "/private/tmp/replace.txt")),
        ]
        let sanitized = CrashRecoveryJournal.sanitize(changes)
        XCTAssertEqual(sanitized, [
            "add:added.txt",
            "remove:gone.txt",
            "rename:a.txt->b.txt",
            "replace:doc.pdf",
        ])
        for entry in sanitized {
            XCTAssertFalse(entry.contains("/Users/secret"), "Leaked private path: \(entry)")
            XCTAssertFalse(entry.contains("/private/tmp"), "Leaked private path: \(entry)")
        }
    }

    func testJournalDoesNotLeakPrivatePathsInJSON() throws {
        let changes: [PendingChange] = [
            .add(sourceURL: URL(fileURLWithPath: "/Users/john/Secret/passwords.txt"), destinationPath: "data.txt"),
            .replace(entryPath: "config.ini", sourceURL: URL(fileURLWithPath: "/private/var/tmp/secret.key")),
        ]
        let journal = CrashRecoveryJournal(
            sourceArchive: tempDir.appending(path: "archive.zip"),
            stagingFile: tempDir.appending(path: ".archive.zip.staging"),
            pendingChanges: changes
        )

        let data = try JSONEncoder().encode(journal)
        let jsonString = String(data: data, encoding: .utf8)!

        XCTAssertFalse(jsonString.contains("passwords.txt"))
        XCTAssertFalse(jsonString.contains("secret.key"))
        XCTAssertFalse(jsonString.contains("/Users/john"))
        XCTAssertFalse(jsonString.contains("/private/var"))
    }

    // MARK: - Store

    func testWriteReadDelete() throws {
        let archiveURL = tempDir.appending(path: "archive.zip")
        let stagingURL = tempDir.appending(path: ".archive.zip.editing-456")
        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: stagingURL,
            pendingChanges: [.remove(entryPath: "a.txt")]
        )

        try CrashRecoveryJournalStore.write(journal, forArchiveAt: archiveURL)
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: archiveURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertTrue(journalURL.lastPathComponent.hasSuffix(".awb-journal"))

        let read = CrashRecoveryJournalStore.read(at: journalURL)
        XCTAssertEqual(read, journal)

        CrashRecoveryJournalStore.deleteJournal(forArchiveAt: archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testReadReturnsNilForMissingFile() {
        let missing = tempDir.appending(path: "nonexistent.awb-journal")
        XCTAssertNil(CrashRecoveryJournalStore.read(at: missing))
    }

    func testScanFindsInProgressOnly() throws {
        let archive1 = tempDir.appending(path: "a.zip")
        let journal1 = CrashRecoveryJournal(
            sourceArchive: archive1,
            stagingFile: tempDir.appending(path: ".a.zip.staging"),
            pendingChanges: []
        )
        try CrashRecoveryJournalStore.write(journal1, forArchiveAt: archive1)

        let archive2 = tempDir.appending(path: "b.zip")
        var journal2 = CrashRecoveryJournal(
            sourceArchive: archive2,
            stagingFile: tempDir.appending(path: ".b.zip.staging"),
            pendingChanges: []
        )
        journal2.state = .committed
        try CrashRecoveryJournalStore.write(journal2, forArchiveAt: archive2)

        let found = CrashRecoveryJournalStore.scanForUnfinishedJournals(in: [tempDir])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].journal.sourceArchive, archive1.path)
        XCTAssertEqual(found[0].journal.state, .inProgress)
    }

    func testScanMultipleDirectories() throws {
        let dir2 = tempDir.appending(path: "subdir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        let archive1 = tempDir.appending(path: "x.zip")
        try CrashRecoveryJournalStore.write(
            CrashRecoveryJournal(
                sourceArchive: archive1,
                stagingFile: tempDir.appending(path: ".x.zip.staging"),
                pendingChanges: []
            ),
            forArchiveAt: archive1
        )

        let archive2 = dir2.appending(path: "y.zip")
        try CrashRecoveryJournalStore.write(
            CrashRecoveryJournal(
                sourceArchive: archive2,
                stagingFile: dir2.appending(path: ".y.zip.staging"),
                pendingChanges: []
            ),
            forArchiveAt: archive2
        )

        let found = CrashRecoveryJournalStore.scanForUnfinishedJournals(in: [tempDir, dir2])
        XCTAssertEqual(found.count, 2)
    }

    func testStagingFileExists() throws {
        let stagingURL = tempDir.appending(path: "staging.zip")
        let journal = CrashRecoveryJournal(
            sourceArchive: tempDir.appending(path: "archive.zip"),
            stagingFile: stagingURL,
            pendingChanges: []
        )

        XCTAssertFalse(CrashRecoveryJournalStore.stagingFileExists(for: journal))

        try Data("valid zip content".utf8).write(to: stagingURL)
        XCTAssertTrue(CrashRecoveryJournalStore.stagingFileExists(for: journal))
    }

    func testStagingFileExistsFalseForEmptyFile() throws {
        let stagingURL = tempDir.appending(path: "empty.zip")
        try Data().write(to: stagingURL)
        let journal = CrashRecoveryJournal(
            sourceArchive: tempDir.appending(path: "archive.zip"),
            stagingFile: stagingURL,
            pendingChanges: []
        )
        XCTAssertFalse(CrashRecoveryJournalStore.stagingFileExists(for: journal))
    }

    // MARK: - Recovery

    func testRecoverCompletesSave() throws {
        let archiveURL = tempDir.appending(path: "original.zip")
        let stagingURL = tempDir.appending(path: ".original.zip.editing-789")
        try Data("original content".utf8).write(to: archiveURL)
        let stagingZIP = Self.makeMinimalStoredZIP(fileName: "a.txt", content: Data("hello".utf8))
        try stagingZIP.write(to: stagingURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: stagingURL,
            pendingChanges: [.replace(entryPath: "file.txt", sourceURL: URL(fileURLWithPath: "/tmp/new.txt"))]
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: archiveURL)

        try CrashRecoveryJournalStore.recover(journal)

        let content = try Data(contentsOf: archiveURL)
        XCTAssertEqual(content, stagingZIP)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testRecoverRefusesInvalidStagingAndPreservesOriginal() throws {
        let archiveURL = tempDir.appending(path: "original.zip")
        let stagingURL = tempDir.appending(path: ".original.zip.editing-bad")
        try Data("original content".utf8).write(to: archiveURL)
        // A partial/non-ZIP staging file (>= 22 bytes) must not clobber the original.
        try Data("partial truncated staging bytes".utf8).write(to: stagingURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: stagingURL,
            pendingChanges: []
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: archiveURL)

        XCTAssertThrowsError(try CrashRecoveryJournalStore.recover(journal)) { error in
            XCTAssertEqual(error as? CrashRecoveryError, .stagingFileInvalid)
        }

        XCTAssertEqual(String(data: try Data(contentsOf: archiveURL), encoding: .utf8), "original content")
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testRecoverThrowsWhenStagingMissing() throws {
        let archiveURL = tempDir.appending(path: "original.zip")
        try Data("original".utf8).write(to: archiveURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: tempDir.appending(path: ".missing.staging"),
            pendingChanges: []
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: archiveURL)

        XCTAssertThrowsError(try CrashRecoveryJournalStore.recover(journal)) { error in
            XCTAssertEqual(error as? CrashRecoveryError, .stagingFileMissing)
        }

        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertEqual(String(data: try Data(contentsOf: archiveURL), encoding: .utf8), "original")
    }

    func testDiscardRemovesStagingAndJournal() throws {
        let archiveURL = tempDir.appending(path: "original.zip")
        let stagingURL = tempDir.appending(path: ".original.zip.editing-discard")
        try Data("original".utf8).write(to: archiveURL)
        try Data("staging".utf8).write(to: stagingURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: stagingURL,
            pendingChanges: []
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: archiveURL)

        CrashRecoveryJournalStore.discard(journal)

        XCTAssertEqual(String(data: try Data(contentsOf: archiveURL), encoding: .utf8), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    func testDiscardToleratesMissingStaging() throws {
        let archiveURL = tempDir.appending(path: "original.zip")
        try Data("original".utf8).write(to: archiveURL)

        let journal = CrashRecoveryJournal(
            sourceArchive: archiveURL,
            stagingFile: tempDir.appending(path: ".gone.staging"),
            pendingChanges: []
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: archiveURL)

        CrashRecoveryJournalStore.discard(journal)

        let journalURL = CrashRecoveryJournalStore.journalURL(forArchiveAt: archiveURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
    }

    // MARK: - Helpers

    /// Builds a minimal but structurally valid stored (uncompressed) ZIP
    /// containing a single entry, for exercising recovery validation.
    private static func makeMinimalStoredZIP(fileName: String, content: Data) -> Data {
        let nameBytes = Array(fileName.utf8)
        let crc = crc32(content)
        let size = UInt32(content.count)

        var data = Data()
        func u16(_ value: UInt16) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8(value >> 8))
        }
        func u32(_ value: UInt32) {
            data.append(UInt8(value & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 24) & 0xFF))
        }

        // Local file header
        u32(0x0403_4b50)
        u16(20)          // version needed
        u16(0)           // flags
        u16(0)           // method: stored
        u16(0)           // mod time
        u16(0)           // mod date
        u32(crc)
        u32(size)        // compressed size
        u32(size)        // uncompressed size
        u16(UInt16(nameBytes.count))
        u16(0)           // extra length
        data.append(contentsOf: nameBytes)
        data.append(content)
        let centralOffset = UInt32(data.count)

        // Central directory header
        u32(0x0201_4b50)
        u16(20)          // version made by
        u16(20)          // version needed
        u16(0)           // flags
        u16(0)           // method
        u16(0)           // mod time
        u16(0)           // mod date
        u32(crc)
        u32(size)
        u32(size)
        u16(UInt16(nameBytes.count))
        u16(0)           // extra length
        u16(0)           // comment length
        u16(0)           // disk number start
        u16(0)           // internal attrs
        u32(0)           // external attrs
        u32(0)           // local header offset
        data.append(contentsOf: nameBytes)
        let centralSize = UInt32(data.count) - centralOffset

        // End of central directory record
        u32(0x0605_4b50)
        u16(0)           // disk number
        u16(0)           // disk with central dir
        u16(1)           // entries on disk
        u16(1)           // total entries
        u32(centralSize)
        u32(centralOffset)
        u16(0)           // comment length
        return data
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1 != 0) ? (crc >> 1) ^ 0xEDB8_8320 : (crc >> 1)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}
