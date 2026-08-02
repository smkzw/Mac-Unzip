import ArchiveDomain
import ArchiveSecurity
import Foundation

// MARK: - Read-only ISO provider backed by the system 7zz binary
//
// Design principles (from handoff):
// - ISO：只读浏览/提取，覆盖 ISO9660/UDF/Joliet/Rock Ridge
// - Uses 7zz which natively supports ISO9660, UDF, Joliet, and Rock Ridge
//   extensions without requiring any mounting or kernel-level access.
// - provider 能力必须按真实运行时发现和验证：capabilities are gated on a
//   successful discovery, never assumed from a design matrix.
// - 不允许 mutation 静默 fallback 到不同引擎：this provider is strictly
//   read-only (.list/.read/.preview). ISO creation/modification is intentionally
//   not implemented.
// - Multi-session ISOs: 7zz lists all sessions automatically; entries from all
//   sessions appear in the unified listing.
// - Security: never mount, never auto-open, never execute contents.

// MARK: - ISO-specific errors

public enum ISOProviderError: Error, Equatable, Sendable {
    /// No validated 7zz binary was found at the known install locations.
    case binaryNotFound
}

// MARK: - Provider

public actor ISOArchiveProvider: ArchiveProvider {
    private let binaryPath: String
    private let binarySHA256: String?
    private let listingTimeoutSeconds: Int
    private let extractionTimeoutSeconds: Int
    private let listingEntryLimit: Int
    private let maximumStdoutListingBytes: Int
    private var archiveURL: URL?
    private var entriesByID: [ArchiveEntryID: ArchiveEntrySnapshot] = [:]

    /// The capabilities this provider exposes. Strictly read-only by design.
    public static let capabilities: Set<SevenZipCapability> = [.list, .read, .preview]

    /// - Parameter binaryPath: a validated 7zz path. Use makeValidated() to
    ///   discover and validate the system binary first.
    public init(
        binaryPath: String,
        binarySHA256: String? = nil,
        listingTimeoutSeconds: Int = 30,
        extractionTimeoutSeconds: Int = 600,
        listingEntryLimit: Int = 1_000_000
    ) {
        self.binaryPath = binaryPath
        self.binarySHA256 = binarySHA256
        self.listingTimeoutSeconds = listingTimeoutSeconds
        self.extractionTimeoutSeconds = extractionTimeoutSeconds
        self.listingEntryLimit = listingEntryLimit
        self.maximumStdoutListingBytes = 256 * 1024 * 1024
    }

    /// Discovers and validates the system 7zz binary, then constructs a provider.
    /// Throws ISOProviderError.binaryNotFound when no binary qualifies.
    public static func makeValidated() throws -> ISOArchiveProvider {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw ISOProviderError.binaryNotFound
        }
        return ISOArchiveProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
    }

    public func open(url: URL) throws -> ArchiveDocumentSnapshot {
        archiveURL = nil
        entriesByID = [:]

        // 7zz l -slt handles ISO9660, UDF, Joliet, Rock Ridge, and multi-session
        // ISOs transparently. All sessions are listed in a single unified output.
        let result = try invoke(
            arguments: ["l", "-slt", url.path],
            timeoutSeconds: listingTimeoutSeconds,
            maximumStdoutBytes: maximumStdoutListingBytes
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result)
        }
        guard !result.stdoutExceeded else { throw ArchiveError.resourceLimit }

        let parse = SevenZipListingParser().parse(String(decoding: result.stdout, as: UTF8.self))

        guard parse.entries.count <= listingEntryLimit else {
            throw ArchiveError.resourceLimit
        }

        var snapshots: [ArchiveEntrySnapshot] = []
        snapshots.reserveCapacity(parse.entries.count)
        for parsed in parse.entries {
            let normalized = parsed.path.replacingOccurrences(of: "\\", with: "/")
            let isDirectory = parsed.isDirectory || normalized.hasSuffix("/")
            let validationPath = isDirectory && normalized.hasSuffix("/")
                ? String(normalized.dropLast())
                : normalized
            do {
                try ArchivePathPolicy().validate(validationPath)
            } catch {
                throw ArchiveError.unsafePath
            }
            let entry = ArchiveEntry(
                id: ArchiveEntryID(),
                rawPath: ArchivePathBytes(Array(parsed.path.utf8)),
                displayPath: validationPath
            )
            snapshots.append(ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: parsed.packedSize,
                uncompressedSize: parsed.size,
                modifiedAt: parsed.modifiedAt,
                isDirectory: isDirectory,
                isSymbolicLink: false,
                isEncrypted: false, // ISO9660/UDF do not support encryption
                usesUTF8FileName: true
            ))
        }

        archiveURL = url
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .iso, entries: snapshots)
    }

    public func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data {
        guard let snapshot = entriesByID[id], let archiveURL else {
            throw ArchiveError.helperFailed
        }
        guard !snapshot.isDirectory else { throw ArchiveError.unsafePath }
        guard snapshot.uncompressedSize <= maximumBytes,
              snapshot.uncompressedSize <= UInt64(Int.max) else {
            throw ArchiveError.resourceLimit
        }
        let result = try invoke(
            arguments: [
                "x", "-so", "-y", "-spd", "-bso0", "-bsp0",
                archiveURL.path, "-i!" + String(decoding: snapshot.entry.rawPath.bytes, as: UTF8.self),
            ],
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: Int(clamping: maximumBytes) == Int.max ? Int.max : Int(clamping: maximumBytes) + 1
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result)
        }
        guard UInt64(result.stdout.count) == snapshot.uncompressedSize else {
            throw ArchiveError.corruptedArchive
        }
        return result.stdout
    }

    public func materializeEntry(
        id: ArchiveEntryID,
        under rootURL: URL,
        budget: ResourceBudget = .previewDefault
    ) throws -> URL {
        try Task.checkCancellation()
        guard let snapshot = entriesByID[id] else { throw ArchiveError.helperFailed }
        let decision = budget.evaluate(ResourceEstimate(
            compressedBytes: snapshot.compressedSize,
            expandedBytes: snapshot.uncompressedSize,
            entries: 1,
            depth: 1
        ))
        guard decision == .allow else { throw ArchiveError.resourceLimit }
        let data = try readEntry(id: id, maximumBytes: budget.maxExpandedBytes)
        try Task.checkCancellation()
        let output = try SecureFileMaterializer(rootURL: rootURL).write(
            data,
            relativePath: snapshot.entry.displayPath
        )
        try Task.checkCancellation()
        return output
    }

    /// Extracts every entry under rootURL using 7zz x, with path validation,
    /// resource budget enforcement, and post-extraction symlink/containment
    /// verification.
    ///
    /// Handles multi-session ISOs: 7zz extracts all sessions transparently.
    public func extractAll(
        under rootURL: URL,
        budget: ResourceBudget = .extractionDefault,
        progress: @Sendable (SevenZipExtractionProgress) -> Void = { _ in }
    ) throws -> SevenZipExtractionResult {
        try Task.checkCancellation()
        guard let archiveURL else { throw ArchiveError.helperFailed }
        let snapshots = entriesByID.values.sorted {
            $0.entry.displayPath < $1.entry.displayPath
        }
        try validateExtractionPaths(snapshots)

        var compressedBytes: UInt64 = 0
        var expandedBytes: UInt64 = 0
        var maximumDepth: UInt64 = 0
        for snapshot in snapshots {
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
            entries: UInt64(snapshots.count),
            depth: maximumDepth
        )) == .allow else {
            throw ArchiveError.resourceLimit
        }

        progress(SevenZipExtractionProgress(
            completedEntries: 0,
            totalEntries: snapshots.count,
            completedBytes: 0,
            totalBytes: expandedBytes
        ))

        let stagingURL = rootURL.appending(
            path: ".iso-staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var published = false
        defer {
            if !published { try? FileManager.default.removeItem(at: stagingURL) }
        }

        let result = try invoke(
            arguments: [
                "x", "-y", "-bso0", "-bsp0",
                "-o\(stagingURL.path)", archiveURL.path,
            ],
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: 1 << 20
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result)
        }
        try Task.checkCancellation()
        let stagingSize = FileManager.default
            .enumerator(at: stagingURL, includingPropertiesForKeys: [.fileSizeKey])?
            .compactMap { (try? ($0 as? URL)?.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
            .reduce(0, +) ?? 0
        guard UInt64(stagingSize) <= budget.maxExpandedBytes else {
            throw ArchiveError.resourceLimit
        }
        try verifyNoSymlinksAndContained(under: stagingURL)
        try Task.checkCancellation()

        let materializer = SecureFileMaterializer(rootURL: rootURL)
        var completedEntries = 0
        var writtenBytes: UInt64 = 0
        for snapshot in snapshots {
            try Task.checkCancellation()
            let path = snapshot.entry.displayPath
            if snapshot.isDirectory {
                _ = try materializer.createDirectory(relativePath: path)
            } else {
                let stagedFile = stagingURL.appending(path: path)
                var fileBytes: UInt64 = 0
                _ = try materializer.write(relativePath: path) { writer in
                    let fd = stagedFile.withUnsafeFileSystemRepresentation { p -> Int32 in
                        guard let p else { return -1 }
                        return Darwin.open(p, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                    }
                    guard fd >= 0 else {
                        throw ArchiveError.helperFailed
                    }
                    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                    defer { try? handle.close() }
                    while true {
                        try Task.checkCancellation()
                        let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                        if chunk.isEmpty { break }
                        try writer.write(chunk)
                        fileBytes += UInt64(chunk.count)
                    }
                }
                if snapshot.uncompressedSize > 0, fileBytes != snapshot.uncompressedSize {
                    throw ArchiveError.corruptedArchive
                }
                writtenBytes += fileBytes
            }
            completedEntries += 1
            progress(SevenZipExtractionProgress(
                completedEntries: completedEntries,
                totalEntries: snapshots.count,
                completedBytes: writtenBytes,
                totalBytes: expandedBytes
            ))
        }
        published = true
        try? FileManager.default.removeItem(at: stagingURL)
        return SevenZipExtractionResult(
            completedEntries: completedEntries,
            expandedBytes: writtenBytes
        )
    }

    // MARK: Private helpers

    private func invoke(
        arguments: [String],
        timeoutSeconds: Int,
        maximumStdoutBytes: Int
    ) throws -> SevenZipProcessResult {
        do {
            return try SevenZipProcessRunner().run(
                executablePath: binaryPath,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds,
                maximumStdoutBytes: maximumStdoutBytes,
                expectedSHA256: binarySHA256
            )
        } catch let error as SevenZipHelperError {
            switch error {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw SevenZipProviderError.helperTimedOut
            case .spawnFailed, .drainFailure:
                throw ArchiveError.helperFailed
            }
        }
    }

    private func mapError(result: SevenZipProcessResult) -> ArchiveError {
        let text = (String(decoding: result.stderr, as: UTF8.self)
            + "\n"
            + String(decoding: result.stdout, as: UTF8.self)).lowercased()
        if text.contains("cannot open archive")
            || text.contains("no more files")
            || text.contains("unexpected end") {
            return .corruptedArchive
        }
        if text.contains("data error")
            || text.contains("crc failed")
            || text.contains("headers error")
            || text.contains("is not supported archive") {
            return .corruptedArchive
        }
        return .helperFailed
    }

    private func validateExtractionPaths(_ snapshots: [ArchiveEntrySnapshot]) throws {
        var canonicalPaths: Set<String> = []
        for snapshot in snapshots {
            let canonical = snapshot.entry.displayPath
                .decomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard canonicalPaths.insert(canonical).inserted else {
                throw ArchiveError.unsafePath
            }
        }
    }

    private func verifyNoSymlinksAndContained(under root: URL) throws {
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else { return }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ArchiveError.unsafePath }
            guard fileURL.standardizedFileURL.path.hasPrefix(rootPath + "/") else {
                throw ArchiveError.unsafePath
            }
        }
    }
}
