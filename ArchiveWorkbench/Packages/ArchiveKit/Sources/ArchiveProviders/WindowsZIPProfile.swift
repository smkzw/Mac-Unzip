import ArchiveDomain
import ArchiveSecurity
import CMinizipBridge
import CryptoKit
import Darwin
import Foundation

public enum WindowsZIPProfileError: Error, Equatable, Sendable {
    case noInputs
    case invalidName(String)
    case collision(String, String)
    case unsupportedItem(String)
    case outputExists
    case io(Int32)
}

public struct WindowsZIPCreationProgress: Equatable, Sendable {
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

extension ZIPArchiveProvider {
    public func createWindowsZIP(at outputURL: URL, inputs: [URL]) throws {
        try createWindowsZIP(at: outputURL, inputs: inputs) { _ in }
    }

    public func createWindowsZIP(
        at outputURL: URL,
        inputs: [URL],
        compressLevel: Int32 = AWB_MZ_LEVEL_NORMAL,
        password: String? = nil,
        encryptMethod: Int32 = AWB_MZ_ENCRYPT_NONE,
        progress: @Sendable (WindowsZIPCreationProgress) -> Void
    ) throws {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw WindowsZIPProfileError.outputExists
        }
        let entries = try WindowsZIPPreflight().collect(inputs: inputs)
        let totalBytes = try entries.reduce(into: UInt64(0)) { total, entry in
            guard let fingerprint = entry.fileFingerprint else { return }
            guard fingerprint.fileSize >= 0 else {
                throw WindowsZIPProfileError.unsupportedItem(entry.archivePath)
            }
            let (next, overflow) = total.addingReportingOverflow(UInt64(fingerprint.fileSize))
            guard !overflow else { throw ArchiveError.resourceLimit }
            total = next
        }
        try Task.checkCancellation()
        let stageURL = outputURL.deletingLastPathComponent().appending(
            path: "." + outputURL.lastPathComponent + ".staging-" + UUID().uuidString
        )
        var stageExists = false
        defer {
            if stageExists { try? FileManager.default.removeItem(at: stageURL) }
        }

        let securePassword: SecurePassword? = password.map { SecurePassword($0) }
        let writer = try ZIPBridgeWriter(url: stageURL, compressLevel: compressLevel, password: securePassword, encryptMethod: encryptMethod)
        stageExists = true
        var completedEntries = 0
        var completedBytes: UInt64 = 0
        progress(WindowsZIPCreationProgress(
            completedEntries: 0,
            totalEntries: entries.count,
            completedBytes: 0,
            totalBytes: totalBytes
        ))
        for entry in entries {
            try Task.checkCancellation()
            if let fingerprint = entry.fileFingerprint {
                try writer.add(
                    sourceURL: entry.sourceURL,
                    archivePath: entry.archivePath,
                    expectedSize: UInt64(fingerprint.fileSize),
                    modifiedUnixTime: entry.modifiedUnixTime
                ) { count in
                    completedBytes += UInt64(count)
                    progress(WindowsZIPCreationProgress(
                        completedEntries: completedEntries,
                        totalEntries: entries.count,
                        completedBytes: completedBytes,
                        totalBytes: totalBytes
                    ))
                    try Task.checkCancellation()
                }
                guard try fingerprint == SourceFingerprint(url: entry.sourceURL) else {
                    throw ArchiveError.sourceChanged
                }
            } else {
                try writer.addDirectory(
                    archivePath: entry.archivePath,
                    modifiedUnixTime: entry.modifiedUnixTime
                )
            }
            completedEntries += 1
            progress(WindowsZIPCreationProgress(
                completedEntries: completedEntries,
                totalEntries: entries.count,
                completedBytes: completedBytes,
                totalBytes: totalBytes
            ))
        }
        try Task.checkCancellation()
        try writer.finish()
        try syncFile(at: stageURL)
        let isEncrypted = securePassword.map { !$0.isEmpty } ?? false
        try verify(stageURL: stageURL, expectedEntries: entries, expectEncrypted: isEncrypted, password: securePassword)
        try Task.checkCancellation()
        try publishExclusively(stageURL: stageURL, outputURL: outputURL)
        stageExists = false
    }

