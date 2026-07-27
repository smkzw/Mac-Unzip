import ArchiveDomain
import ArchiveSecurity
import Foundation

// MARK: - Read-only DMG provider backed by the system 7zz binary
//
// Design principles (from handoff):
// - DMG：只读、安全、无自动执行的浏览/挂载/提取
// - This provider NEVER mounts the DMG (avoids auto-execution of any embedded
//   code, launchd plists, or scripts that macOS would run on mount).
// - Uses 7zz l -slt for listing and 7zz x -so for extraction to stdout.
// - provider 能力必须按真实运行时发现和验证：capabilities are gated on a
//   successful discovery, never assumed from a design matrix.
// - 不允许 mutation 静默 fallback 到不同引擎：this provider is strictly
//   read-only (.list/.read/.preview). DMG creation/modification is intentionally
//   not implemented.
// - Security: never auto-open, never execute contents, never mount.

// MARK: - DMG-specific errors

public enum DMGProviderError: Error, Equatable, Sendable {
    /// No validated 7zz binary was found at the known install locations.
    case binaryNotFound
    /// The DMG is encrypted and cannot be read without a password.
    case encryptedImage
}

// MARK: - Provider

public actor DMGArchiveProvider: ArchiveProvider {
    private let binaryPath: String
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
        listingTimeoutSeconds: Int = 30,
        extractionTimeoutSeconds: Int = 600,
        listingEntryLimit: Int = 1_000_000
    ) {
        self.binaryPath = binaryPath
        self.listingTimeoutSeconds = listingTimeoutSeconds
        self.extractionTimeoutSeconds = extractionTimeoutSeconds
        self.listingEntryLimit = listingEntryLimit
        self.maximumStdoutListingBytes = 256 * 1024 * 1024
    }

    /// Discovers and validates the system 7zz binary, then constructs a provider.
    /// Throws DMGProviderError.binaryNotFound when no binary qualifies.
    public static func makeValidated() throws -> DMGArchiveProvider {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw DMGProviderError.binaryNotFound
        }
        return DMGArchiveProvider(binaryPath: discovery.resolvedPath)
    }

    public func open(url: URL) throws -> ArchiveDocumentSnapshot {
        archiveURL = nil
        entriesByID = [:]

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
                rawPath: ArchivePathBytes(Array(normalized.utf8)),
                displayPath: validationPath
            )
            snapshots.append(ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: parsed.packedSize,
                uncompressedSize: parsed.size,
                modifiedAt: parsed.modifiedAt,
                isDirectory: isDirectory,
                isSymbolicLink: false,
                isEncrypted: parsed.encrypted,
                usesUTF8FileName: true
            ))
        }

        archiveURL = url
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .dmg, entries: snapshots)
    }

    public func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data {
        guard let snapshot = entriesByID[id], let archiveURL else {
            throw ArchiveError.helperFailed
        }
        guard !snapshot.isDirectory else { throw ArchiveError.unsafePath }
        guard !snapshot.isEncrypted else { throw ArchiveError.passwordRequired }
        guard snapshot.uncompressedSize <= maximumBytes,
              snapshot.uncompressedSize <= UInt64(Int.max) else {
            throw ArchiveError.resourceLimit
        }
        let result = try invoke(
            arguments: [
                "x", "-so", "-y", "-spd", "-bso0", "-bsp0",
                archiveURL.path, snapshot.entry.displayPath,
            ],
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: Int(maximumBytes) + 1
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
    /// encrypted-entry rejection, resource budget enforcement, and post-extraction
    /// symlink/containment verification.
    ///
    /// Security: extracted files are never executed. The caller is responsible for
    /// not opening extracted contents automatically.
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
        guard !snapshots.contains(where: { $0.isEncrypted }) else {
            throw ArchiveError.passwordRequired
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
            path: ".dmg-staging-\(UUID().uuidString)",
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
                let data = try Data(contentsOf: stagedFile)
                _ = try materializer.write(data, relativePath: path)
                writtenBytes += UInt64(data.count)
            }
            completedEntries += 1
            progress(SevenZipExtractionProgress(
                completedEntries: completedEntries,
                totalEntries: snapshots.count,
                completedBytes: writtenBytes,
                totalBytes: expandedBytes
            ))
        }
        try FileManager.default.removeItem(at: stagingURL)
        published = true
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
                maximumStdoutBytes: maximumStdoutBytes
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
        if text.contains("wrong password")
            || text.contains("password")
            || text.contains("enter password")
            || text.contains("encrypted") {
            return .passwordRequired
        }
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
            options: [.skipsHiddenFiles]
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
