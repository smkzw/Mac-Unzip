import ArchiveDomain
import ArchiveSecurity
import Foundation

// MARK: - Read-only RAR provider backed by the system 7zz binary
//
// Design principles (from handoff):
// - RAR：浏览、搜索、预览、解压，包括 RAR4/5、加密、solid、Unicode、multipart
// - 7z/RAR 读取计划走隔离、验证后的 7zz：reuses the same SevenZipBinaryDiscovery
//   and SevenZipProcessRunner infrastructure that validates the binary at runtime.
// - provider 能力必须按真实运行时发现和验证：capabilities are gated on a
//   successful discovery, never assumed from a design matrix.
// - 不允许 mutation 静默 fallback 到不同引擎：this provider is strictly
//   read-only (.list/.read/.preview). RAR creation requires RARLAB's proprietary
//   rar binary and is intentionally not implemented here.
// - Password is passed to 7zz as a -p<password> argv token. 7zz provides no
//   stdin-based password channel, so this is unavoidable; the token is briefly
//   visible to same-user process listings (ps) for the lifetime of the process.

// MARK: - RAR-specific errors

public enum RARProviderError: Error, Equatable, Sendable {
    /// No validated 7zz binary was found at the known install locations.
    case binaryNotFound
    /// A multipart RAR set is missing one or more volumes.
    case missingVolume(expected: String)
    /// The archive headers are encrypted and cannot be listed without a password.
    case encryptedHeaders
}

// MARK: - Multipart volume detection

/// Detects and validates multipart RAR volume sets.
///
/// RAR multipart patterns:
/// - Modern: archive.part1.rar, archive.part2.rar, ... (or .part01.rar, etc.)
/// - Legacy: archive.rar, archive.r00, archive.r01, ...
///
/// Only the first volume needs to be passed to 7zz; it locates subsequent
/// volumes automatically by naming convention in the same directory.
public struct RARMultipartDetector: Sendable {

    public struct VolumeSet: Equatable, Sendable {
        /// The first volume path that should be passed to 7zz.
        public let firstVolumePath: String
        /// All detected volume paths in order (may be incomplete).
        public let detectedVolumes: [String]
        /// True when this appears to be a multipart set.
        public let isMultipart: Bool
        /// Names of volumes that appear to be missing (gaps in sequence).
        public let missingVolumes: [String]

        public init(
            firstVolumePath: String,
            detectedVolumes: [String],
            isMultipart: Bool,
            missingVolumes: [String]
        ) {
            self.firstVolumePath = firstVolumePath
            self.detectedVolumes = detectedVolumes
            self.isMultipart = isMultipart
            self.missingVolumes = missingVolumes
        }
    }

    public init() {}

    /// Analyzes the given file URL to determine if it is part of a multipart
    /// RAR set and validates that all expected volumes are present.
    public func detect(firstVolumeURL: URL) -> VolumeSet {
        let directory = firstVolumeURL.deletingLastPathComponent()
        let fileName = firstVolumeURL.lastPathComponent
        let lowerName = fileName.lowercased()

        // Modern pattern: name.partN.rar (N can be multi-digit)
        if let partInfo = parseModernPartName(lowerName) {
            return detectModernVolumes(
                directory: directory,
                baseName: partInfo.baseName,
                partNumber: partInfo.number,
                partDigits: partInfo.digits,
                originalFileName: fileName
            )
        }

        // Legacy pattern: name.rar + name.r00, name.r01, ...
        if lowerName.hasSuffix(".rar") {
            return detectLegacyVolumes(
                directory: directory,
                fileName: fileName,
                lowerName: lowerName
            )
        }

        // Legacy continuation volume opened directly: name.r00, name.r01, ...
        if let legacyInfo = parseLegacyContinuationName(lowerName) {
            return detectLegacyFromContinuation(
                directory: directory,
                baseName: legacyInfo.baseName,
                originalFileName: fileName
            )
        }

        // Single-volume RAR
        return VolumeSet(
            firstVolumePath: firstVolumeURL.path,
            detectedVolumes: [firstVolumeURL.path],
            isMultipart: false,
            missingVolumes: []
        )
    }

