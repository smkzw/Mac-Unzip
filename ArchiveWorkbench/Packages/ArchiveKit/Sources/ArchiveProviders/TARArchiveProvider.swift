import ArchiveDomain
import ArchiveSecurity
import CLibArchiveBridge
import Foundation

// MARK: - TAR provider backed by libarchive
//
// Design principles (from handoff):
// - TAR 及 gzip/bzip2/xz/zstd 组合: supports .tar, .tar.gz, .tgz, .tar.bz2,
//   .tar.xz, .tar.zst via libarchive's transparent compression handling.
// - TAR/filter/ISO 计划走 libarchive: this provider uses the system libarchive
//   (installed via Homebrew at /opt/homebrew/opt/libarchive).
// - provider 能力必须按真实运行时发现和验证: capabilities are gated on
//   libarchive being available at compile time (always true on macOS with
//   Homebrew libarchive installed).
// - 不允许 mutation 静默 fallback 到不同引擎: creation uses libarchive
//   exclusively; no fallback to system tar or 7zz.
// - Security: reject symlinks, hardlinks, absolute paths, traversal; enforce
//   resource budgets; use ArchivePathPolicy + libarchive's built-in sanitization.

// MARK: - AE_IF* constants (C macros not imported by Swift)

private let AE_IFMT: mode_t = 0o170000
private let AE_IFDIR: mode_t = 0o040000
private let AE_IFREG: mode_t = 0o100000
private let AE_IFLNK: mode_t = 0o120000

// MARK: - TAR-specific errors

public enum TARProviderError: Error, Equatable, Sendable {
    /// libarchive reported an unrecoverable error during the operation.
    case libarchiveFailed(code: Int32, message: String)
    /// Extraction of a symbolic link was requested; listing may still succeed.
    case symlinkRejected(path: String)
    /// Extraction of a hard link was requested; listing may still succeed.
    case hardlinkRejected(path: String)
    /// Extraction of a special file (device, socket, fifo) was requested.
    case specialFileRejected(path: String)
    /// The archive could not be opened or is not a recognized TAR format.
    case openFailed(message: String)
    /// Payload is gzip/bzip2/xz/zstd but not a TAR stream.
    case notTAR(message: String)
    /// A write operation failed during archive creation.
    case createFailed(message: String)
}

// MARK: - Compression format for creation

public enum TARCompression: String, CaseIterable, Sendable {
    case none
    case gzip
    case bzip2
    case xz
    case zstd

    /// Infer compression from a file extension or compound extension.
    public static func fromFileName(_ fileName: String) -> TARCompression {
        let lower = fileName.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .gzip }
        if lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tbz2") { return .bzip2 }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") { return .xz }
        if lower.hasSuffix(".tar.zst") || lower.hasSuffix(".tar.zstd") { return .zstd }
        return .none
    }

    /// The libarchive filter name for diagnostics.
    var filterName: String {
        switch self {
        case .none: return "none"
        case .gzip: return "gzip"
        case .bzip2: return "bzip2"
        case .xz: return "xz"
        case .zstd: return "zstd"
        }
    }
}

// MARK: - Extraction result

public struct TARExtractionResult: Equatable, Sendable {
    public let completedEntries: Int
    public let expandedBytes: UInt64

    public init(completedEntries: Int, expandedBytes: UInt64) {
        self.completedEntries = completedEntries
        self.expandedBytes = expandedBytes
    }
}

// MARK: - Provider

