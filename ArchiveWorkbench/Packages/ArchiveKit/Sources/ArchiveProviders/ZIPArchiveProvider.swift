import ArchiveDomain
import ArchiveSecurity
import CMinizipBridge
import CryptoKit
import Foundation

public struct ZIPExtractionResult: Equatable, Sendable {
    public let completedEntries: Int
    public let expandedBytes: UInt64

    public init(completedEntries: Int, expandedBytes: UInt64) {
        self.completedEntries = completedEntries
        self.expandedBytes = expandedBytes
    }
}

public struct ZIPExtractionProgress: Equatable, Sendable {
    public let completedEntries: Int
    public let totalEntries: Int
    public let completedBytes: UInt64
    public let totalBytes: UInt64

    public init(completedEntries: Int, totalEntries: Int, completedBytes: UInt64, totalBytes: UInt64) {
        self.completedEntries = completedEntries
        self.totalEntries = totalEntries
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}

public actor ZIPArchiveProvider: ArchiveProvider {
    private let listingEntryLimit: Int
    private let splitResolver = SplitVolumeResolver()
    private let encodingDetector = EncodingDetector()
    private var reader: ZIPBridgeReader?
    private var entriesByID: [ArchiveEntryID: ArchiveEntrySnapshot] = [:]
    private var ordinalsByID: [ArchiveEntryID: UInt64] = [:]
    private var looksLikeMultipartVolume = false
    private var hasPassword = false
    /// The URL passed to `open(url:)` or `openWithPassword(url:password:)`.
    private var openedURL: URL?

    /// Per-archive encoding override. When set to a non-automatic value, all
    /// entry names are re-decoded with this encoding regardless of detection.
    private var encodingOverride: LegacyEncodingPreference = .automatic

    /// Raw bridge entries retained so we can re-decode display names when the
    /// user changes the encoding override without re-reading the archive.
    private var rawBridgeEntries: [ZIPBridgeEntry] = []

    public init() {
        listingEntryLimit = 1_000_000
    }

    init(listingEntryLimit: Int) {
        self.listingEntryLimit = listingEntryLimit
    }

    /// True when the opened archive is part of a split volume set.
    public var isMultipartVolume: Bool { looksLikeMultipartVolume }

    /// The current per-archive encoding override.
    public var currentEncodingOverride: LegacyEncodingPreference { encodingOverride }

    /// Sets a per-archive encoding override and re-decodes all entry display
    /// names. Raw bytes are never modified — only the display representation
    /// changes. Returns an updated snapshot with re-decoded names.
    public func setEncodingOverride(_ preference: LegacyEncodingPreference) -> ArchiveDocumentSnapshot? {
        let previous = encodingOverride
        encodingOverride = preference
        guard reader != nil, !rawBridgeEntries.isEmpty else { return nil }
        guard let snapshot = rebuildSnapshotFromRawEntries() else {
            encodingOverride = previous
            return nil
        }
        return snapshot
    }

    public func open(url: URL) throws -> ArchiveDocumentSnapshot {
        reader = nil
        entriesByID = [:]
        ordinalsByID = [:]
        looksLikeMultipartVolume = false
        hasPassword = false
        rawBridgeEntries = []
        openedURL = url

        // Detect and validate split volume sets before opening.
        var effectiveURL = url
        if let resolution = splitResolver.resolve(url: url) {
            looksLikeMultipartVolume = true
            if resolution.hasMissingVolumes {
                throw ArchiveError.missingVolume
            }
            effectiveURL = resolution.primaryURL
        }

        let openedReader = try ZIPBridgeReader(url: effectiveURL)
        let bridgeEntries = try openedReader.allEntries(maximumCount: listingEntryLimit)
        rawBridgeEntries = bridgeEntries

        let snapshots = try buildSnapshots(from: bridgeEntries)
        reader = openedReader
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        ordinalsByID = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map {
            ($0.element.entry.id, UInt64($0.offset))
        })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .zip, entries: snapshots)
    }

    /// Opens an encrypted ZIP archive with the given password.
    /// The password is held in locked memory and zeroized on release.
    public func openWithPassword(url: URL, password: SecurePassword) throws -> ArchiveDocumentSnapshot {
        reader = nil
        entriesByID = [:]
        ordinalsByID = [:]
        rawBridgeEntries = []
        looksLikeMultipartVolume = false
        hasPassword = true
        openedURL = url

        var effectiveURL = url
        if let resolution = splitResolver.resolve(url: url) {
            looksLikeMultipartVolume = true
            if resolution.hasMissingVolumes {
                throw ArchiveError.missingVolume
            }
            effectiveURL = resolution.primaryURL
        }

        let openedReader = try ZIPBridgeReader(url: effectiveURL, password: password)
        let bridgeEntries = try openedReader.allEntries(maximumCount: listingEntryLimit)
        rawBridgeEntries = bridgeEntries

        let snapshots = try buildSnapshots(from: bridgeEntries)
        reader = openedReader
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        ordinalsByID = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map {
            ($0.element.entry.id, UInt64($0.offset))
        })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .zip, entries: snapshots)
    }

    public func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data {
        guard
            let snapshot = entriesByID[id],
            let ordinal = ordinalsByID[id],
            let reader
        else {
            throw ArchiveError.helperFailed
        }
        guard !snapshot.isDirectory, !snapshot.isSymbolicLink else {
            throw ArchiveError.unsafePath
        }
        if snapshot.isEncrypted && !hasPassword {
            throw ArchiveError.passwordRequired
        }
        guard snapshot.uncompressedSize <= maximumBytes,
              snapshot.uncompressedSize <= UInt64(Int.max) else {
            throw ArchiveError.resourceLimit
        }
        return try reader.readEntry(
            ordinal: ordinal,
            expectedSize: snapshot.uncompressedSize,
            maximumBytes: maximumBytes
        )
    }

    public func materializeEntry(
        id: ArchiveEntryID,
        under rootURL: URL,
        budget: ResourceBudget = .previewDefault
    ) throws -> URL {
        try Task.checkCancellation()
        guard let snapshot = entriesByID[id] else {
            throw ArchiveError.helperFailed
        }
        let decision = budget.evaluate(ResourceEstimate(
            compressedBytes: snapshot.compressedSize,
            expandedBytes: snapshot.uncompressedSize,
            entries: 1,
            depth: 1
        ))
        guard decision == .allow else { throw ArchiveError.resourceLimit }
        guard let ordinal = ordinalsByID[id], let reader else {
            throw ArchiveError.helperFailed
        }
        let output = try SecureFileMaterializer(rootURL: rootURL).write(
            relativePath: snapshot.entry.displayPath
        ) { writer in
            try reader.streamEntry(
                ordinal: ordinal,
                expectedSize: snapshot.uncompressedSize,
                maximumBytes: budget.maxExpandedBytes,
                writer: writer,
                progress: { _ in }
            )
        }
        try Task.checkCancellation()
        return output
    }

    public func extractAll(
        under rootURL: URL,
        budget: ResourceBudget = .extractionDefault,
        progress: @Sendable (ZIPExtractionProgress) -> Void = { _ in }
    ) throws -> ZIPExtractionResult {
        try Task.checkCancellation()
        let snapshots = entriesByID.values.sorted {
            guard let left = ordinalsByID[$0.entry.id], let right = ordinalsByID[$1.entry.id] else {
                return $0.entry.displayPath < $1.entry.displayPath
            }
            return left < right
        }
        guard let reader else { throw ArchiveError.helperFailed }
        guard !snapshots.contains(where: { $0.isSymbolicLink }) else {
            throw ArchiveError.unsafePath
        }
        if snapshots.contains(where: { $0.isEncrypted }) && !hasPassword {
            throw ArchiveError.passwordRequired
        }
        try validateExtractionPaths(snapshots)

        var compressedBytes: UInt64 = 0
        var expandedBytes: UInt64 = 0
        var maximumDepth: UInt64 = 0
        for snapshot in snapshots {
            let (nextCompressed, compressedOverflow) = compressedBytes.addingReportingOverflow(snapshot.compressedSize)
            let (nextExpanded, expandedOverflow) = expandedBytes.addingReportingOverflow(snapshot.uncompressedSize)
            guard !compressedOverflow, !expandedOverflow else { throw ArchiveError.resourceLimit }
            compressedBytes = nextCompressed
            expandedBytes = nextExpanded
            let path = snapshot.isDirectory && snapshot.entry.displayPath.hasSuffix("/")
                ? String(snapshot.entry.displayPath.dropLast())
                : snapshot.entry.displayPath
            maximumDepth = max(maximumDepth, UInt64(path.split(separator: "/").count))
        }
        guard budget.evaluate(ResourceEstimate(
            compressedBytes: compressedBytes,
            expandedBytes: expandedBytes,
            entries: UInt64(snapshots.count),
            depth: maximumDepth
        )) == .allow else {
            throw ArchiveError.resourceLimit
        }

        let materializer = try SecureMaterializationSession(rootURL: rootURL)
        var completedEntries = 0
        var writtenBytes: UInt64 = 0
        progress(ZIPExtractionProgress(
            completedEntries: 0,
            totalEntries: snapshots.count,
            completedBytes: 0,
            totalBytes: expandedBytes
        ))
        for snapshot in snapshots {
            try Task.checkCancellation()
            let path = snapshot.isDirectory && snapshot.entry.displayPath.hasSuffix("/")
                ? String(snapshot.entry.displayPath.dropLast())
                : snapshot.entry.displayPath
            if snapshot.isDirectory {
                _ = try materializer.createDirectory(relativePath: path)
            } else {
                guard let ordinal = ordinalsByID[snapshot.entry.id] else {
                    throw ArchiveError.helperFailed
                }
                _ = try materializer.write(relativePath: path) { writer in
                    try reader.streamEntry(
                        ordinal: ordinal,
                        expectedSize: snapshot.uncompressedSize,
                        maximumBytes: snapshot.uncompressedSize,
                        writer: writer
                    ) { chunkBytes in
                        progress(ZIPExtractionProgress(
                            completedEntries: completedEntries,
                            totalEntries: snapshots.count,
                            completedBytes: writtenBytes + chunkBytes,
                            totalBytes: expandedBytes
                        ))
                    }
                }
                writtenBytes += snapshot.uncompressedSize
            }
            completedEntries += 1
            progress(ZIPExtractionProgress(
                completedEntries: completedEntries,
                totalEntries: snapshots.count,
                completedBytes: writtenBytes,
                totalBytes: expandedBytes
            ))
        }
        return ZIPExtractionResult(completedEntries: completedEntries, expandedBytes: writtenBytes)
    }

    // MARK: - Private

    /// Builds entry snapshots from raw bridge entries using encoding detection.
    /// Raw bytes are always preserved in `ArchiveEntry.rawPath`; the display path
    /// is decoded according to detection heuristics or user override.
    private func buildSnapshots(from bridgeEntries: [ZIPBridgeEntry]) throws -> [ArchiveEntrySnapshot] {
        var snapshots: [ArchiveEntrySnapshot] = []
        snapshots.reserveCapacity(bridgeEntries.count)

        for bridgeEntry in bridgeEntries {
            let detection = encodingDetector.detect(
                rawBytes: bridgeEntry.nameBytes,
                usesUTF8Flag: bridgeEntry.usesUTF8FileName,
                override: encodingOverride
            )
            let displayPath = detection.decodedName

            let validationPath = bridgeEntry.isDirectory && displayPath.hasSuffix("/")
                ? String(displayPath.dropLast())
                : displayPath
            do {
                try ArchivePathPolicy().validate(validationPath)
            } catch {
                throw ArchiveError.unsafePath
            }

            let entry = ArchiveEntry(
                id: ArchiveEntryID(),
                rawPath: ArchivePathBytes(bridgeEntry.nameBytes),
                displayPath: displayPath
            )
            snapshots.append(ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: bridgeEntry.compressedSize,
                uncompressedSize: bridgeEntry.uncompressedSize,
                modifiedAt: bridgeEntry.modifiedAt,
                isDirectory: bridgeEntry.isDirectory,
                isSymbolicLink: bridgeEntry.isSymbolicLink,
                isEncrypted: bridgeEntry.isEncrypted,
                usesUTF8FileName: bridgeEntry.usesUTF8FileName
            ))
        }
        return snapshots
    }

    /// Re-decodes all entry display names using the current encoding override.
    /// Called when the user changes the per-archive encoding preference.
    /// Raw bytes are never modified.
    private func rebuildSnapshotFromRawEntries() -> ArchiveDocumentSnapshot? {
        guard reader != nil else { return nil }
        guard let snapshots = try? buildSnapshots(from: rawBridgeEntries) else { return nil }
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        ordinalsByID = Dictionary(uniqueKeysWithValues: snapshots.enumerated().map {
            ($0.element.entry.id, UInt64($0.offset))
        })
        return ArchiveDocumentSnapshot(
            sourceURL: openedURL ?? URL(fileURLWithPath: "/dev/null"),
            format: .zip,
            entries: snapshots
        )
    }

    private func validateExtractionPaths(_ snapshots: [ArchiveEntrySnapshot]) throws {
        var canonicalPaths: Set<String> = []
        for snapshot in snapshots {
            let path = snapshot.isDirectory && snapshot.entry.displayPath.hasSuffix("/")
                ? String(snapshot.entry.displayPath.dropLast())
                : snapshot.entry.displayPath
            let canonical = path.decomposedStringWithCanonicalMapping.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard canonicalPaths.insert(canonical).inserted else {
                throw ArchiveError.unsafePath
            }
        }
    }
}