    private func syncFile(at url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw WindowsZIPProfileError.io(errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw WindowsZIPProfileError.io(errno) }
    }

    private func verify(stageURL: URL, expectedEntries: [WindowsZIPInputEntry], expectEncrypted: Bool, password: SecurePassword?) throws {
        let reader: ZIPBridgeReader
        if expectEncrypted, let password {
            reader = try ZIPBridgeReader(url: stageURL, password: password)
        } else {
            reader = try ZIPBridgeReader(url: stageURL)
        }
        let entries = try reader.allEntries(maximumCount: expectedEntries.count + 1)
        guard entries.count == expectedEntries.count else { throw ArchiveError.sourceChanged }
        for (ordinal, pair) in zip(entries, expectedEntries).enumerated() {
            try Task.checkCancellation()
            let (entry, expected) = pair
            let expectedPath = expected.archivePath + (expected.isDirectory ? "/" : "")
            let expectedSize = expected.fileFingerprint.map { UInt64($0.fileSize) } ?? 0
            guard String(bytes: entry.nameBytes, encoding: .utf8) == expectedPath,
                  entry.usesUTF8FileName,
                  entry.isDirectory == expected.isDirectory,
                  !entry.isSymbolicLink,
                  entry.isEncrypted == expectEncrypted,
                  entry.uncompressedSize == expectedSize else {
                throw ArchiveError.sourceChanged
            }
            guard let fingerprint = expected.fileFingerprint else { continue }
            let digest = try reader.sha256Entry(
                ordinal: UInt64(ordinal),
                expectedSize: entry.uncompressedSize,
                maximumBytes: entry.uncompressedSize
            )
            guard digest == fingerprint.sha256 else {
                throw ArchiveError.sourceChanged
            }
        }
    }

    private func publishExclusively(stageURL: URL, outputURL: URL) throws {
        let linkResult = stageURL.withUnsafeFileSystemRepresentation { stagePath in
            outputURL.withUnsafeFileSystemRepresentation { outputPath in
                guard let stagePath, let outputPath else { return Int32(-1) }
                return Darwin.link(stagePath, outputPath)
            }
        }
        guard linkResult == 0 else {
            if errno == EEXIST { throw WindowsZIPProfileError.outputExists }
            throw WindowsZIPProfileError.io(errno)
        }
        do {
            try FileManager.default.removeItem(at: stageURL)
            try syncDirectory(at: outputURL.deletingLastPathComponent())
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private func syncDirectory(at url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw WindowsZIPProfileError.io(errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw WindowsZIPProfileError.io(errno) }
    }
}

private struct WindowsZIPInputEntry {
    let sourceURL: URL
    let archivePath: String
    let fileFingerprint: SourceFingerprint?
    let modifiedUnixTime: Int64

    var isDirectory: Bool { fileFingerprint == nil }
}

private struct SourceFingerprint: Equatable {
    let resourceIdentifier: String
    let fileSize: Int
    let modificationTime: TimeInterval
    let sha256: Data

    init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw WindowsZIPProfileError.unsupportedItem(url.lastPathComponent)
        }
        resourceIdentifier = String(describing: values.fileResourceIdentifier)
        fileSize = values.fileSize ?? -1
        modificationTime = values.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1
        sha256 = try Self.hash(url: url)
    }

    private static func hash(url: URL) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw WindowsZIPProfileError.io(errno) }
        defer { Darwin.close(descriptor) }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.read(descriptor, baseAddress, rawBuffer.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw WindowsZIPProfileError.io(errno)
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return Data(hasher.finalize())
    }
}