    // MARK: - Modern pattern (.partN.rar)

    private struct PartInfo {
        let baseName: String
        let number: Int
        let digits: Int
    }

    private func parseModernPartName(_ lowerName: String) -> PartInfo? {
        // Match: <base>.part<N>.rar where N is one or more digits
        guard lowerName.hasSuffix(".rar") else { return nil }
        let withoutRar = String(lowerName.dropLast(4)) // drop ".rar"
        guard let partRange = withoutRar.range(of: ".part", options: .backwards) else { return nil }
        let numberStr = String(withoutRar[partRange.upperBound...])
        guard !numberStr.isEmpty, numberStr.allSatisfy(\.isNumber) else { return nil }
        guard let number = Int(numberStr) else { return nil }
        let baseName = String(withoutRar[..<partRange.lowerBound])
        guard !baseName.isEmpty else { return nil }
        return PartInfo(baseName: baseName, number: number, digits: numberStr.count)
    }

    private func detectModernVolumes(
        directory: URL,
        baseName: String,
        partNumber: Int,
        partDigits: Int,
        originalFileName: String
    ) -> VolumeSet {
        let fm = FileManager.default
        var detected: [String] = []
        var missing: [String] = []

        // Probe volumes starting from part1 upward until we find a gap
        var index = 1
        var foundFirst = false
        while true {
            let volumeName = modernVolumeName(baseName: baseName, number: index, digits: partDigits)
            let volumePath = directory.appending(path: volumeName).path
            if fm.fileExists(atPath: volumePath) {
                detected.append(volumePath)
                foundFirst = true
            } else if foundFirst {
                // Gap after finding at least one: probe one more to distinguish
                // end-of-set from a missing volume.
                let nextName = modernVolumeName(baseName: baseName, number: index + 1, digits: partDigits)
                let nextPath = directory.appending(path: nextName).path
                if fm.fileExists(atPath: nextPath) {
                    missing.append(volumeName)
                    detected.append(nextPath)
                    index += 2
                    continue
                } else {
                    break
                }
            } else {
                break
            }
            index += 1
            if index > 10_000 { break }
        }

        let firstVolume = detected.first ?? directory.appending(path: originalFileName).path
        return VolumeSet(
            firstVolumePath: firstVolume,
            detectedVolumes: detected,
            isMultipart: detected.count > 1 || partNumber > 1 || !missing.isEmpty,
            missingVolumes: missing
        )
    }

    private func modernVolumeName(baseName: String, number: Int, digits: Int) -> String {
        let numberStr = String(format: "%0\(digits)d", number)
        return "\(baseName).part\(numberStr).rar"
    }

    // MARK: - Legacy pattern (.rar + .r00, .r01, ...)

    private func detectLegacyVolumes(
        directory: URL,
        fileName: String,
        lowerName: String
    ) -> VolumeSet {
        let fm = FileManager.default
        let baseName = String(fileName.dropLast(4)) // drop ".rar"
        var detected: [String] = [directory.appending(path: fileName).path]
        var missing: [String] = []

        var index = 0
        var foundAny = false
        while true {
            let ext = String(format: "r%02d", index)
            let volumeName = "\(baseName).\(ext)"
            let volumePath = directory.appending(path: volumeName).path
            if fm.fileExists(atPath: volumePath) {
                detected.append(volumePath)
                foundAny = true
            } else if foundAny {
                let nextExt = String(format: "r%02d", index + 1)
                let nextName = "\(baseName).\(nextExt)"
                let nextPath = directory.appending(path: nextName).path
                if fm.fileExists(atPath: nextPath) {
                    missing.append(volumeName)
                    detected.append(nextPath)
                    index += 2
                    continue
                } else {
                    break
                }
            } else {
                break
            }
            index += 1
            if index > 10_000 { break }
        }

        return VolumeSet(
            firstVolumePath: detected.first!,
            detectedVolumes: detected,
            isMultipart: detected.count > 1 || !missing.isEmpty,
            missingVolumes: missing
        )
    }

    private struct LegacyContinuationInfo {
        let baseName: String
    }

