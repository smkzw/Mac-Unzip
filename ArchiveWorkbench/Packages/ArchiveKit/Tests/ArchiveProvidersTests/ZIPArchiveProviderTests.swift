import ArchiveDomain
@testable import ArchiveProviders
import Foundation
import XCTest

final class ZIPArchiveProviderTests: XCTestCase {
    func testOpenListsUTF8FilesAndDirectories() async throws {
        let fixture = try ZIPFixture(entries: [
            "文档/说明.txt": Data("你好 Windows".utf8),
            "图片/封面.png": Data([0x89, 0x50, 0x4e, 0x47]),
        ])
        let provider = ZIPArchiveProvider()

        let snapshot = try await provider.open(url: fixture.archiveURL)

        XCTAssertEqual(snapshot.format, .zip)
        let files = snapshot.entries
            .filter { !$0.isDirectory }
            .sorted { $0.entry.displayPath < $1.entry.displayPath }
        XCTAssertEqual(files.map(\.entry.displayPath), ["图片/封面.png", "文档/说明.txt"])
        XCTAssertTrue(files.allSatisfy {
            $0.entry.rawPath.bytes == Array($0.entry.displayPath.utf8)
        })
    }

    func testOpenRejectsNonZIPBytes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ArchiveWorkbenchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "损坏.zip")
        try Data("not zip".utf8).write(to: url)
        let provider = ZIPArchiveProvider()

        do {
            _ = try await provider.open(url: url)
            XCTFail("Expected corruptedArchive")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .corruptedArchive)
        }
    }

    func testOpenRejectsUnsafeDirectoryEntry() async throws {
        let fixture = try ZIPFixture(entries: ["safe/file.txt": Data("x".utf8)])
        try fixture.replaceArchiveNameBytes(
            matching: Array("safe/".utf8),
            with: Array("../x/".utf8)
        )
        let provider = ZIPArchiveProvider()

        do {
            _ = try await provider.open(url: fixture.archiveURL)
            XCTFail("Expected unsafePath")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .unsafePath)
        }
    }

    func testOpenEnforcesListingEntryLimit() async throws {
        let fixture = try ZIPFixture(entries: [
            "one.txt": Data("1".utf8),
            "two.txt": Data("2".utf8),
        ])
        let provider = ZIPArchiveProvider(listingEntryLimit: 1)

        do {
            _ = try await provider.open(url: fixture.archiveURL)
            XCTFail("Expected resourceLimit")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .resourceLimit)
        }
    }

    func testEncryptedEntryRequiresPasswordBeforeRead() async throws {
        let fixture = try ZIPFixture(entries: ["secret.txt": Data("secret".utf8)], password: "1234")
        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: fixture.archiveURL)
        let encrypted = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory })
        XCTAssertTrue(encrypted.isEncrypted)

        do {
            _ = try await provider.readEntry(id: encrypted.entry.id, maximumBytes: 4096)
            XCTFail("Expected passwordRequired")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .passwordRequired)
        }
    }

    func testRepeatedOpenReplacesThePreviousDocument() async throws {
        let first = try ZIPFixture(entries: ["first.txt": Data("1".utf8)])
        let second = try ZIPFixture(entries: ["second.txt": Data("2".utf8)])
        let provider = ZIPArchiveProvider()

        _ = try await provider.open(url: first.archiveURL)
        let reopened = try await provider.open(url: second.archiveURL)

        XCTAssertEqual(
            reopened.entries.filter { !$0.isDirectory }.map(\.entry.displayPath),
            ["second.txt"]
        )
    }

    func testReadEntryReturnsExactBytes() async throws {
        let expected = Data("压缩包内的真实内容".utf8)
        let fixture = try ZIPFixture(entries: ["文档/内容.txt": expected])
        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: fixture.archiveURL)
        let id = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory }?.entry.id)

        let actual = try await provider.readEntry(id: id, maximumBytes: 1 << 20)

        XCTAssertEqual(actual, expected)
    }

    func testReadEntryRejectsAdvertisedSizeAboveCeiling() async throws {
        let fixture = try ZIPFixture(entries: [
            "large.bin": Data(repeating: 0x41, count: 4097),
        ])
        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: fixture.archiveURL)
        let id = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory }?.entry.id)

        do {
            _ = try await provider.readEntry(id: id, maximumBytes: 4096)
            XCTFail("Expected resourceLimit")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .resourceLimit)
        }
    }

    func testReadEntryRejectsUnknownIdentity() async throws {
        let fixture = try ZIPFixture(entries: ["file.txt": Data("data".utf8)])
        let provider = ZIPArchiveProvider()
        _ = try await provider.open(url: fixture.archiveURL)

        do {
            _ = try await provider.readEntry(id: ArchiveEntryID(), maximumBytes: 4096)
            XCTFail("Expected helperFailed")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .helperFailed)
        }
    }

    func testMaterializeEntryPublishesValidatedBytesBelowBudget() async throws {
        let expected = Data("可安全预览".utf8)
        let fixture = try ZIPFixture(entries: ["文档/预览.txt": expected])
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ArchiveWorkbenchPreview-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: fixture.archiveURL)
        let id = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory }?.entry.id)

        let output = try await provider.materializeEntry(id: id, under: root)

        XCTAssertEqual(try Data(contentsOf: output), expected)
        XCTAssertTrue(output.path.hasPrefix(root.path + "/"))
    }

    func testExtractAllStreamsFilesAndPreservesDirectories() async throws {
        let largePayload = pseudoRandomData(count: 150_000)
        let fixture = try ZIPFixture(entries: [
            "文档/说明.txt": Data("跨平台内容".utf8),
            "图片/封面.bin": largePayload,
        ])
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ArchiveWorkbenchExtract-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ZIPArchiveProvider()
        _ = try await provider.open(url: fixture.archiveURL)

        let result = try await provider.extractAll(under: root)

        XCTAssertEqual(result.completedEntries, 4)
        XCTAssertEqual(
            try Data(contentsOf: root.appending(path: "文档/说明.txt")),
            Data("跨平台内容".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: root.appending(path: "图片/封面.bin")),
            largePayload
        )
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appending(path: "文档").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testExtractAllReportsMonotonicChunkProgress() async throws {
        let payload = pseudoRandomData(count: 150_000)
        let fixture = try ZIPFixture(entries: ["数据/大文件.bin": payload])
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ArchiveWorkbenchProgress-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ZIPArchiveProvider()
        _ = try await provider.open(url: fixture.archiveURL)
        let recorder = ProgressRecorder()

        _ = try await provider.extractAll(under: root) { progress in
            recorder.append(progress)
        }

        let values = recorder.values
        XCTAssertEqual(values.first?.completedBytes, 0)
        XCTAssertEqual(values.last?.completedBytes, UInt64(payload.count))
        XCTAssertEqual(values.last?.completedEntries, values.last?.totalEntries)
        XCTAssertGreaterThan(values.count, 3)
        XCTAssertEqual(values.map(\.completedBytes), values.map(\.completedBytes).sorted())
    }

    func testExtractAllRejectsCaseInsensitivePathCollisionBeforeWriting() async throws {
        let fixture = try ZIPFixture(entries: [
            "A.txt": Data("first".utf8),
            "b.txt": Data("second".utf8),
        ])
        try fixture.replaceArchiveNameBytes(
            matching: Array("b.txt".utf8),
            with: Array("a.txt".utf8)
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ArchiveWorkbenchCollisionScan-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ZIPArchiveProvider()
        _ = try await provider.open(url: fixture.archiveURL)

        do {
            _ = try await provider.extractAll(under: root)
            XCTFail("Expected unsafePath")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .unsafePath)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ZIPExtractionProgress] = []

    var values: [ZIPExtractionProgress] {
        lock.withLock { storage }
    }

    func append(_ value: ZIPExtractionProgress) {
        lock.withLock { storage.append(value) }
    }
}

private func pseudoRandomData(count: Int) -> Data {
    var state: UInt64 = 0x4d595df4d0f33173
    return Data((0..<count).map { _ in
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return UInt8(truncatingIfNeeded: state)
    })
}

private final class ZIPFixture {
    let archiveURL: URL
    private let rootURL: URL

    init(entries: [String: Data], password: String? = nil) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "ArchiveWorkbenchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        process.arguments = ["-q", "-r"]
            + (password.map { ["-P", $0] } ?? [])
            + [archiveURL.path, "."]
        process.currentDirectoryURL = contentsURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
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
