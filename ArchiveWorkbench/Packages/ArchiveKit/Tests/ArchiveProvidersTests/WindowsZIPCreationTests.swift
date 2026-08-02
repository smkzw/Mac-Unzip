import ArchiveDomain
import ArchiveProviders
import Foundation
import XCTest

final class WindowsZIPCreationTests: XCTestCase {
    func testCreatesUTF8ZIPAndSuppressesMacMetadata() async throws {
        let input = try InputTree(entries: [
            "资料/报告.txt": Data("跨平台".utf8),
            ".DS_Store": Data("hidden".utf8),
            "资料/._报告.txt": Data("fork".utf8),
            "__MACOSX/资料/报告.txt": Data("metadata".utf8),
        ])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: output) }
        let provider = ZIPArchiveProvider()

        try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
        let snapshot = try await provider.open(url: output)

        let files = snapshot.entries.filter { !$0.isDirectory }
        XCTAssertEqual(files.map(\.entry.displayPath), ["资料/报告.txt"])
        XCTAssertTrue(files.allSatisfy(\.usesUTF8FileName))
        let id = try XCTUnwrap(files.first?.entry.id)
        let contents = try await provider.readEntry(id: id, maximumBytes: 4096)
        XCTAssertEqual(contents, Data("跨平台".utf8))
        if let interoperabilityPath = ProcessInfo.processInfo.environment["AWB_INTEROP_OUTPUT"] {
            let interoperabilityURL = URL(fileURLWithPath: interoperabilityPath)
            try? FileManager.default.removeItem(at: interoperabilityURL)
            try FileManager.default.copyItem(at: output, to: interoperabilityURL)
        }
    }

    func testPreservesNestedEmptyDirectory() async throws {
        let input = try InputTree(entries: ["说明.txt": Data("内容".utf8)])
        try FileManager.default.createDirectory(
            at: input.rootURL.appending(path: "空资料", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: output) }
        let provider = ZIPArchiveProvider()

        try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
        let snapshot = try await provider.open(url: output)

        XCTAssertEqual(
            snapshot.entries.filter(\.isDirectory).map(\.entry.displayPath),
            ["空资料/"]
        )
    }

    func testCreatesArchiveFromAnEmptySelectedDirectory() async throws {
        let input = try InputTree(entries: [:])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        defer {
            if FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: output)
            }
        }
        let provider = ZIPArchiveProvider()

        try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
        let snapshot = try await provider.open(url: output)

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertTrue(snapshot.entries[0].isDirectory)
        XCTAssertEqual(snapshot.entries[0].entry.displayPath, input.rootURL.lastPathComponent + "/")
    }

    func testMetadataOnlySelectedDirectoryBecomesAnEmptyDirectoryEntry() async throws {
        let input = try InputTree(entries: [".DS_Store": Data("metadata".utf8)])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        defer {
            if FileManager.default.fileExists(atPath: output.path) {
                try? FileManager.default.removeItem(at: output)
            }
        }
        let provider = ZIPArchiveProvider()

        try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
        let snapshot = try await provider.open(url: output)

        XCTAssertEqual(snapshot.entries.count, 1)
        XCTAssertTrue(snapshot.entries[0].isDirectory)
        XCTAssertEqual(snapshot.entries[0].entry.displayPath, input.rootURL.lastPathComponent + "/")
    }

    func testRejectsWindowsReservedDeviceName() async throws {
        let input = try InputTree(entries: ["CON.txt": Data("x".utf8)])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        let provider = ZIPArchiveProvider()

        do {
            try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
            XCTFail("Expected invalidName")
        } catch let error as WindowsZIPProfileError {
            XCTAssertEqual(error, .invalidName("CON.txt"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testRejectsWindowsSuperscriptDeviceAliases() async throws {
        for name in ["COM¹.txt", "LPT².log", "COM³"] {
            let input = try InputTree(entries: [name: Data("x".utf8)])
            let output = input.rootURL.deletingLastPathComponent()
                .appending(path: UUID().uuidString + ".zip")
            let provider = ZIPArchiveProvider()

            do {
                try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
                XCTFail("Expected invalidName for \(name)")
            } catch let error as WindowsZIPProfileError {
                XCTAssertEqual(error, .invalidName(name))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testRejectsCaseInsensitiveCollision() async throws {
        let first = try InputTree(entries: ["Readme.txt": Data("one".utf8)])
        let second = try InputTree(entries: ["README.TXT": Data("two".utf8)])
        let output = first.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        let provider = ZIPArchiveProvider()

        do {
            try await provider.createWindowsZIP(
                at: output,
                inputs: [first.rootURL, second.rootURL]
            )
            XCTFail("Expected collision")
        } catch let error as WindowsZIPProfileError {
            XCTAssertEqual(error, .collision("Readme.txt", "README.TXT"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testExistingOutputIsNeverOverwritten() async throws {
        let input = try InputTree(entries: ["file.txt": Data("new".utf8)])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        try Data("keep".utf8).write(to: output)
        defer { try? FileManager.default.removeItem(at: output) }
        let provider = ZIPArchiveProvider()

        do {
            try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
            XCTFail("Expected outputExists")
        } catch let error as WindowsZIPProfileError {
            XCTAssertEqual(error, .outputExists)
        }
        XCTAssertEqual(try Data(contentsOf: output), Data("keep".utf8))
    }

    func testNormalizesDecomposedUnicodeNameToNFC() async throws {
        let decomposedName = "e\u{301}.txt"
        let input = try InputTree(entries: [decomposedName: Data("accent".utf8)])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: output) }
        let provider = ZIPArchiveProvider()

        try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
        let snapshot = try await provider.open(url: output)

        XCTAssertEqual(snapshot.entries.first?.entry.displayPath, "é.txt")
    }

    func testRejectsSymbolicLinkInput() async throws {
        let input = try InputTree(entries: ["file.txt": Data("data".utf8)])
        try FileManager.default.createSymbolicLink(
            at: input.rootURL.appending(path: "linked.txt"),
            withDestinationURL: input.rootURL.appending(path: "file.txt")
        )
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        let provider = ZIPArchiveProvider()

        do {
            try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
            XCTFail("Expected unsupportedItem")
        } catch let error as WindowsZIPProfileError {
            XCTAssertEqual(error, .unsupportedItem("linked.txt"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testAlreadyCancelledCreationPublishesNothing() async throws {
        let input = try InputTree(entries: ["file.txt": Data("data".utf8)])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        let gate = CreationStartGate()
        let provider = ZIPArchiveProvider()
        let task = Task {
            await gate.wait()
            try await provider.createWindowsZIP(at: output, inputs: [input.rootURL])
        }
        while await !gate.hasWaiter { await Task.yield() }

        task.cancel()
        await gate.open()

        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCancellationDuringLargeFileRemovesStagingAndPublishesNothing() async throws {
        let input = try InputTree(entries: [
            "large.bin": creationPseudoRandomData(count: 2_000_000),
        ])
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        let provider = ZIPArchiveProvider()

        do {
            try await provider.createWindowsZIP(at: output, inputs: [input.rootURL]) { progress in
                if progress.completedBytes > 0 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let stagePrefix = "." + output.lastPathComponent + ".staging-"
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
                .contains { $0.hasPrefix(stagePrefix) }
        )
    }

    func testSameIdentitySameMetadataContentMutationIsRejectedBeforePublish() async throws {
        let original = creationPseudoRandomData(count: 2_000_000)
        let replacement = Data(repeating: 0xA5, count: original.count)
        let input = try InputTree(entries: ["large.bin": original])
        let sourceURL = input.rootURL.appending(path: "large.bin")
        let modificationDate = try XCTUnwrap(
            sourceURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        )
        let mutation = OneShotSourceMutation(
            sourceURL: sourceURL,
            replacement: replacement,
            modificationDate: modificationDate
        )
        let output = input.rootURL.deletingLastPathComponent()
            .appending(path: UUID().uuidString + ".zip")
        let provider = ZIPArchiveProvider()

        do {
            try await provider.createWindowsZIP(at: output, inputs: [input.rootURL]) { progress in
                if progress.completedBytes > 0 { mutation.perform() }
            }
            XCTFail("Expected sourceChanged")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .sourceChanged)
        }

        XCTAssertNil(mutation.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let stagePrefix = "." + output.lastPathComponent + ".staging-"
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
                .contains { $0.hasPrefix(stagePrefix) }
        )
    }
}

private func creationPseudoRandomData(count: Int) -> Data {
    var state: UInt64 = 0x9e3779b97f4a7c15
    return Data((0..<count).map { _ in
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return UInt8(truncatingIfNeeded: state)
    })
}

private final class OneShotSourceMutation: @unchecked Sendable {
    private let lock = NSLock()
    private let sourceURL: URL
    private let replacement: Data
    private let modificationDate: Date
    private var didRun = false
    private var storedError: Error?

    init(sourceURL: URL, replacement: Data, modificationDate: Date) {
        self.sourceURL = sourceURL
        self.replacement = replacement
        self.modificationDate = modificationDate
    }

    var error: Error? {
        lock.withLock { storedError }
    }

    func perform() {
        lock.withLock {
            guard !didRun else { return }
            didRun = true
            do {
                let handle = try FileHandle(forWritingTo: sourceURL)
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: replacement)
                try handle.close()
                try FileManager.default.setAttributes(
                    [.modificationDate: modificationDate],
                    ofItemAtPath: sourceURL.path
                )
            } catch {
                storedError = error
            }
        }
    }
}

private actor CreationStartGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var hasWaiter = false

    func wait() async {
        await withCheckedContinuation { continuation in
            hasWaiter = true
            self.continuation = continuation
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private final class InputTree {
    let rootURL: URL

    init(entries: [String: Data]) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipInput-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (path, data) in entries {
            let url = rootURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