private struct WindowsZIPPreflight {
    private let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileResourceIdentifierKey,
        .fileSizeKey,
        .contentModificationDateKey,
    ]

    func collect(inputs: [URL]) throws -> [WindowsZIPInputEntry] {
        guard !inputs.isEmpty else { throw WindowsZIPProfileError.noInputs }
        var candidates: [(url: URL, path: String, isDirectory: Bool, modifiedAt: Date?)] = []
        for input in inputs {
            let values = try input.resourceValues(forKeys: resourceKeys)
            if values.isSymbolicLink == true {
                throw WindowsZIPProfileError.unsupportedItem(input.lastPathComponent)
            }
            if values.isRegularFile == true {
                candidates.append((input, input.lastPathComponent, false, values.contentModificationDate))
            } else if values.isDirectory == true {
                let nestedEntries = try entries(under: input)
                let hasVisibleEntry = nestedEntries.contains { entry in
                    !shouldSuppress(components: entry.path.split(separator: "/").map(String.init))
                }
                if !hasVisibleEntry {
                    candidates.append((input, input.lastPathComponent, true, values.contentModificationDate))
                } else {
                    candidates.append(contentsOf: nestedEntries)
                }
            } else {
                throw WindowsZIPProfileError.unsupportedItem(input.lastPathComponent)
            }
        }

        let normalized = try candidates.compactMap { candidate -> WindowsZIPInputEntry? in
            let sourceURL = candidate.url
            let relativePath = candidate.path
            let components = relativePath.split(separator: "/").map(String.init)
            if shouldSuppress(components: components) { return nil }
            let archivePath = components
                .map { $0.precomposedStringWithCanonicalMapping }
                .joined(separator: "/")
            try validate(path: archivePath)
            return WindowsZIPInputEntry(
                sourceURL: sourceURL,
                archivePath: archivePath,
                fileFingerprint: candidate.isDirectory ? nil : try SourceFingerprint(url: sourceURL),
                modifiedUnixTime: Int64(candidate.modifiedAt?.timeIntervalSince1970 ?? 0)
            )
        }
        guard !normalized.isEmpty else { throw WindowsZIPProfileError.noInputs }

        var seen: [String: String] = [:]
        for file in normalized {
            let key = file.archivePath.precomposedStringWithCanonicalMapping
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
            if let existing = seen[key] {
                let ordered = [existing, file.archivePath].sorted(by: >)
                throw WindowsZIPProfileError.collision(ordered[0], ordered[1])
            }
            seen[key] = file.archivePath
        }
        return normalized.sorted {
            Array($0.archivePath.utf8).lexicographicallyPrecedes(Array($1.archivePath.utf8))
        }
    }

    private func entries(
        under root: URL
    ) throws -> [(url: URL, path: String, isDirectory: Bool, modifiedAt: Date?)] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw WindowsZIPProfileError.unsupportedItem(root.lastPathComponent)
        }
        var result: [(url: URL, path: String, isDirectory: Bool, modifiedAt: Date?)] = []
        // The enumerator yields symlink-resolved paths; resolve the root too so the
        // prefix matches even when root sits under a symlinked component (/tmp -> /private/tmp).
        let prefix = root.resolvingSymlinksInPath().path + "/"
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard url.path.hasPrefix(prefix) else {
                throw WindowsZIPProfileError.unsupportedItem(url.lastPathComponent)
            }
            let relativePath = String(url.path.dropFirst(prefix.count))
            if values.isSymbolicLink == true {
                throw WindowsZIPProfileError.unsupportedItem(relativePath)
            }
            if values.isRegularFile == true {
                result.append((url, relativePath, false, values.contentModificationDate))
            } else if values.isDirectory == true {
                result.append((url, relativePath, true, values.contentModificationDate))
            } else if values.isDirectory != true {
                throw WindowsZIPProfileError.unsupportedItem(relativePath)
            }
        }
        if let enumerationError { throw enumerationError }
        return result
    }

    private func shouldSuppress(components: [String]) -> Bool {
        components.contains { component in
            component == ".DS_Store" || component == "__MACOSX" || component.hasPrefix("._")
        }
    }

    private func validate(path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, path.utf16.count <= 180 else {
            throw WindowsZIPProfileError.invalidName(path)
        }
        let forbidden = CharacterSet(charactersIn: "<>:\"/\\|?*")
        let reserved = Set(["CON", "PRN", "AUX", "NUL"])
        let reservedDeviceDigits = Set("123456789¹²³")
        for component in components {
            let upperStem = component.split(separator: ".", maxSplits: 1).first
                .map(String.init)?.uppercased() ?? ""
            let isNumberedDevice = (upperStem.hasPrefix("COM") || upperStem.hasPrefix("LPT"))
                && upperStem.count == 4
                && upperStem.last.map(reservedDeviceDigits.contains) == true
            let invalid = component.isEmpty
                || component.utf16.count > 255
                || component.hasSuffix(".")
                || component.hasSuffix(" ")
                || component.hasPrefix(" ")
                || component.unicodeScalars.contains { scalar in
                    scalar.value < 0x20 || forbidden.contains(scalar)
                }
                || reserved.contains(upperStem)
                || isNumberedDevice
            if invalid { throw WindowsZIPProfileError.invalidName(component) }
        }
    }
}