    private func parseLegacyContinuationName(_ lowerName: String) -> LegacyContinuationInfo? {
        guard let dotRange = lowerName.range(of: ".", options: .backwards) else { return nil }
        let ext = String(lowerName[dotRange.upperBound...])
        guard ext.count >= 2, ext.first == "r", ext.dropFirst().allSatisfy(\.isNumber) else {
            return nil
        }
        let baseName = String(lowerName[..<dotRange.lowerBound])
        guard !baseName.isEmpty else { return nil }
        return LegacyContinuationInfo(baseName: baseName)
    }

    private func detectLegacyFromContinuation(
        directory: URL,
        baseName: String,
        originalFileName: String
    ) -> VolumeSet {
        let firstVolumeName = "\(baseName).rar"
        let firstVolumePath = directory.appending(path: firstVolumeName).path
        let fm = FileManager.default

        guard fm.fileExists(atPath: firstVolumePath) else {
            return VolumeSet(
                firstVolumePath: firstVolumePath,
                detectedVolumes: [directory.appending(path: originalFileName).path],
                isMultipart: true,
                missingVolumes: [firstVolumeName]
            )
        }

        return detectLegacyVolumes(
            directory: directory,
            fileName: firstVolumeName,
            lowerName: firstVolumeName.lowercased()
        )
    }
}

// MARK: - Provider

