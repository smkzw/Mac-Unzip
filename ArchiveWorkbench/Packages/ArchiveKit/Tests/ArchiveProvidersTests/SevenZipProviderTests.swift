import ArchiveDomain
import ArchiveSecurity
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

    /// Prefers the release-pinned App/Binaries/7zz (or MACUNZIP_PINNED_7ZZ).
    /// CI sets MACUNZIP_REQUIRE_PINNED_7ZZ=1 so missing prep fails hard (no silent skip).
    private func requireValidatedBinary() throws -> SevenZipBinaryDiscovery {
        if let pinned = try pinnedDiscoveryIfAvailable() {
            return pinned
        }
        if ProcessInfo.processInfo.environment["MACUNZIP_REQUIRE_PINNED_7ZZ"] == "1" {
            XCTFail("Pinned 7zz required. Run ArchiveWorkbench/Scripts/prepare_7zz.sh before tests.")
            throw SevenZipProviderError.binaryNotFound
        }
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw XCTSkip("7zz is not installed at a trusted location; skipping 7z fixture test.")
        }
        return discovery
    }

    private func pinnedDiscoveryIfAvailable() throws -> SevenZipBinaryDiscovery? {
        let candidates: [String] = {
            var paths: [String] = []
            if let override = ProcessInfo.processInfo.environment["MACUNZIP_PINNED_7ZZ"], !override.isEmpty {
                paths.append(override)
            }
            var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0..<10 {
                paths.append(dir.appendingPathComponent("App/Binaries/7zz").path)
                // #file is under Packages/ArchiveKit/Tests/...; also try repo App/Binaries via parents.
                dir = dir.deletingLastPathComponent()
            }
            // Absolute walk from CWD used by `swift test`.
            paths.append(
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("../../App/Binaries/7zz").path
            )
            paths.append(
                URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent("App/Binaries/7zz").path
            )
            return paths
        }()

        for path in candidates {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            guard let hash = SevenZipBinaryDiscovery.sha256(ofFileAt: url.path),
                  hash == SevenZipBinaryDiscovery.pinnedBundledSHA256 else {
                continue
            }
            // validate() rejects paths outside bundle/homebrew; construct discovery directly
            // for the prepared workspace binary used by tests/CI.
            guard let probe = try? probePinned(url.path) else { continue }
            return SevenZipBinaryDiscovery(
                resolvedPath: url.path,
                version: probe.version,
                architecture: probe.architecture,
                sha256: hash,
                origin: .bundledPinned
            )
        }
        return nil
    }

    private func probePinned(_ path: String) throws -> (version: String, architecture: String) {
        let result = try SevenZipProcessRunner().run(
            executablePath: path,
            arguments: ["i"],
            timeoutSeconds: 10,
            maximumStdoutBytes: 1 << 20
        )
        XCTAssertEqual(result.exitStatus, 0)
        let text = String(decoding: result.stdout, as: UTF8.self)
        for line in text.split(separator: "\n") where line.contains("7-Zip") {
            // Banner form: "7-Zip (z) 26.03 (arm64) : ..."
            let pattern = #"7-Zip \([^)]+\) (\d+(?:\.\d+)*) \(([^)]+)\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: String(line),
                    range: NSRange(line.startIndex..<line.endIndex, in: line)
                  ),
                  let versionRange = Range(match.range(at: 1), in: line),
                  let archRange = Range(match.range(at: 2), in: line) else {
                continue
            }
            return (String(line[versionRange]), String(line[archRange]))
        }
        struct ProbeFailed: Error {}
        throw ProbeFailed()
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
        switch discovery.origin {
        case .bundledPinned:
            XCTAssertEqual(discovery.sha256, SevenZipBinaryDiscovery.pinnedBundledSHA256)
            XCTAssertEqual(discovery.version, SevenZipBinaryDiscovery.pinnedBundledVersion)
            XCTAssertEqual(discovery.architecture, "arm64")
        case .externalFallback:
            XCTAssertTrue(
                discovery.resolvedPath.hasPrefix("/opt/homebrew/")
                    || discovery.resolvedPath.hasPrefix("/usr/local/")
            )
        }
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
        let provider = SevenZipProvider(
            binaryPath: discovery.resolvedPath,
            binarySHA256: discovery.sha256
        )

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
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)

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
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)

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
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)

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

    func testContentEncryptionRoundTripWithCorrectPassword() async throws {
        let discovery = try requireValidatedBinary()
        let payload = Data("7z content encryption plaintext".utf8)
        let archiveURL = try makeArchive(
            binary: discovery.resolvedPath,
            files: ["secret.txt": payload],
            password: "ContentPass99",
            encryptHeaders: false
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
        let snapshot = try await provider.openWithPassword(
            url: archiveURL,
            password: "ContentPass99"
        )
        let entry = try XCTUnwrap(snapshot.entries.first { $0.entry.displayPath == "secret.txt" })
        let readBack = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(readBack, payload)

        let out = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        let materialized = try await provider.materializeEntry(id: entry.entry.id, under: out)
        XCTAssertEqual(try Data(contentsOf: materialized), payload)
    }

    func testHeaderEncryptionRoundTripWithCorrectPassword() async throws {
        let discovery = try requireValidatedBinary()
        let payload = Data("7z header encryption plaintext".utf8)
        let archiveURL = try makeArchive(
            binary: discovery.resolvedPath,
            files: ["secret.txt": payload],
            password: "HeaderPass99",
            encryptHeaders: true
        )
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
        let snapshot = try await provider.openWithPassword(
            url: archiveURL,
            password: "HeaderPass99"
        )
        let entry = try XCTUnwrap(snapshot.entries.first { $0.entry.displayPath == "secret.txt" })
        let readBack = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(readBack, payload)

        let out = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: out) }
        let materialized = try await provider.materializeEntry(id: entry.entry.id, under: out)
        XCTAssertEqual(try Data(contentsOf: materialized), payload)
    }

    func testExtractAllPublishesFiles() async throws {
        let discovery = try requireValidatedBinary()
        let archiveURL = try makeArchive(binary: discovery.resolvedPath, files: [
            "a.txt": Data("AAA".utf8),
            "nested/b.txt": Data("BBB".utf8),
        ])
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }
        let provider = SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
        _ = try await provider.open(url: archiveURL)

        let outputRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: outputRoot) }
        let result = try await provider.extractAll(under: outputRoot)
        XCTAssertGreaterThanOrEqual(result.completedEntries, 2)
        XCTAssertEqual(try Data(contentsOf: outputRoot.appending(path: "a.txt")), Data("AAA".utf8))
        XCTAssertEqual(try Data(contentsOf: outputRoot.appending(path: "nested/b.txt")), Data("BBB".utf8))
    }

    // MARK: - Cancellation / private-input backpressure

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

    func testTimeoutDuringUnreadStdinAndFloodingStdout() throws {
        let script = try makeFloodingUnreadStdinScript()
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        // Large but within the 16 KiB private-input cap — enough to backpressure
        // when the child never reads stdin while flooding stdout.
        let password = SecurePassword(copying: [UInt8](repeating: 0x41, count: 12 * 1024))
        XCTAssertFalse(password.isZeroed)

        let clock = ContinuousClock()
        let started = clock.now
        do {
            _ = try SevenZipProcessRunner().run(
                executablePath: script.path,
                arguments: [],
                timeoutSeconds: 1,
                maximumStdoutBytes: 4_096,
                maximumStderrBytes: 4_096,
                stdinPassword: password
            )
            XCTFail("Expected timeout")
        } catch let error as SevenZipHelperError {
            XCTAssertEqual(error, .timedOut)
        }
        XCTAssertTrue(password.isZeroed)
        XCTAssertLessThan(started.duration(to: clock.now), Duration.seconds(3))
    }

    func testCancellationDuringUnreadStdinAndFloodingStdout() async throws {
        let script = try makeFloodingUnreadStdinScript()
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let password = SecurePassword(copying: [UInt8](repeating: 0x42, count: 12 * 1024))
        XCTAssertFalse(password.isZeroed)

        let clock = ContinuousClock()
        let started = clock.now
        let task = Task {
            try SevenZipProcessRunner().run(
                executablePath: script.path,
                arguments: [],
                timeoutSeconds: 30,
                maximumStdoutBytes: 4_096,
                maximumStderrBytes: 4_096,
                stdinPassword: password
            )
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as SevenZipHelperError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertTrue(password.isZeroed)
        XCTAssertLessThan(started.duration(to: clock.now), Duration.seconds(3))
    }

    func testPrivateInputAbove16KiBIsRejected() throws {
        let oversized = SecurePassword(
            copying: [UInt8](repeating: 0x43, count: SevenZipProcessRunner.maximumPrivateInputBytes + 1)
        )
        do {
            _ = try SevenZipProcessRunner().run(
                executablePath: "/bin/cat",
                arguments: [],
                timeoutSeconds: 2,
                maximumStdoutBytes: 1024,
                stdinPassword: oversized
            )
            XCTFail("Expected privateInputTooLarge")
        } catch let error as SevenZipHelperError {
            XCTAssertEqual(
                error,
                .privateInputTooLarge(maximumBytes: SevenZipProcessRunner.maximumPrivateInputBytes)
            )
        }
        XCTAssertTrue(oversized.isZeroed)
    }

    /// Child that never reads stdin and continuously floods stdout — exercises
    /// non-blocking private writes under backpressure (not a plain /bin/sleep).
    private func makeFloodingUnreadStdinScript() throws -> URL {
        let root = try makeTempDirectory()
        let script = root.appendingPathComponent("flood-unread-stdin.sh")
        let body = """
        #!/bin/sh
        # Intentionally ignore stdin and flood stdout until killed.
        exec 0</dev/null
        while true; do
          dd if=/dev/zero bs=65536 count=1 2>/dev/null || printf '%65536s' x
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        return script
    }
}
