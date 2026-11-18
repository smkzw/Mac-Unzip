import ArchiveDomain
import ArchiveProviders
import Foundation
import Testing

// MARK: - TAR fixture creation helpers

private enum TARFixture {
    /// Creates a temporary directory with test files and returns its URL.
    static func createSourceDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "tar-test-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create a simple text file
        let helloURL = dir.appending(path: "hello.txt")
        try "Hello, TAR world!\n".write(to: helloURL, atomically: true, encoding: .utf8)

        // Create a subdirectory with a file
        let subDir = dir.appending(path: "subdir", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let nestedURL = subDir.appending(path: "nested.txt")
        try "Nested content\n".write(to: nestedURL, atomically: true, encoding: .utf8)

        return dir
    }

    /// Creates a .tar archive from a source directory using the system tar command.
    static func createTAR(from sourceDir: URL, compression: String = "") throws -> URL {
        let ext = compression.isEmpty ? "tar" : "tar.\(compression)"
        let tarURL = FileManager.default.temporaryDirectory
            .appending(path: "test-\(UUID().uuidString).\(ext)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        var args = ["-c", "-f", tarURL.path]
        switch compression {
        case "gz": args.append("-z")
        case "bz2": args.append("-j")
        case "xz": args.append("-J")
        default: break
        }
        args.append("-C")
        args.append(sourceDir.path)
        args.append(".")
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = pipe.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "TARFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "tar failed: \(String(decoding: stderr, as: UTF8.self))"
            ])
        }
        return tarURL
    }

    /// Creates a .tar archive with a symlink entry (for security testing).
    static func createTARWithSymlink() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "tar-symlink-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Create a regular file
        let targetURL = dir.appending(path: "target.txt")
        try "target content\n".write(to: targetURL, atomically: true, encoding: .utf8)

        // Create a symlink
        let linkURL = dir.appending(path: "evil-link")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let tarURL = FileManager.default.temporaryDirectory
            .appending(path: "symlink-\(UUID().uuidString).tar")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-c", "-h", "-f", tarURL.path, "-C", dir.path, "."]
        // Note: -h follows symlinks; without -h, tar stores the symlink itself
        // We want to store the symlink, so do NOT use -h
        process.arguments = ["-c", "-f", tarURL.path, "-C", dir.path, "."]

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = pipe.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "TARFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "tar failed: \(String(decoding: stderr, as: UTF8.self))"
            ])
        }
        return tarURL
    }

    /// Creates a .tar archive with a path traversal entry using raw tar manipulation.
    /// Uses the system tar with a specially crafted directory structure.
    static func createTARWithTraversal() throws -> URL {
        // Create a tar with a path traversal entry by using a directory named ".."
        // Actually, we'll create it using Python's tarfile for precise control
        let tarURL = FileManager.default.temporaryDirectory
            .appending(path: "traversal-\(UUID().uuidString).tar")

        let script = """
import tarfile, io, sys
with tarfile.open(sys.argv[1], 'w') as tar:
    data = b'evil content'
    info = tarfile.TarInfo(name='../../etc/passwd')
    info.size = len(data)
    tar.addfile(info, io.BytesIO(data))
"""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, tarURL.path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = pipe.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "TARFixture", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "python3 tarfile failed: \(String(decoding: stderr, as: UTF8.self))"
            ])
        }
        return tarURL
    }

    static func cleanup(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - Tests

@Suite("TARArchiveProvider")
struct TARArchiveProviderTests {

    @Test("libarchive version is available")
    func libarchiveVersion() {
        let version = TARArchiveProvider.libarchiveVersion
        #expect(version.contains("libarchive"))
    }

    @Test("list plain .tar entries")
    func listPlainTAR() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir)
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        #expect(snapshot.format == .tar)
        #expect(snapshot.entries.count >= 2) // hello.txt + subdir/nested.txt (+ possibly subdir itself)

        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("hello.txt"))
        #expect(paths.contains("subdir/nested.txt"))
    }

    @Test("list .tar.gz entries")
    func listTarGz() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir, compression: "gz")
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        #expect(snapshot.format == .gzip)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("hello.txt"))
        #expect(paths.contains("subdir/nested.txt"))
    }

    @Test("list .tar.bz2 entries")
    func listTarBz2() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir, compression: "bz2")
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        #expect(snapshot.format == .bzip2)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("hello.txt"))
    }

    @Test("list .tar.xz entries")
    func listTarXz() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir, compression: "xz")
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        #expect(snapshot.format == .xz)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("hello.txt"))
    }

    @Test("read entry content from .tar")
    func readEntryContent() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir)
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        guard let helloEntry = snapshot.entries.first(where: { $0.entry.displayPath == "hello.txt" }) else {
            Issue.record("hello.txt not found in archive")
            return
        }

        let data = try await provider.readEntry(id: helloEntry.entry.id, maximumBytes: 1024)
        let content = String(decoding: data, as: UTF8.self)
        #expect(content == "Hello, TAR world!\n")
    }

    @Test("read entry content from .tar.gz")
    func readEntryContentGz() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir, compression: "gz")
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        guard let helloEntry = snapshot.entries.first(where: { $0.entry.displayPath == "hello.txt" }) else {
            Issue.record("hello.txt not found in archive")
            return
        }

        let data = try await provider.readEntry(id: helloEntry.entry.id, maximumBytes: 1024)
        let content = String(decoding: data, as: UTF8.self)
        #expect(content == "Hello, TAR world!\n")
    }

    @Test("extract all entries from .tar")
    func extractAll() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir)
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        let extractDir = FileManager.default.temporaryDirectory
            .appending(path: "tar-extract-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        tempURLs.append(extractDir)

        let result = try await provider.extractAll(under: extractDir)
        #expect(result.completedEntries >= 2)
        #expect(result.expandedBytes > 0)

        // Verify extracted content
        let helloURL = extractDir.appending(path: "hello.txt")
        let content = try String(contentsOf: helloURL, encoding: .utf8)
        #expect(content == "Hello, TAR world!\n")

        let nestedURL = extractDir.appending(path: "subdir/nested.txt")
        let nestedContent = try String(contentsOf: nestedURL, encoding: .utf8)
        #expect(nestedContent == "Nested content\n")
    }

    @Test("reject path traversal entries")
    func rejectPathTraversal() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let tarURL = try TARFixture.createTARWithTraversal()
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        do {
            _ = try await provider.open(url: tarURL)
            Issue.record("Expected unsafePath error for traversal entry")
        } catch let error as ArchiveError {
            #expect(error == .unsafePath)
        }
    }

    @Test("list symlink entries as non-extractable without failing open")
    func listSymlinksAsNonExtractable() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let tarURL = try TARFixture.createTARWithSymlink()
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)
        let link = try #require(snapshot.entries.first { $0.isSymbolicLink })
        #expect(link.isExtractable == false)
        let regular = try #require(snapshot.entries.first { $0.entry.displayPath.contains("target.txt") })
        #expect(regular.isExtractable == true)

        do {
            _ = try await provider.readEntry(id: link.entry.id, maximumBytes: 4096)
            Issue.record("Expected symlinkRejected on read")
        } catch let error as TARProviderError {
            guard case .symlinkRejected = error else {
                Issue.record("Expected symlinkRejected, got \(error)")
                return
            }
        }

        let out = FileManager.default.temporaryDirectory
            .appending(path: "tar-symlink-out-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        tempURLs.append(out)
        do {
            _ = try await provider.materializeEntry(id: link.entry.id, under: out)
            Issue.record("Expected symlinkRejected on materialize")
        } catch let error as TARProviderError {
            guard case .symlinkRejected = error else {
                Issue.record("Expected symlinkRejected, got \(error)")
                return
            }
        }
    }

    @Test("extractAll rejects symlink archive before any write")
    func extractAllRejectsSymlinkBeforeWrite() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }
        let tarURL = try TARFixture.createTARWithSymlink()
        tempURLs.append(tarURL)
        let provider = TARArchiveProvider()
        _ = try await provider.open(url: tarURL)
        let out = FileManager.default.temporaryDirectory
            .appending(path: "tar-extract-symlink-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        tempURLs.append(out)
        do {
            _ = try await provider.extractAll(under: out)
            Issue.record("Expected symlinkRejected before write")
        } catch let error as TARProviderError {
            guard case .symlinkRejected = error else {
                Issue.record("Expected symlinkRejected, got \(error)")
                return
            }
        }
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []
        #expect(remaining.isEmpty)
    }

    @Test("empty gzip is not empty TAR; empty tar lists; damaged tar is openFailed")
    func emptyAndDamagedFormats() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let emptyTar = FileManager.default.temporaryDirectory
            .appending(path: "empty-\(UUID().uuidString).tar")
        tempURLs.append(emptyTar)
        try runProcess("/usr/bin/tar", ["-cf", emptyTar.path, "-T", "/dev/null"])

        let emptyGz = FileManager.default.temporaryDirectory
            .appending(path: "empty-\(UUID().uuidString).gz")
        tempURLs.append(emptyGz)
        try runProcess("/bin/bash", ["-lc", ": | gzip > \(emptyGz.path)"])

        let badTar = FileManager.default.temporaryDirectory
            .appending(path: "bad-\(UUID().uuidString).tar")
        tempURLs.append(badTar)
        try Data("not-a-tar".utf8).write(to: badTar)

        let provider = TARArchiveProvider()
        let emptySnapshot = try await provider.open(url: emptyTar)
        #expect(emptySnapshot.entries.isEmpty)

        do {
            _ = try await provider.open(url: emptyGz)
            Issue.record("Expected notTAR for empty gzip")
        } catch let error as TARProviderError {
            guard case .notTAR = error else {
                Issue.record("Expected notTAR, got \(error)")
                return
            }
        }

        do {
            _ = try await provider.open(url: badTar)
            Issue.record("Expected openFailed for damaged tar")
        } catch let error as TARProviderError {
            guard case .openFailed = error else {
                Issue.record("Expected openFailed, got \(error)")
                return
            }
        }
    }

    @Test("replaced archive file is rejected on read")
    func rejectsStaleArchiveIdentity() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }
        let src = try TARFixture.createSourceDirectory()
        tempURLs.append(src)
        let tarURL = try TARFixture.createTAR(from: src)
        tempURLs.append(tarURL)
        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)
        let hello = try #require(snapshot.entries.first { $0.entry.displayPath.hasSuffix("hello.txt") })

        // Replace the archive file after open.
        let otherSrc = try TARFixture.createSourceDirectory()
        tempURLs.append(otherSrc)
        let replacement = try TARFixture.createTAR(from: otherSrc)
        tempURLs.append(replacement)
        try FileManager.default.removeItem(at: tarURL)
        try FileManager.default.copyItem(at: replacement, to: tarURL)

        do {
            _ = try await provider.readEntry(id: hello.entry.id, maximumBytes: 4096)
            Issue.record("Expected corruptedArchive after replacement")
        } catch let error as ArchiveError {
            #expect(error == .corruptedArchive)
        }
    }

    @Test("create plain .tar archive")
    func createPlainTAR() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        // Create source files
        let srcDir = FileManager.default.temporaryDirectory
            .appending(path: "tar-create-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        tempURLs.append(srcDir)

        let file1 = srcDir.appending(path: "file1.txt")
        try "Content one\n".write(to: file1, atomically: true, encoding: .utf8)
        let file2 = srcDir.appending(path: "file2.txt")
        try "Content two\n".write(to: file2, atomically: true, encoding: .utf8)

        // Create the archive
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "created-\(UUID().uuidString).tar")
        tempURLs.append(outputURL)

        let provider = TARArchiveProvider()
        try await provider.createArchive(at: outputURL, inputs: [file1, file2])

        // Verify by re-opening
        let snapshot = try await provider.open(url: outputURL)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("file1.txt"))
        #expect(paths.contains("file2.txt"))

        // Verify content
        guard let entry1 = snapshot.entries.first(where: { $0.entry.displayPath == "file1.txt" }) else {
            Issue.record("file1.txt not found")
            return
        }
        let data = try await provider.readEntry(id: entry1.entry.id, maximumBytes: 1024)
        #expect(String(decoding: data, as: UTF8.self) == "Content one\n")
    }

    @Test("create .tar.gz archive")
    func createTarGz() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = FileManager.default.temporaryDirectory
            .appending(path: "tar-create-gz-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        tempURLs.append(srcDir)

        let file1 = srcDir.appending(path: "data.txt")
        try String(repeating: "compressible data\n", count: 100).write(to: file1, atomically: true, encoding: .utf8)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "created-\(UUID().uuidString).tar.gz")
        tempURLs.append(outputURL)

        let provider = TARArchiveProvider()
        try await provider.createArchive(at: outputURL, inputs: [file1])

        // Verify by re-opening
        let snapshot = try await provider.open(url: outputURL)
        #expect(snapshot.format == .gzip)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("data.txt"))
    }

    @Test("create .tar.xz archive")
    func createTarXz() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = FileManager.default.temporaryDirectory
            .appending(path: "tar-create-xz-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        tempURLs.append(srcDir)

        let file1 = srcDir.appending(path: "data.txt")
        try "xz test content\n".write(to: file1, atomically: true, encoding: .utf8)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "created-\(UUID().uuidString).tar.xz")
        tempURLs.append(outputURL)

        let provider = TARArchiveProvider()
        try await provider.createArchive(at: outputURL, inputs: [file1])

        let snapshot = try await provider.open(url: outputURL)
        #expect(snapshot.format == .xz)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("data.txt"))
    }

    @Test("create .tar.zst archive")
    func createTarZst() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = FileManager.default.temporaryDirectory
            .appending(path: "tar-create-zst-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        tempURLs.append(srcDir)

        let file1 = srcDir.appending(path: "data.txt")
        try "zstd test content\n".write(to: file1, atomically: true, encoding: .utf8)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "created-\(UUID().uuidString).tar.zst")
        tempURLs.append(outputURL)

        let provider = TARArchiveProvider()
        try await provider.createArchive(at: outputURL, inputs: [file1])

        let snapshot = try await provider.open(url: outputURL)
        #expect(snapshot.format == .zstandard)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        #expect(paths.contains("data.txt"))
    }

    @Test("materialize entry for preview")
    func materializePreview() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir)
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        guard let helloEntry = snapshot.entries.first(where: { $0.entry.displayPath == "hello.txt" }) else {
            Issue.record("hello.txt not found")
            return
        }

        let previewDir = FileManager.default.temporaryDirectory
            .appending(path: "tar-preview-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
        tempURLs.append(previewDir)

        let materializedURL = try await provider.materializeEntry(id: helloEntry.entry.id, under: previewDir)
        let content = try String(contentsOf: materializedURL, encoding: .utf8)
        #expect(content == "Hello, TAR world!\n")
    }

    @Test("resource budget enforcement on read")
    func resourceBudgetOnRead() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir)
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        guard let helloEntry = snapshot.entries.first(where: { $0.entry.displayPath == "hello.txt" }) else {
            Issue.record("hello.txt not found")
            return
        }

        // Request with a maximum smaller than the file size
        do {
            _ = try await provider.readEntry(id: helloEntry.entry.id, maximumBytes: 5)
            Issue.record("Expected resourceLimit error")
        } catch let error as ArchiveError {
            #expect(error == .resourceLimit)
        }
    }

    @Test("directory entries are marked correctly")
    func directoryEntries() async throws {
        var tempURLs: [URL] = []
        defer { TARFixture.cleanup(tempURLs) }

        let srcDir = try TARFixture.createSourceDirectory()
        tempURLs.append(srcDir)
        let tarURL = try TARFixture.createTAR(from: srcDir)
        tempURLs.append(tarURL)

        let provider = TARArchiveProvider()
        let snapshot = try await provider.open(url: tarURL)

        let dirEntries = snapshot.entries.filter(\.isDirectory)
        let fileEntries = snapshot.entries.filter { !$0.isDirectory }

        #expect(dirEntries.contains { $0.entry.displayPath == "subdir" })
        #expect(fileEntries.contains { $0.entry.displayPath == "hello.txt" })
        #expect(fileEntries.contains { $0.entry.displayPath == "subdir/nested.txt" })
    }

    private func runProcess(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "TARArchiveProviderTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}