public actor RARArchiveProvider: ArchiveProvider {
    private let binaryPath: String
    private let binarySHA256: String?
    private let listingTimeoutSeconds: Int
    private let extractionTimeoutSeconds: Int
    private let listingEntryLimit: Int
    private let maximumStdoutListingBytes: Int
    private var archiveURL: URL?
    private var entriesByID: [ArchiveEntryID: ArchiveEntrySnapshot] = [:]
    private var isSolidArchive = false
    private var volumeSet: RARMultipartDetector.VolumeSet?
    private var currentPassword: SecurePassword?

    /// The capabilities this provider exposes. Read-only by design.
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
    /// Throws RARProviderError.binaryNotFound when no binary qualifies.
    public static func makeValidated() throws -> RARArchiveProvider {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw RARProviderError.binaryNotFound
        }
        return RARArchiveProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
    }

    /// True when the opened archive uses solid compression.
    public var isSolid: Bool { isSolidArchive }

    /// The detected volume set for multipart archives.
    public var currentVolumeSet: RARMultipartDetector.VolumeSet? { volumeSet }

    public func open(url: URL) throws -> ArchiveDocumentSnapshot {
        archiveURL = nil
        entriesByID = [:]
        isSolidArchive = false
        currentPassword = nil

        // Detect multipart volumes and validate completeness
        let detector = RARMultipartDetector()
        let detected = detector.detect(firstVolumeURL: url)
        volumeSet = detected

        // If volumes are missing, report a clear error
        if !detected.missingVolumes.isEmpty {
            throw ArchiveError.missingVolume
        }

        // Use the first volume for 7zz (it finds others automatically)
        let targetPath = detected.firstVolumePath

        let result = try invoke(
            arguments: ["l", "-slt", targetPath],
            timeoutSeconds: listingTimeoutSeconds,
            maximumStdoutBytes: maximumStdoutListingBytes
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: true)
        }
        guard !result.stdoutExceeded else { throw ArchiveError.resourceLimit }

        let parse = SevenZipListingParser().parse(String(decoding: result.stdout, as: UTF8.self))
        isSolidArchive = parse.signals.isSolid

        // Update multipart status from 7zz's own detection
        if parse.signals.isMultipart {
            volumeSet = RARMultipartDetector.VolumeSet(
                firstVolumePath: detected.firstVolumePath,
                detectedVolumes: detected.detectedVolumes,
                isMultipart: true,
                missingVolumes: detected.missingVolumes
            )
        }

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
                isEncrypted: parsed.encrypted,
                usesUTF8FileName: true
            ))
        }

        archiveURL = url
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .rar, entries: snapshots)
    }

    public func openWithPassword(url: URL, password: String) throws -> ArchiveDocumentSnapshot {
        archiveURL = nil
        entriesByID = [:]
        isSolidArchive = false
        currentPassword = SecurePassword(password)

        let detector = RARMultipartDetector()
        let detected = detector.detect(firstVolumeURL: url)
        volumeSet = detected

        if !detected.missingVolumes.isEmpty {
            throw ArchiveError.missingVolume
        }

        let targetPath = detected.firstVolumePath

        // 7zz has no stdin/askpass password interface; the password is briefly visible in argv (ps).
        let result = try invoke(
            arguments: ["l", "-slt", "-p\(password)", targetPath],
            timeoutSeconds: listingTimeoutSeconds,
            maximumStdoutBytes: maximumStdoutListingBytes
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: true)
        }
        guard !result.stdoutExceeded else { throw ArchiveError.resourceLimit }

        let parse = SevenZipListingParser().parse(String(decoding: result.stdout, as: UTF8.self))
        isSolidArchive = parse.signals.isSolid

        if parse.signals.isMultipart {
            volumeSet = RARMultipartDetector.VolumeSet(
                firstVolumePath: detected.firstVolumePath,
                detectedVolumes: detected.detectedVolumes,
                isMultipart: true,
                missingVolumes: detected.missingVolumes
            )
        }

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
                isEncrypted: parsed.encrypted,
                usesUTF8FileName: true
            ))
        }

        archiveURL = url
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .rar, entries: snapshots)
    }

    public func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data {
        guard let snapshot = entriesByID[id], let archiveURL else {
            throw ArchiveError.helperFailed
        }
        guard !snapshot.isDirectory else { throw ArchiveError.unsafePath }
        if snapshot.isEncrypted && currentPassword == nil { throw ArchiveError.passwordRequired }
        guard snapshot.uncompressedSize <= maximumBytes,
              snapshot.uncompressedSize <= UInt64(Int.max) else {
            throw ArchiveError.resourceLimit
        }
        // Use the first volume path for extraction (7zz finds other volumes)
        let targetPath = volumeSet?.firstVolumePath ?? archiveURL.path
        var arguments = ["x", "-so", "-y", "-spd", "-bso0", "-bsp0"]
        if let password = currentPassword {
            // 7zz has no stdin/askpass password interface; the password is briefly visible in argv (ps).
            password.withCString { ptr in
                arguments.append("-p" + String(cString: ptr))
            }
        }
        arguments.append(targetPath)
        arguments.append("-i!" + String(decoding: snapshot.entry.rawPath.bytes, as: UTF8.self))
        let result = try invoke(
            arguments: arguments,
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: Int(clamping: maximumBytes) == Int.max ? Int.max : Int(clamping: maximumBytes) + 1
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: false)
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
        if snapshots.contains(where: { $0.isEncrypted }) && currentPassword == nil {
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
            path: ".rar-staging-\(UUID().uuidString)",
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

        let targetPath = volumeSet?.firstVolumePath ?? archiveURL.path
        var extractArguments = ["x", "-y", "-bso0", "-bsp0"]
        if let password = currentPassword {
            password.withCString { ptr in
                extractArguments.append("-p" + String(cString: ptr))
            }
        }
        extractArguments.append("-o\(stagingURL.path)")
        extractArguments.append(targetPath)
        let result = try invoke(
            arguments: extractArguments,
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: 1 << 20
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: false)
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

    private func mapError(
        result: SevenZipProcessResult,
        forListing: Bool
    ) -> ArchiveError {
        let text = (String(decoding: result.stderr, as: UTF8.self)
            + "\n"
            + String(decoding: result.stdout, as: UTF8.self)).lowercased()
        // Encrypted headers or password-protected content
        if text.contains("wrong password")
            || text.contains("enter password")
            || text.contains("cannot open encrypted archive")
            || text.contains("encrypted headers") {
            return .passwordRequired
        }
        // Compression/encryption 7zz cannot handle (e.g. RAR5 AES decryption)
        if text.contains("unsupported encryption") {
            return .unsupportedEncryption
        }
        if text.contains("unsupported method") {
            return .unsupportedMethod
        }
        // Missing volumes in a multipart set
        if text.contains("cannot open archive")
            || text.contains("no more files")
            || text.contains("unexpected end")
            || text.contains("missing volume")
            || text.contains("cannot find volume") {
            return .missingVolume
        }
        // Corrupted or unsupported
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
