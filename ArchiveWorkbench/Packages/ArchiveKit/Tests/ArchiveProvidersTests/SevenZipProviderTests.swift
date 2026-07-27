import ArchiveDomain
@testable import ArchiveProviders
import Foundation
import XCTest

/// Tests for the read-only 7z provider backed by the system 7zz binary.
///
/// Fixture-based tests require a real 7zz install and skip gracefully when it is
/// absent. Binary-validation and cancellation tests are deterministic and always
/// run.
final class SevenZipProviderTests: XCTestCase {
    // MARK: - Helpers

    /// Returns a validated 7zz discovery or skips the test when 7zz is missing.
    private func requireValidatedBinary() throws -> SevenZipBinaryDiscovery {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw XCTSkip("7zz is not installed at a trusted location; skipping 7z fixture test.")
        }
        return discovery
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "SevenZipProviderTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs 7zz with an explicit argv array (test scaffolding only, never a shell).
    @discardableResult
    private func run7zz(
        _ binary: String,
        _ arguments: [String],
        in workingDirectory: URL
    ) throws -> (Int32, String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: outData, as: UTF8.self),
            String(decoding: errData, as: UTF8.self)
        )
    }

    /// Creates a .7z archive containing the given files (relative path -> bytes).
    private func makeArchive(
        binary: String,
        files: [String: Data],
        password: String? = nil,
        encryptHeaders: Bool = false
    ) throws -> URL {
        let dir = try makeTempDirectory()
        let sourceDir = dir.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        var names: [String] = []
        for (name, data) in files.sorted(by: { $0.key < $1.key }) {
            let fileURL = sourceDir.appending(path: name)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL)
            names.append(name)
        }
        let archiveURL = dir.appending(path: "archive.7z")
        var args = ["a", "-t7z", "-y"]
        if let password {
            args.append("-p\(password)")
            if encryptHeaders { args.append("-mhe=on") }
        }
        args.append(archiveURL.path)
        args.append(contentsOf: names)
        let (status, _, stderr) = try run7zz(binary, args, in: sourceDir)
        XCTAssertEqual(status, 0, "7zz create failed: \(stderr)")
        return archiveURL
    }

    // MARK: - Binary discovery & validation

    func testDiscoverValidatesSystemBinary() throws {
        let discovery = try requireValidatedBinary()
        XCTAssertTrue(
            discovery.resolvedPath.hasPrefix("/opt/homebrew/")
                || discovery.resolvedPath.hasPrefix("/usr/local/")
        )
        XCTAssertFalse(discovery.version.isEmpty)
        XCTAssertFalse(discovery.architecture.isEmpty)
        XCTAssertEqual(discovery.sha256.count, 64)
        XCTAssertTrue(discovery.sha256.allSatisfy(\.isHexDigit))
    }

    func testCapabilitiesAreReadOnly() {
        XCTAssertEqual(SevenZipProvider.capabilities, [.list, .read, .preview])
    }

    func testDiscoverReturnsNilForMissingCandidates() {
        XCTAssertNil(SevenZipBinaryDiscovery.discover(candidatePaths: [
            "/opt/homebrew/bin/definitely-not-7zz-\(UUID().uuidString)",
            "/usr/local/bin/definitely-not-7zz-\(UUID().uuidString)",
        ]))
    }

    func testValidationRejectsRelativeAndDirectoryCandidates() throws {
        XCTAssertNil(SevenZipBinaryDiscovery.validate(candidate: "relative/7zz"))
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(SevenZipBinaryDiscovery.validate(candidate: dir.path))
    }

    func testValidationRejectsBinaryOutsideTrustedPrefix() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // An executable file that lives outside any trusted prefix must be rejected.
        let fake = dir.appending(path: "7zz")
        try Data("#!/bin/sh\n".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        XCTAssertNil(SevenZipBinaryDiscovery.validate(candidate: fake.path))

        // A symlink resolving outside the trusted prefix must also be rejected,
        // proving symlink resolution happens before the prefix check.
        let link = dir.appending(path: "7zz-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fake)
        XCTAssertNil(SevenZipBinaryDiscovery.validate(candidate: link.path))
    }

    func testValidationRejectsWorldWritableBinary() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "7zz")
        try Data("x".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: fake.path)
        XCTAssertNil(SevenZipBinaryDiscovery.validate(candidate: fake.path))
    }

    // MARK: - Listing & extraction (require 7zz)

    func testOpenListsEntries() async throws {
        let discovery = try requireValidatedBinary()
        let archiveURL = try makeArchive(binary: discovery.resolvedPath, files: [
            "hello.txt": Data("hello world".utf8),
            "docs/notes.txt": Data("notes".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath)

        let snapshot = try await provider.open(url: archiveURL)
        XCTAssertEqual(snapshot.format, .sevenZip)
        let filePaths = snapshot.entries
            .filter { !$0.isDirectory }
            .map(\.entry.displayPath)
            .sorted()
        XCTAssertEqual(filePaths, ["docs/notes.txt", "hello.txt"])
        let hello = snapshot.entries.first { $0.entry.displayPath == "hello.txt" }
        XCTAssertEqual(hello?.uncompressedSize, UInt64("hello world".utf8.count))
    }

    func testReadSingleEntryReturnsExactBytes() async throws {
        let discovery = try requireValidatedBinary()
        let payload = Data("精确的字节内容 12345".utf8)
        let archiveURL = try makeArchive(binary: discovery.resolvedPath, files: ["payload.bin": payload])
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath)

        let snapshot = try await provider.open(url: archiveURL)
        let entry = try XCTUnwrap(snapshot.entries.first { $0.entry.displayPath == "payload.bin" })
        let data = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(data, payload)
    }

    func testEncryptedHeadersReportPasswordRequiredOnOpen() async throws {
        let discovery = try requireValidatedBinary()
        let archiveURL = try makeArchive(
            binary: discovery.resolvedPath,
            files: ["secret.txt": Data("top secret".utf8)],
            password: "CorrectHorse42",
            encryptHeaders: true
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath)

        do {
            _ = try await provider.open(url: archiveURL)
            XCTFail("Expected passwordRequired")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .passwordRequired)
        }
    }

    func testReadEncryptedEntryReportsPasswordRequired() async throws {
        let discovery = try requireValidatedBinary()
        let archiveURL = try makeArchive(
            binary: discovery.resolvedPath,
            files: ["secret.txt": Data("top secret".utf8)],
            password: "CorrectHorse42",
            encryptHeaders: false
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath)

        let snapshot = try await provider.open(url: archiveURL)
        let entry = try XCTUnwrap(snapshot.entries.first { $0.entry.displayPath == "secret.txt" })
        XCTAssertTrue(entry.isEncrypted)
        do {
            _ = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
            XCTFail("Expected passwordRequired")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .passwordRequired)
        }
    }

    func testExtractAllPublishesFiles() async throws {
        let discovery = try requireValidatedBinary()
        let archiveURL = try makeArchive(binary: discovery.resolvedPath, files: [
            "a.txt": Data("AAA".utf8),
            "nested/b.txt": Data("BBB".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath)
        _ = try await provider.open(url: archiveURL)

        let outputRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let result = try await provider.extractAll(under: outputRoot)
        XCTAssertGreaterThanOrEqual(result.completedEntries, 2)
        XCTAssertEqual(try Data(contentsOf: outputRoot.appending(path: "a.txt")), Data("AAA".utf8))
        XCTAssertEqual(try Data(contentsOf: outputRoot.appending(path: "nested/b.txt")), Data("BBB".utf8))
    }

    // MARK: - Cancellation

    func testCancellationKillsRunningHelper() async throws {
        // A long-running child proves the runner observes cancellation and kills
        // the whole process group. /bin/sleep is universally available on macOS.
        let task = Task {
            try SevenZipProcessRunner().run(
                executablePath: "/bin/sleep",
                arguments: ["30"],
                timeoutSeconds: 60,
                maximumStdoutBytes: 1024
            )
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as SevenZipHelperError {
            XCTAssertEqual(error, .cancelled)
        }
    }
}