struct ZIPBridgeEntry {
    let nameBytes: [UInt8]
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let modifiedAt: Date?
    let modifiedUnixTime: Int64
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let isEncrypted: Bool
    let usesUTF8FileName: Bool
}

final class ZIPBridgeReader {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var opened: OpaquePointer?
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
            return awb_mz_reader_open(path, &opened)
        }
        guard status == AWB_MZ_OK, let opened else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        handle = opened
    }

    init(url: URL, password: SecurePassword) throws {
        var opened: OpaquePointer?
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
            return password.withCString { pwd in
                awb_mz_reader_open_with_password(path, pwd, &opened)
            }
        }
        guard status == AWB_MZ_OK, let opened else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        handle = opened
    }

    deinit {
        awb_mz_reader_close(&handle)
    }

    func allEntries(maximumCount: Int) throws -> [ZIPBridgeEntry] {
        guard let handle else { throw ArchiveError.helperFailed }
        guard maximumCount > 0 else { throw ArchiveError.resourceLimit }
        var result: [ZIPBridgeEntry] = []
        var info = awb_mz_entry_info()
        var status = awb_mz_reader_first(handle, &info)
        while status == AWB_MZ_OK {
            guard result.count < maximumCount else {
                throw ArchiveError.resourceLimit
            }
            result.append(try copy(info))
            status = awb_mz_reader_next(handle, &info)
        }
        guard status == AWB_MZ_END else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        return result
    }

    func readEntry(ordinal: UInt64, expectedSize: UInt64, maximumBytes: UInt64) throws -> Data {
        guard let handle else { throw ArchiveError.helperFailed }
        var info = awb_mz_entry_info()
        var status = awb_mz_reader_goto(handle, ordinal, &info)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        status = awb_mz_reader_open_current(handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }

        var data = Data()
        let capacity = min(Int(expectedSize), 256 * 1024 * 1024) // cap at 256MB
        data.reserveCapacity(capacity)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var readError: Error?
        while true {
            do {
                try Task.checkCancellation()
            } catch {
                readError = CancellationError()
                break
            }
            let count = buffer.withUnsafeMutableBufferPointer { bytes in
                awb_mz_reader_read_current(handle, bytes.baseAddress, Int32(bytes.count))
            }
            if count == 0 { break }
            if count < 0 {
                readError = ZIPProviderErrorMapper.archiveError(for: count)
                break
            }
            let nextSize = UInt64(data.count) + UInt64(count)
            if nextSize > maximumBytes {
                readError = ArchiveError.resourceLimit
                break
            }
            data.append(buffer, count: Int(count))
        }

        let closeStatus = awb_mz_reader_close_current(handle)
        if let readError { throw readError }
        guard closeStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: closeStatus)
        }
        guard UInt64(data.count) == expectedSize else {
            throw ArchiveError.corruptedArchive
        }
        return data
    }

    /// Streams an entry's decompressed bytes in chunks without buffering the
    /// whole payload in memory. Used by the editing backend to copy unchanged
    /// entries verbatim into a staging archive.
    func streamEntryChunks(
        ordinal: UInt64,
        expectedSize: UInt64,
        maximumBytes: UInt64,
        emit: (Data) throws -> Void
    ) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        var info = awb_mz_entry_info()
        var status = awb_mz_reader_goto(handle, ordinal, &info)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        status = awb_mz_reader_open_current(handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var written: UInt64 = 0
        var readError: Error?
        while true {
            do {
                try Task.checkCancellation()
            } catch {
                readError = CancellationError()
                break
            }
            let count = buffer.withUnsafeMutableBufferPointer { bytes in
                awb_mz_reader_read_current(handle, bytes.baseAddress, Int32(bytes.count))
            }
            if count == 0 { break }
            if count < 0 {
                readError = ZIPProviderErrorMapper.archiveError(for: count)
                break
            }
            let (nextWritten, overflow) = written.addingReportingOverflow(UInt64(count))
            if overflow || nextWritten > maximumBytes {
                readError = ArchiveError.resourceLimit
                break
            }
            do {
                try emit(Data(buffer.prefix(Int(count))))
            } catch {
                readError = error
                break
            }
            written = nextWritten
        }

        let closeStatus = awb_mz_reader_close_current(handle)
        if let readError { throw readError }
        guard closeStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: closeStatus)
        }
        guard written == expectedSize else {
            throw ArchiveError.corruptedArchive
        }
    }

    func sha256Entry(ordinal: UInt64, expectedSize: UInt64, maximumBytes: UInt64) throws -> Data {
        guard let handle else { throw ArchiveError.helperFailed }
        var info = awb_mz_entry_info()
        var status = awb_mz_reader_goto(handle, ordinal, &info)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        status = awb_mz_reader_open_current(handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var totalRead: UInt64 = 0
        var readError: Error?
        while true {
            do {
                try Task.checkCancellation()
            } catch {
                readError = CancellationError()
                break
            }
            let count = buffer.withUnsafeMutableBufferPointer { bytes in
                awb_mz_reader_read_current(handle, bytes.baseAddress, Int32(bytes.count))
            }
            if count == 0 { break }
            if count < 0 {
                readError = ZIPProviderErrorMapper.archiveError(for: count)
                break
            }
            let (nextTotal, overflow) = totalRead.addingReportingOverflow(UInt64(count))
            if overflow || nextTotal > maximumBytes {
                readError = ArchiveError.resourceLimit
                break
            }
            hasher.update(data: Data(buffer.prefix(Int(count))))
            totalRead = nextTotal
        }

        let closeStatus = awb_mz_reader_close_current(handle)
        if let readError { throw readError }
        guard closeStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: closeStatus)
        }
        guard totalRead == expectedSize else { throw ArchiveError.corruptedArchive }
        return Data(hasher.finalize())
    }

    func streamEntry(
        ordinal: UInt64,
        expectedSize: UInt64,
        maximumBytes: UInt64,
        writer: SecureFileWriter,
        progress: (UInt64) -> Void
    ) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        var info = awb_mz_entry_info()
        var status = awb_mz_reader_goto(handle, ordinal, &info)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        status = awb_mz_reader_open_current(handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var written: UInt64 = 0
        var readError: Error?
        while true {
            do {
                try Task.checkCancellation()
            } catch {
                readError = CancellationError()
                break
            }
            let count = buffer.withUnsafeMutableBufferPointer { bytes in
                awb_mz_reader_read_current(handle, bytes.baseAddress, Int32(bytes.count))
            }
            if count == 0 { break }
            if count < 0 {
                readError = ZIPProviderErrorMapper.archiveError(for: count)
                break
            }
            let (nextWritten, overflow) = written.addingReportingOverflow(UInt64(count))
            if overflow || nextWritten > maximumBytes {
                readError = ArchiveError.resourceLimit
                break
            }
            do {
                try writer.write(Data(buffer.prefix(Int(count))))
            } catch {
                readError = error
                break
            }
            written = nextWritten
            progress(written)
        }

        let closeStatus = awb_mz_reader_close_current(handle)
        if let readError { throw readError }
        guard closeStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: closeStatus)
        }
        guard written == expectedSize else {
            throw ArchiveError.corruptedArchive
        }
    }

    private func copy(_ info: awb_mz_entry_info) throws -> ZIPBridgeEntry {
        guard let nameBytes = info.name_bytes, info.name_size > 0 else {
            throw ArchiveError.corruptedArchive
        }
        let name = Array(UnsafeBufferPointer(start: nameBytes, count: Int(info.name_size)))
        return ZIPBridgeEntry(
            nameBytes: name,
            compressedSize: info.compressed_size,
            uncompressedSize: info.uncompressed_size,
            modifiedAt: info.modified_unix_time > 0
                ? Date(timeIntervalSince1970: TimeInterval(info.modified_unix_time))
                : nil,
            modifiedUnixTime: info.modified_unix_time,
            isDirectory: info.is_directory != 0,
            isSymbolicLink: info.is_symlink != 0,
            isEncrypted: info.is_encrypted != 0,
            usesUTF8FileName: info.uses_utf8_file_name != 0
        )
    }
}