public actor TARArchiveProvider: ArchiveProvider {
    private var archiveURL: URL?
    private var entriesByID: [ArchiveEntryID: ArchiveEntrySnapshot] = [:]
    private var ordinalsByID: [ArchiveEntryID: Int] = [:]
    private var openedIdentity: ArchiveFileIdentity?
    private let listingEntryLimit: Int

    /// Capabilities: list, read, preview, create.
    public static let capabilities: Set<ArchiveAction> = [.list, .read, .preview, .create]

    public init(listingEntryLimit: Int = 1_000_000) {
        self.listingEntryLimit = listingEntryLimit
    }

    private struct ArchiveFileIdentity: Equatable, Sendable {
        let path: String
        let fileSize: UInt64
        let modificationTime: TimeInterval
        let device: UInt64
        let inode: UInt64

        static func capture(url: URL) throws -> ArchiveFileIdentity {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey
            ])
            let resolved = url.resolvingSymlinksInPath()
            var status = stat()
            let statResult = resolved.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return stat(path, &status)
            }
            guard statResult == 0 else {
                throw TARProviderError.openFailed(message: "stat failed for archive identity")
            }
            return ArchiveFileIdentity(
                path: resolved.path,
                fileSize: UInt64(values.fileSize ?? 0),
                modificationTime: values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0,
                device: UInt64(status.st_dev),
                inode: UInt64(status.st_ino)
            )
        }
    }

    private enum MemberKind: Equatable, Sendable {
        case directory
        case regular
        case symlink
        case hardlink
        case special
    }

    /// Returns the libarchive version string for diagnostics.
    public static var libarchiveVersion: String {
        String(cString: archive_version_string())
    }

    // MARK: - ArchiveProvider conformance

    public func open(url: URL) throws -> ArchiveDocumentSnapshot {
        archiveURL = nil
        entriesByID = [:]
        ordinalsByID = [:]
        openedIdentity = nil

        let identity = try ArchiveFileIdentity.capture(url: url)
        let snapshots = try listEntries(url: url)
        archiveURL = url
        openedIdentity = identity
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        ordinalsByID = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map {
            ($0.element.entry.id, $0.offset)
        })

        let format = Self.formatForURL(url)
        return ArchiveDocumentSnapshot(sourceURL: url, format: format, entries: snapshots)
    }

    public func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data {
        let snapshot = try resolvedSnapshot(id: id)
        try rejectNonExtractable(snapshot)
        guard snapshot.uncompressedSize <= maximumBytes else {
            throw ArchiveError.resourceLimit
        }
        guard let ordinal = ordinalsByID[id], let archiveURL else {
            throw ArchiveError.helperFailed
        }
        return try extractEntryData(
            url: archiveURL,
            ordinal: ordinal,
            expectedPath: snapshot.entry.displayPath,
            expectedKind: memberKind(of: snapshot),
            expectedSize: snapshot.uncompressedSize,
            maximumBytes: maximumBytes
        )
    }

    // MARK: - Preview / materialize

    public func materializeEntry(
        id: ArchiveEntryID,
        under rootURL: URL,
        budget: ResourceBudget = .previewDefault
    ) throws -> URL {
        try Task.checkCancellation()
        let snapshot = try resolvedSnapshot(id: id)
        try rejectNonExtractable(snapshot)
        guard let ordinal = ordinalsByID[id], let archiveURL else { throw ArchiveError.helperFailed }
        let decision = budget.evaluate(ResourceEstimate(
            compressedBytes: snapshot.compressedSize,
            expandedBytes: snapshot.uncompressedSize,
            entries: 1,
            depth: 1
        ))
        guard decision == .allow else { throw ArchiveError.resourceLimit }
        let targetPath = snapshot.entry.displayPath
        let expectedKind = memberKind(of: snapshot)
        let expectedSize = snapshot.uncompressedSize
        let maximumBytes = budget.maxExpandedBytes
        let output = try SecureFileMaterializer(rootURL: rootURL).write(
            relativePath: targetPath
        ) { writer in
            try self.withReader(at: archiveURL) { reader in
                try self.seekToMember(
                    reader: reader,
                    ordinal: ordinal,
                    expectedPath: targetPath,
                    expectedKind: expectedKind,
                    expectedSize: expectedSize
                )
                var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
                var written: UInt64 = 0
                while true {
                    try Task.checkCancellation()
                    let bytesRead = archive_read_data(reader, &buffer, buffer.count)
                    if bytesRead == 0 { break }
                    if bytesRead < 0 {
                        throw TARProviderError.libarchiveFailed(code: Int32(bytesRead), message: self.lastError(reader))
                    }
                    written += UInt64(bytesRead)
                    guard written <= maximumBytes else { throw ArchiveError.resourceLimit }
                    try writer.write(Data(buffer[..<bytesRead]))
                }
            }
        }
        try Task.checkCancellation()
        return output
    }

    // MARK: - Extract all

    public func extractAll(
        under rootURL: URL,
        budget: ResourceBudget = .extractionDefault,
        progress: @Sendable (SevenZipExtractionProgress) -> Void = { _ in }
    ) throws -> TARExtractionResult {
        try Task.checkCancellation()
        try ensureArchiveUnchanged()
        guard let archiveURL else { throw ArchiveError.helperFailed }

        let ordered = entriesByID.keys.compactMap { id -> (Int, ArchiveEntrySnapshot)? in
            guard let ordinal = ordinalsByID[id], let snapshot = entriesByID[id] else { return nil }
            return (ordinal, snapshot)
        }.sorted { $0.0 < $1.0 }.map(\.1)

        // Conservative product rule: any non-extractable member aborts before writes.
        for snapshot in ordered {
            try rejectNonExtractable(snapshot, allowDirectory: true)
        }

        var compressedBytes: UInt64 = 0
        var expandedBytes: UInt64 = 0
        var maximumDepth: UInt64 = 0
        var canonicalPaths: Set<String> = []
        for snapshot in ordered {
            let canonical = snapshot.entry.displayPath
                .decomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard canonicalPaths.insert(canonical).inserted else {
                throw ArchiveError.unsafePath
            }
            let (nextCompressed, compressedOverflow) = compressedBytes
                .addingReportingOverflow(snapshot.compressedSize)
            let (nextExpanded, expandedOverflow) = expandedBytes
                .addingReportingOverflow(snapshot.uncompressedSize)
            guard !compressedOverflow, !expandedOverflow else { throw ArchiveError.resourceLimit }
            compressedBytes = nextCompressed
            expandedBytes = nextExpanded
            maximumDepth = max(
                maximumDepth,
                UInt64(snapshot.entry.displayPath.split(separator: "/").count)
            )
        }
        guard budget.evaluate(ResourceEstimate(
            compressedBytes: compressedBytes,
            expandedBytes: expandedBytes,
            entries: UInt64(ordered.count),
            depth: maximumDepth
        )) == .allow else {
            throw ArchiveError.resourceLimit
        }

        progress(SevenZipExtractionProgress(
            completedEntries: 0,
            totalEntries: ordered.count,
            completedBytes: 0,
            totalBytes: expandedBytes
        ))

        let materializer = SecureFileMaterializer(rootURL: rootURL)
        var completedEntries = 0
        var writtenBytes: UInt64 = 0
        let expectedByOrdinal = Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
            ($0.offset, $0.element)
        })

        try withReader(at: archiveURL) { reader in
            var entryPointer: OpaquePointer?
            var ordinal = 0
            while true {
                try Task.checkCancellation()
                let result = archive_read_next_header(reader, &entryPointer)
                if result == ARCHIVE_EOF { break }
                guard result == ARCHIVE_OK || result == ARCHIVE_WARN else {
                    throw TARProviderError.libarchiveFailed(code: result, message: lastError(reader))
                }
                guard let ep = entryPointer else { break }
                guard let pathCString = archive_entry_pathname(ep) else { continue }
                var path = String(cString: pathCString)
                if path == "." || path == "./" {
                    archive_read_data_skip(reader)
                    continue
                }
                if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
                if path.hasSuffix("/") { path = String(path.dropLast()) }
                if path.isEmpty {
                    archive_read_data_skip(reader)
                    continue
                }
                guard let expected = expectedByOrdinal[ordinal] else {
                    throw ArchiveError.corruptedArchive
                }
                try verifyHeader(
                    entry: ep,
                    expectedPath: expected.entry.displayPath,
                    expectedKind: memberKind(of: expected),
                    expectedSize: expected.uncompressedSize
                )
                ordinal += 1

                if expected.isDirectory {
                    _ = try materializer.createDirectory(relativePath: expected.entry.displayPath)
                    archive_read_data_skip(reader)
                } else {
                    var fileBytes: UInt64 = 0
                    let bufferSize = 1024 * 1024
                    var buffer = [UInt8](repeating: 0, count: bufferSize)
                    nonisolated(unsafe) let unsafeReader = reader
                    let entryCap = expected.uncompressedSize > 0
                        ? expected.uncompressedSize
                        : budget.maxExpandedBytes
                    _ = try materializer.write(relativePath: expected.entry.displayPath) { writer in
                        while true {
                            try Task.checkCancellation()
                            let bytesRead = archive_read_data(unsafeReader, &buffer, bufferSize)
                            if bytesRead == 0 { break }
                            if bytesRead < 0 {
                                throw TARProviderError.libarchiveFailed(
                                    code: Int32(bytesRead),
                                    message: lastError(unsafeReader)
                                )
                            }
                            fileBytes += UInt64(bytesRead)
                            guard fileBytes <= entryCap, fileBytes <= budget.maxExpandedBytes else {
                                throw ArchiveError.resourceLimit
                            }
                            guard writtenBytes + fileBytes <= budget.maxExpandedBytes else {
                                throw ArchiveError.resourceLimit
                            }
                            try writer.write(Data(bytes: buffer, count: bytesRead))
                        }
                    }
                    writtenBytes += fileBytes
                    if expected.uncompressedSize > 0, fileBytes != expected.uncompressedSize {
                        throw ArchiveError.corruptedArchive
                    }
                }
                completedEntries += 1
                progress(SevenZipExtractionProgress(
                    completedEntries: completedEntries,
                    totalEntries: ordered.count,
                    completedBytes: writtenBytes,
                    totalBytes: expandedBytes
                ))
            }
            guard completedEntries == ordered.count else {
                throw ArchiveError.corruptedArchive
            }
        }

        return TARExtractionResult(
            completedEntries: completedEntries,
            expandedBytes: writtenBytes
        )
    }

    // MARK: - Create TAR archive

    /// Creates a TAR archive at outputURL from the given input file URLs.
    /// Compression is inferred from the output file name.
    public func createArchive(
        at outputURL: URL,
        inputs: [URL],
        compression: TARCompression? = nil
    ) throws {
        try createArchive(
            at: outputURL,
            inputs: inputs.map { ArchiveCreationInput(sourceURL: $0) },
            compression: compression
        )
    }

    public func createArchive(
        at outputURL: URL,
        inputs: [ArchiveCreationInput],
        compression: TARCompression? = nil
    ) throws {
        try Task.checkCancellation()
        let effectiveCompression = compression ?? TARCompression.fromFileName(outputURL.lastPathComponent)

        guard let writer = archive_write_new() else {
            throw TARProviderError.createFailed(message: "archive_write_new failed")
        }
        defer { archive_write_free(writer) }

        // Set format to pax restricted (supports long paths, large files)
        guard archive_write_set_format_pax_restricted(writer) == ARCHIVE_OK else {
            throw TARProviderError.createFailed(message: "set_format_pax_restricted failed")
        }

        // Add compression filter
        let filterResult: Int32
        switch effectiveCompression {
        case .none:
            filterResult = ARCHIVE_OK // no filter needed
        case .gzip:
            filterResult = archive_write_add_filter_gzip(writer)
        case .bzip2:
            filterResult = archive_write_add_filter_bzip2(writer)
        case .xz:
            filterResult = archive_write_add_filter_xz(writer)
        case .zstd:
            filterResult = archive_write_add_filter_zstd(writer)
        }
        guard filterResult == ARCHIVE_OK else {
            throw TARProviderError.createFailed(
                message: "add_filter_\(effectiveCompression.filterName) failed: \(lastError(writer))"
            )
        }

        // Write to a staging file; publish atomically only on full success.
        let stageURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).awb_stage_\(UUID().uuidString)")
        var stagePublished = false
        defer { if !stagePublished { try? FileManager.default.removeItem(at: stageURL) } }

        guard archive_write_open_filename(writer, stageURL.path) == ARCHIVE_OK else {
            throw TARProviderError.createFailed(
                message: "open_filename failed: \(lastError(writer))"
            )
        }

        for input in inputs {
            try Task.checkCancellation()
            try addFileToArchive(
                writer: writer,
                fileURL: input.sourceURL,
                archiveRootName: input.archiveRootName
            )
        }

        guard archive_write_close(writer) == ARCHIVE_OK else {
            throw TARProviderError.createFailed(
                message: "write_close failed: \(lastError(writer))"
            )
        }

        try syncFile(at: stageURL)
        try publishAtomically(stageURL: stageURL, outputURL: outputURL)
        stagePublished = true
    }

    // MARK: - Private: listing

    private func listEntries(url: URL) throws -> [ArchiveEntrySnapshot] {
        var snapshots: [ArchiveEntrySnapshot] = []
        try withReader(at: url, mapFailures: true) { reader in
            var entryPointer: OpaquePointer?
            while true {
                try Task.checkCancellation()
                let result = archive_read_next_header(reader, &entryPointer)
                if result == ARCHIVE_EOF { break }
                guard result == ARCHIVE_OK || result == ARCHIVE_WARN else {
                    if snapshots.isEmpty {
                        throw Self.mapOpenFailure(url: url, message: lastError(reader))
                    }
                    throw TARProviderError.libarchiveFailed(
                        code: result,
                        message: lastError(reader)
                    )
                }
                guard let ep = entryPointer else { break }
                guard snapshots.count < listingEntryLimit else {
                    throw ArchiveError.resourceLimit
                }
                guard let pathCString = archive_entry_pathname(ep) else { continue }
                var path = String(cString: pathCString)
                if path == "." || path == "./" {
                    archive_read_data_skip(reader)
                    continue
                }
                if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
                if path.isEmpty {
                    archive_read_data_skip(reader)
                    continue
                }

                let kind = Self.memberKind(fromHeader: ep)
                let displayPath: String
                if kind == .directory && path.hasSuffix("/") {
                    displayPath = String(path.dropLast())
                } else {
                    displayPath = path
                }
                do {
                    try ArchivePathPolicy().validate(displayPath)
                } catch {
                    throw ArchiveError.unsafePath
                }

                let rawSize = archive_entry_size(ep)
                let size: UInt64 = (kind == .symlink || kind == .hardlink || kind == .special)
                    ? 0
                    : (rawSize > 0 ? UInt64(rawSize) : 0)
                let mtime = archive_entry_mtime(ep)
                let modifiedAt = mtime > 0 ? Date(timeIntervalSince1970: TimeInterval(mtime)) : nil
                let entry = ArchiveEntry(
                    id: ArchiveEntryID(),
                    rawPath: ArchivePathBytes(Array(path.utf8)),
                    displayPath: displayPath
                )
                snapshots.append(ArchiveEntrySnapshot(
                    entry: entry,
                    compressedSize: size,
                    uncompressedSize: size,
                    modifiedAt: modifiedAt,
                    isDirectory: kind == .directory,
                    isSymbolicLink: kind == .symlink,
                    isEncrypted: false,
                    usesUTF8FileName: true,
                    isHardLink: kind == .hardlink,
                    isExtractable: kind == .regular
                ))
                if kind != .regular {
                    archive_read_data_skip(reader)
                }
            }
        }
        return snapshots
    }

    // MARK: - Private: single entry extraction

    private func extractEntryData(
        url: URL,
        ordinal: Int,
        expectedPath: String,
        expectedKind: MemberKind,
        expectedSize: UInt64,
        maximumBytes: UInt64
    ) throws -> Data {
        var data = Data()
        try withReader(at: url) { reader in
            try seekToMember(
                reader: reader,
                ordinal: ordinal,
                expectedPath: expectedPath,
                expectedKind: expectedKind,
                expectedSize: expectedSize
            )
            let bufferSize = 1024 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while true {
                try Task.checkCancellation()
                let bytesRead = archive_read_data(reader, &buffer, bufferSize)
                if bytesRead == 0 { break }
                if bytesRead < 0 {
                    throw TARProviderError.libarchiveFailed(
                        code: Int32(bytesRead),
                        message: lastError(reader)
                    )
                }
                guard UInt64(data.count + bytesRead) <= maximumBytes else {
                    throw ArchiveError.resourceLimit
                }
                data.append(contentsOf: buffer[0..<bytesRead])
            }
        }
        return data
    }

    private func resolvedSnapshot(id: ArchiveEntryID) throws -> ArchiveEntrySnapshot {
        try ensureArchiveUnchanged()
        guard let snapshot = entriesByID[id] else { throw ArchiveError.helperFailed }
        return snapshot
    }

    private func ensureArchiveUnchanged() throws {
        guard let archiveURL, let openedIdentity else { throw ArchiveError.helperFailed }
        let current = try ArchiveFileIdentity.capture(url: archiveURL)
        guard current == openedIdentity else { throw ArchiveError.corruptedArchive }
    }

    private func rejectNonExtractable(
        _ snapshot: ArchiveEntrySnapshot,
        allowDirectory: Bool = false
    ) throws {
        if snapshot.isDirectory {
            if allowDirectory { return }
            throw ArchiveError.unsafePath
        }
        if snapshot.isSymbolicLink {
            throw TARProviderError.symlinkRejected(path: snapshot.entry.displayPath)
        }
        if snapshot.isHardLink {
            throw TARProviderError.hardlinkRejected(path: snapshot.entry.displayPath)
        }
        if !snapshot.isExtractable {
            throw TARProviderError.specialFileRejected(path: snapshot.entry.displayPath)
        }
    }

    private func memberKind(of snapshot: ArchiveEntrySnapshot) -> MemberKind {
        if snapshot.isDirectory { return .directory }
        if snapshot.isSymbolicLink { return .symlink }
        if snapshot.isHardLink { return .hardlink }
        if snapshot.isExtractable { return .regular }
        return .special
    }

    private static func memberKind(fromHeader entry: OpaquePointer) -> MemberKind {
        let fileType = archive_entry_filetype(entry)
        let maskedType = fileType & AE_IFMT
        if maskedType == AE_IFDIR { return .directory }
        if maskedType == AE_IFLNK { return .symlink }
        if archive_entry_hardlink(entry) != nil { return .hardlink }
        if maskedType == AE_IFREG { return .regular }
        return .special
    }

    private func withReader(
        at url: URL,
        mapFailures: Bool = false,
        body: (OpaquePointer) throws -> Void
    ) throws {
        guard let reader = archive_read_new() else {
            throw TARProviderError.openFailed(message: "archive_read_new failed")
        }
        defer { archive_read_free(reader) }
        // Do not enable format_empty: empty gzip would otherwise look like an empty TAR.
        archive_read_support_format_tar(reader)
        archive_read_support_filter_all(reader)
        let openResult = archive_read_open_filename(reader, url.path, 10240)
        guard openResult == ARCHIVE_OK else {
            let message = lastError(reader)
            throw mapFailures ? Self.mapOpenFailure(url: url, message: message)
                : TARProviderError.openFailed(message: message)
        }
        try body(reader)
    }

    private func seekToMember(
        reader: OpaquePointer,
        ordinal: Int,
        expectedPath: String,
        expectedKind: MemberKind,
        expectedSize: UInt64
    ) throws {
        var entryPointer: OpaquePointer?
        var index = 0
        while true {
            try Task.checkCancellation()
            let result = archive_read_next_header(reader, &entryPointer)
            if result == ARCHIVE_EOF { break }
            guard result == ARCHIVE_OK || result == ARCHIVE_WARN else {
                throw TARProviderError.libarchiveFailed(code: result, message: lastError(reader))
            }
            guard let ep = entryPointer else { break }
            guard let pathCString = archive_entry_pathname(ep) else { continue }
            var path = String(cString: pathCString)
            if path == "." || path == "./" {
                archive_read_data_skip(reader)
                continue
            }
            if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
            if path.hasSuffix("/") { path = String(path.dropLast()) }
            if path.isEmpty {
                archive_read_data_skip(reader)
                continue
            }
            if index == ordinal {
                try verifyHeader(
                    entry: ep,
                    expectedPath: expectedPath,
                    expectedKind: expectedKind,
                    expectedSize: expectedSize
                )
                return
            }
            index += 1
            archive_read_data_skip(reader)
        }
        throw ArchiveError.helperFailed
    }

    private func verifyHeader(
        entry: OpaquePointer,
        expectedPath: String,
        expectedKind: MemberKind,
        expectedSize: UInt64
    ) throws {
        guard let pathCString = archive_entry_pathname(entry) else {
            throw ArchiveError.corruptedArchive
        }
        var path = String(cString: pathCString)
        if path.hasPrefix("./") { path = String(path.dropFirst(2)) }
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        guard path == expectedPath else { throw ArchiveError.corruptedArchive }
        let kind = Self.memberKind(fromHeader: entry)
        guard kind == expectedKind else { throw ArchiveError.corruptedArchive }
        if expectedKind == .regular {
            let rawSize = archive_entry_size(entry)
            let size: UInt64 = rawSize > 0 ? UInt64(rawSize) : 0
            if expectedSize > 0, size != expectedSize {
                throw ArchiveError.corruptedArchive
            }
        }
    }

    // MARK: - Private: creation helpers

    private func addFileToArchive(
        writer: OpaquePointer,
        fileURL: URL,
        archiveRootName: String
    ) throws {
        let fm = FileManager.default
        let resourceValues = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard resourceValues.isSymbolicLink != true else { return }
        let attributes = try fm.attributesOfItem(atPath: fileURL.path)
        let fileType = attributes[.type] as? FileAttributeType
        let isDirectory = fileType == .typeDirectory

        if isDirectory {
            let baseName = archiveRootName
            try addDirectoryEntry(writer: writer, path: baseName, attributes: attributes)
            guard let enumerator = fm.enumerator(
                at: fileURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: []
            ) else { return }
            // enumerator yields symlink-resolved paths; resolve the base too so the prefix matches.
            let resolvedPrefix = fileURL.resolvingSymlinksInPath().path + "/"
            for case let itemURL as URL in enumerator {
                try Task.checkCancellation()
                guard itemURL.path.hasPrefix(resolvedPrefix) else { continue }
                let relativePath = baseName + "/" + itemURL.path.dropFirst(resolvedPrefix.count)
                let itemResourceValues = try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                guard itemResourceValues.isSymbolicLink != true else { continue }
                let itemAttributes = try fm.attributesOfItem(atPath: itemURL.path)
                let itemType = itemAttributes[.type] as? FileAttributeType
                if itemType == .typeDirectory {
                    try addDirectoryEntry(writer: writer, path: relativePath, attributes: itemAttributes)
                } else if itemType == .typeRegular {
                    try addRegularFileEntry(writer: writer, fileURL: itemURL, archivePath: relativePath, attributes: itemAttributes)
                }
                // Skip special files (FIFO/socket/device): opening them can block.
            }
        } else if fileType == .typeRegular {
            try addRegularFileEntry(
                writer: writer,
                fileURL: fileURL,
                archivePath: archiveRootName,
                attributes: attributes
            )
        }
        // Skip special files (FIFO/socket/device): opening them can block.
    }

    private func addDirectoryEntry(writer: OpaquePointer, path: String, attributes: [FileAttributeKey: Any]) throws {
        guard let entry = archive_entry_new() else {
            throw TARProviderError.createFailed(message: "archive_entry_new failed")
        }
        defer { archive_entry_free(entry) }
        archive_entry_set_pathname(entry, path)
        archive_entry_set_filetype(entry, UInt32(AE_IFDIR))
        archive_entry_set_size(entry, 0)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o755
        archive_entry_set_perm(entry, permissions)
        if let mtime = attributes[.modificationDate] as? Date {
            archive_entry_set_mtime(entry, time_t(mtime.timeIntervalSince1970), 0)
        }
        let headerResult = archive_write_header(writer, entry)
        guard headerResult == ARCHIVE_OK else {
            throw TARProviderError.createFailed(message: "write_header failed for \(path): \(lastError(writer))")
        }
    }

    private func addRegularFileEntry(writer: OpaquePointer, fileURL: URL, archivePath: String, attributes: [FileAttributeKey: Any]) throws {
        guard let entry = archive_entry_new() else {
            throw TARProviderError.createFailed(message: "archive_entry_new failed")
        }
        defer { archive_entry_free(entry) }

        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        archive_entry_set_pathname(entry, archivePath)
        archive_entry_set_filetype(entry, UInt32(AE_IFREG))
        archive_entry_set_size(entry, fileSize)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
        archive_entry_set_perm(entry, permissions)
        if let mtime = attributes[.modificationDate] as? Date {
            archive_entry_set_mtime(entry, time_t(mtime.timeIntervalSince1970), 0)
        }

        let headerResult = archive_write_header(writer, entry)
        guard headerResult == ARCHIVE_OK else {
            throw TARProviderError.createFailed(
                message: "write_header failed for \(archivePath): \(lastError(writer))"
            )
        }

        let fd = fileURL.withUnsafeFileSystemRepresentation { p -> Int32 in
            guard let p else { return -1 }
            return Darwin.open(p, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fd >= 0 else {
            throw TARProviderError.createFailed(message: "cannot open \(fileURL.path)")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var totalWritten: Int64 = 0
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            } catch {
                throw TARProviderError.createFailed(
                    message: "read failed for \(archivePath): \(error.localizedDescription)"
                )
            }
            if chunk.isEmpty { break }
            let written = chunk.withUnsafeBytes { ptr -> Int in
                archive_write_data(writer, ptr.baseAddress, ptr.count)
            }
            guard written == chunk.count else {
                throw TARProviderError.createFailed(
                    message: "write_data failed for \(archivePath): \(lastError(writer))"
                )
            }
            totalWritten += Int64(written)
        }
        guard totalWritten == fileSize else {
            throw TARProviderError.createFailed(
                message: "size mismatch for \(archivePath): header \(fileSize), wrote \(totalWritten)"
            )
        }
    }

    private func lastError(_ archive: OpaquePointer) -> String {
        if let msg = archive_error_string(archive) {
            return String(cString: msg)
        }
        return "unknown error"
    }

    // MARK: - Private: format detection

    private static func formatForURL(_ url: URL) -> ArchiveFormat {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .gzip }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2") { return .bzip2 }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .xz }
        if name.hasSuffix(".tar.zst") || name.hasSuffix(".tar.zstd") { return .zstandard }
        return .tar
    }

    /// Pure gzip/bzip2/xz/zstd (non-TAR) must not silently fall back to another engine.
    /// Damaged `.tar` must stay `openFailed`, never `notTAR`.
    private static func mapOpenFailure(url: URL, message: String) -> TARProviderError {
        let name = url.lastPathComponent.lowercased()
        let looksLikeTARName =
            name.hasSuffix(".tar")
            || name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz")
            || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz2")
            || name.hasSuffix(".tar.xz") || name.hasSuffix(".txz")
            || name.hasSuffix(".tar.zst") || name.hasSuffix(".tar.zstd")
        let looksLikeCompressedNonTAR =
            (name.hasSuffix(".gz") && !name.hasSuffix(".tar.gz") && !name.hasSuffix(".tgz"))
            || (name.hasSuffix(".bz2") && !name.hasSuffix(".tar.bz2") && !name.hasSuffix(".tbz2"))
            || (name.hasSuffix(".xz") && !name.hasSuffix(".tar.xz") && !name.hasSuffix(".txz"))
            || (name.hasSuffix(".zst") && !name.hasSuffix(".tar.zst"))
            || name.hasSuffix(".zstd")
        if looksLikeTARName {
            return .openFailed(message: message)
        }
        if looksLikeCompressedNonTAR {
            return .notTAR(message: message)
        }
        let lowerMessage = message.lowercased()
        if lowerMessage.contains("unrecognized")
            || lowerMessage.contains("not a tar")
            || lowerMessage.contains("invalid tar") {
            return .notTAR(message: message)
        }
        return .openFailed(message: message)
    }

    // MARK: - Private: durability

    private func syncFile(at url: URL) throws {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fd >= 0 else {
            throw TARProviderError.createFailed(message: "open for fsync failed: \(errno)")
        }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else {
            throw TARProviderError.createFailed(message: "fsync failed: \(errno)")
        }
    }

    private func syncDirectory(at url: URL) throws {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY)
        }
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        fsync(fd)
    }

    private func publishAtomically(stageURL: URL, outputURL: URL) throws {
        let linkResult = stageURL.withUnsafeFileSystemRepresentation { stagePath in
            outputURL.withUnsafeFileSystemRepresentation { outputPath in
                guard let stagePath, let outputPath else { return Int32(-1) }
                return Darwin.link(stagePath, outputPath)
            }
        }
        guard linkResult == 0 else {
            throw TARProviderError.createFailed(message: "link failed: \(errno)")
        }
        try? FileManager.default.removeItem(at: stageURL)
        try syncDirectory(at: outputURL.deletingLastPathComponent())
    }
}