private final class ZIPBridgeWriter {
    private var handle: OpaquePointer?

    init(url: URL, compressLevel: Int32 = AWB_MZ_LEVEL_NORMAL, password: SecurePassword? = nil, encryptMethod: Int32 = AWB_MZ_ENCRYPT_NONE) throws {
        var opened: OpaquePointer?
        let status: Int32
        if let password {
            status = password.withCString { passwordPtr in
                url.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
                    return awb_mz_writer_open_configured(path, compressLevel, passwordPtr, encryptMethod, &opened)
                }
            }
        } else {
            status = url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
                return awb_mz_writer_open_configured(path, compressLevel, nil, encryptMethod, &opened)
            }
        }
        guard status == AWB_MZ_OK, let opened else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        handle = opened
    }

    deinit {
        if handle != nil { _ = awb_mz_writer_close(&handle) }
    }

    func add(
        sourceURL: URL,
        archivePath: String,
        expectedSize: UInt64,
        modifiedUnixTime: Int64,
        onChunk: (Int) throws -> Void
    ) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        let descriptor = sourceURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw WindowsZIPProfileError.io(errno) }
        defer { Darwin.close(descriptor) }

        let openStatus = archivePath.withCString {
            awb_mz_writer_open_entry(handle, $0, expectedSize, modifiedUnixTime)
        }
        guard openStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: openStatus)
        }
        var entryOpen = true
        defer {
            if entryOpen { _ = awb_mz_writer_close_entry(handle) }
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var totalRead: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.read(descriptor, baseAddress, rawBuffer.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw WindowsZIPProfileError.io(errno)
            }
            if count == 0 { break }

            var written = 0
            while written < count {
                let writeCount = buffer.withUnsafeBytes { rawBuffer -> Int32 in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return Int32(AWB_MZ_INVALID_ARGUMENT)
                    }
                    return awb_mz_writer_write_entry(
                        handle,
                        baseAddress.advanced(by: written).assumingMemoryBound(to: UInt8.self),
                        Int32(count - written)
                    )
                }
                guard writeCount > 0 else {
                    throw ZIPProviderErrorMapper.archiveError(for: writeCount)
                }
                written += Int(writeCount)
            }
            totalRead += UInt64(count)
            guard totalRead <= expectedSize else { throw ArchiveError.sourceChanged }
            try onChunk(count)
        }
        guard totalRead == expectedSize else { throw ArchiveError.sourceChanged }
        let closeStatus = awb_mz_writer_close_entry(handle)
        entryOpen = false
        guard closeStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: closeStatus)
        }
    }

    func addDirectory(archivePath: String, modifiedUnixTime: Int64) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        let directoryPath = archivePath + "/"
        let openStatus = directoryPath.withCString {
            awb_mz_writer_open_entry(handle, $0, 0, modifiedUnixTime)
        }
        guard openStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: openStatus)
        }
        let closeStatus = awb_mz_writer_close_entry(handle)
        guard closeStatus == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: closeStatus)
        }
    }

    func finish() throws {
        guard handle != nil else { throw ArchiveError.helperFailed }
        let status = awb_mz_writer_close(&handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
    }
}
