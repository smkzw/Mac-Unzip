import ArchiveDomain
import ArchiveOperations
import ArchiveSecurity
import CMinizipBridge
import CryptoKit
import Darwin
import Foundation

/// Errors specific to the transactional editing backend.
public enum ArchiveEditorError: Error, Equatable, Sendable {
    case noSourceArchive
    case missingEntry(String)
    case pathCollision(String, String)
    case invalidPath(String)
    case sourceNotAFile(String)
    case sourceUnreadable(String)
    case sourceArchiveChanged
    case unsupportedEntry(String)
    case outputExists
    case io(Int32)
}

struct EditorFileFingerprint: Equatable {
    let size: UInt64
    let sha256: Data
    let modifiedUnixTime: Int64

    init(fileURL: URL) throws {
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size >= 0 else {
            throw ArchiveEditorError.sourceNotAFile(fileURL.lastPathComponent)
        }
        self.size = UInt64(size)
        self.modifiedUnixTime = Int64(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
        self.sha256 = try EditorFileFingerprint.hash(fileURL)
    }

    private static func hash(_ url: URL) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw ArchiveEditorError.sourceUnreadable(url.lastPathComponent) }
        defer { Darwin.close(descriptor) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.read(descriptor, baseAddress, rawBuffer.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw ArchiveEditorError.sourceUnreadable(url.lastPathComponent)
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return Data(hasher.finalize())
    }
}

/// Internal model of a single entry in the archive being edited.
struct EditableEntry: Sendable {
    let ordinal: UInt64
    let nameBytes: [UInt8]
    /// Path used for matching changes; directories never carry a trailing slash.
    let normalizedPath: String
    let uncompressedSize: UInt64
    let modifiedUnixTime: Int64
    let isDirectory: Bool
    let usesUTF8FileName: Bool
    let isSymbolicLink: Bool
    let isEncrypted: Bool
}

/// A fully-resolved description of one entry to write into the staging archive.
private struct OutputEntry: Sendable {
    enum Source: Sendable {
        case original(ordinal: UInt64, uncompressedSize: UInt64)
        case file(URL)
        case directory
    }

    let nameBytes: [UInt8]
    let usesUTF8: Bool
    let modifiedUnixTime: Int64
    let isDirectory: Bool
    let source: Source
}

/// An actor that stages archive edits and publishes them through a
/// transactional, verify-before-replace save. The original archive is never
/// modified in place; save builds a staging ZIP, copies unchanged entries
/// verbatim, applies the staged edits, verifies the staging archive, and only
/// then atomically publishes it over the target.
public actor ArchiveEditor {
    private let listingEntryLimit: Int
    private let pathPolicy = ArchivePathPolicy()
    private let encodingDetector = EncodingDetector()
    private var sourceURL: URL?
    private var baseEntries: [EditableEntry] = []
    private var sourceFingerprint: EditorFileFingerprint?
    private var fingerprintUnavailable = false
    private var stagedChanges: [PendingChange] = []

    public init() {
        listingEntryLimit = 1_000_000
    }

    init(listingEntryLimit: Int) {
        self.listingEntryLimit = listingEntryLimit
    }

    public var pendingChanges: [PendingChange] { stagedChanges }

    public var hasPendingChanges: Bool { !stagedChanges.isEmpty }

    public var currentSourceURL: URL? { sourceURL }

    /// Opens an archive for editing, recording each entry's raw name bytes so
    /// unchanged entries can later be copied verbatim.
    public func open(url: URL) throws {
        let reader = try ZIPBridgeReader(url: url)
        let bridgeEntries = try reader.allEntries(maximumCount: listingEntryLimit)
        var entries: [EditableEntry] = []
        entries.reserveCapacity(bridgeEntries.count)
        for (ordinal, bridgeEntry) in bridgeEntries.enumerated() {
            let detection = encodingDetector.detect(
                rawBytes: bridgeEntry.nameBytes,
                usesUTF8Flag: bridgeEntry.usesUTF8FileName
            )
            let displayPath = detection.decodedName
            let normalized = bridgeEntry.isDirectory && displayPath.hasSuffix("/")
                ? String(displayPath.dropLast())
                : displayPath
            entries.append(EditableEntry(
                ordinal: UInt64(ordinal),
                nameBytes: bridgeEntry.nameBytes,
                normalizedPath: normalized,
                uncompressedSize: bridgeEntry.uncompressedSize,
                modifiedUnixTime: bridgeEntry.modifiedUnixTime,
                isDirectory: bridgeEntry.isDirectory,
                usesUTF8FileName: bridgeEntry.usesUTF8FileName,
                isSymbolicLink: bridgeEntry.isSymbolicLink,
                isEncrypted: bridgeEntry.isEncrypted
            ))
        }
        sourceURL = url
        baseEntries = entries
        sourceFingerprint = try? EditorFileFingerprint(fileURL: url)
        fingerprintUnavailable = sourceFingerprint == nil
        stagedChanges = []
    }

    public func reset() {
        sourceURL = nil
        baseEntries = []
        sourceFingerprint = nil
        stagedChanges = []
    }

    /// Stages a change without touching the original archive.
    public func stage(_ change: PendingChange) throws {
        guard sourceURL != nil else { throw ArchiveEditorError.noSourceArchive }
        try validateStructuralPaths(for: change)
        stagedChanges.append(change)
    }

    /// Removes the first staged change with the given identity (undo).
    @discardableResult
    public func undo(id: String) -> Bool {
        guard let index = stagedChanges.firstIndex(where: { $0.id == id }) else { return false }
        stagedChanges.remove(at: index)
        return true
    }

    /// Removes the most recently staged change (undo).
    @discardableResult
    public func undoLast() -> PendingChange? {
        stagedChanges.isEmpty ? nil : stagedChanges.removeLast()
    }

    public func undoAll() {
        stagedChanges = []
    }

    private func validateStructuralPaths(for change: PendingChange) throws {
        let candidates: [String]
        switch change {
        case let .add(_, destinationPath):
            candidates = [destinationPath]
        case let .rename(_, to):
            candidates = [to]
        case .remove, .replace:
            candidates = []
        }
        for path in candidates {
            do {
                try pathPolicy.validate(path)
            } catch {
                throw ArchiveEditorError.invalidPath(path)
            }
        }
    }

    /// Saves the staged changes back to the original archive location,
    /// atomically replacing it. Returns the published URL.
    @discardableResult
    public func save() throws -> URL {
        guard let sourceURL else { throw ArchiveEditorError.noSourceArchive }
        return try publish(to: sourceURL, allowOverwrite: true)
    }

    /// Saves the staged changes to a new location, atomically replacing any
    /// existing file at the target path. Returns the published URL.
    @discardableResult
    public func saveAs(to targetURL: URL) throws -> URL {
        guard sourceURL != nil else { throw ArchiveEditorError.noSourceArchive }
        return try publish(to: targetURL, allowOverwrite: true)
    }

    private func publish(to targetURL: URL, allowOverwrite: Bool) throws -> URL {
        guard let sourceURL else { throw ArchiveEditorError.noSourceArchive }
        try Task.checkCancellation()
        try verifySourceUnchanged()

        let plan = try buildPlan()
        let reader = try ZIPBridgeReader(url: sourceURL)

        let directory = targetURL.deletingLastPathComponent()
        let stageURL = directory.appending(
            path: "." + targetURL.lastPathComponent + ".editing-" + UUID().uuidString
        )

        // Write crash-recovery journal before any mutation begins.
        // If the process crashes between here and the atomic publish, the
        // journal remains on disk with state "in_progress" so the next
        // launch can offer recovery or deletion.
        let journal = CrashRecoveryJournal(
            sourceArchive: targetURL,
            stagingFile: stageURL,
            pendingChanges: stagedChanges
        )
        try CrashRecoveryJournalStore.write(journal, forArchiveAt: targetURL)

        var stageExists = false
        defer {
            if stageExists { try? FileManager.default.removeItem(at: stageURL) }
            // Clean up the journal on every non-crash exit path (success or
            // clean failure). A crash skips this defer, leaving the journal.
            CrashRecoveryJournalStore.deleteJournal(forArchiveAt: targetURL)
        }

        let writer = try EditorWriter(url: stageURL)
        stageExists = true
        var fileHashesByOrdinal: [UInt64: Data] = [:]
        for (index, entry) in plan.enumerated() {
            try Task.checkCancellation()
            try writeOutputEntry(entry, reader: reader, writer: writer)
            if case let .file(fileURL) = entry.source {
                fileHashesByOrdinal[UInt64(index)] = try EditorFileFingerprint(fileURL: fileURL).sha256
            }
        }
        try Task.checkCancellation()
        try writer.finish()
        try EditorAtomic.syncFile(at: stageURL)
        try verify(stageURL: stageURL, plan: plan, fileHashesByOrdinal: fileHashesByOrdinal)
        try Task.checkCancellation()
        try EditorAtomic.publish(stageURL: stageURL, targetURL: targetURL, allowOverwrite: allowOverwrite)
        stageExists = false

        try open(url: targetURL)
        return targetURL
    }

    private func verifySourceUnchanged() throws {
        guard let sourceURL else { return }
        guard let expected = sourceFingerprint else {
            if fingerprintUnavailable { throw ArchiveEditorError.sourceArchiveChanged }
            return
        }
        guard let actual = try? EditorFileFingerprint(fileURL: sourceURL) else {
            throw ArchiveEditorError.sourceArchiveChanged
        }
        guard actual.size == expected.size,
              actual.modifiedUnixTime == expected.modifiedUnixTime,
              actual.sha256 == expected.sha256 else {
            throw ArchiveEditorError.sourceArchiveChanged
        }
    }

    private func buildPlan() throws -> [OutputEntry] {
        var output: [OutputEntry] = try baseEntries.map { entry in
            guard !entry.isSymbolicLink else {
                throw ArchiveEditorError.unsupportedEntry(entry.normalizedPath)
            }
            guard !entry.isEncrypted else {
                throw ArchiveEditorError.unsupportedEntry(entry.normalizedPath)
            }
            return OutputEntry(
                nameBytes: entry.nameBytes,
                usesUTF8: entry.usesUTF8FileName,
                modifiedUnixTime: entry.modifiedUnixTime,
                isDirectory: entry.isDirectory,
                source: entry.isDirectory
                    ? .directory
                    : .original(ordinal: entry.ordinal, uncompressedSize: entry.uncompressedSize)
            )
        }
        var livePaths: [String] = baseEntries.map(\.normalizedPath)

        for change in stagedChanges {
            switch change {
            case let .remove(entryPath):
                let target = Self.normalize(entryPath)
                guard let index = livePaths.firstIndex(of: target) else {
                    throw ArchiveEditorError.missingEntry(target)
                }
                let targetPrefix = target + "/"
                livePaths.removeAll { $0 == target || $0.hasPrefix(targetPrefix) }
                output.removeAll {
                    let normalized = Self.normalize(nameBytes: $0.nameBytes, usesUTF8Flag: $0.usesUTF8)
                    return normalized == target || normalized.hasPrefix(targetPrefix)
                }

            case let .rename(from, to):
                let source = Self.normalize(from)
                let destination = Self.normalize(to)
                guard let index = livePaths.firstIndex(of: source) else {
                    throw ArchiveEditorError.missingEntry(source)
                }
                let sourcePrefix = source + "/"
                let destinationPrefix = destination + "/"
                for position in livePaths.indices {
                    if livePaths[position] == source {
                        livePaths[position] = destination
                    } else if livePaths[position].hasPrefix(sourcePrefix) {
                        let suffix = String(livePaths[position].dropFirst(sourcePrefix.count))
                        livePaths[position] = destinationPrefix + suffix
                    }
                }
                for position in output.indices {
                    let current = Self.normalize(nameBytes: output[position].nameBytes, usesUTF8Flag: output[position].usesUTF8)
                    if current == source {
                        output[position] = renamed(output[position], to: destination)
                    } else if current.hasPrefix(sourcePrefix) {
                        let suffix = String(current.dropFirst(sourcePrefix.count))
                        output[position] = renamed(output[position], to: destinationPrefix + suffix)
                    }
                }

            case let .replace(entryPath, sourceURL):
                let target = Self.normalize(entryPath)
                guard livePaths.contains(target),
                      let position = output.firstIndex(where: {
                          Self.normalize(nameBytes: $0.nameBytes, usesUTF8Flag: $0.usesUTF8) == target && !$0.isDirectory
                      })
                else {
                    throw ArchiveEditorError.missingEntry(target)
                }
                let replaced = OutputEntry(
                    nameBytes: output[position].nameBytes,
                    usesUTF8: output[position].usesUTF8,
                    modifiedUnixTime: (try? EditorFileFingerprint(fileURL: sourceURL).modifiedUnixTime)
                        ?? output[position].modifiedUnixTime,
                    isDirectory: false,
                    source: .file(sourceURL)
                )
                output[position] = replaced

            case let .add(sourceURL, destinationPath):
                let destination = Self.normalize(destinationPath)
                let fingerprint = try EditorFileFingerprint(fileURL: sourceURL)
                output.append(OutputEntry(
                    nameBytes: Array(destination.utf8),
                    usesUTF8: true,
                    modifiedUnixTime: fingerprint.modifiedUnixTime,
                    isDirectory: false,
                    source: .file(sourceURL)
                ))
                livePaths.append(destination)
            }
        }

        try detectCollisions(in: output)
        return output
    }

    private func renamed(_ entry: OutputEntry, to normalizedDestination: String) -> OutputEntry {
        let storedName = entry.isDirectory ? normalizedDestination + "/" : normalizedDestination
        return OutputEntry(
            nameBytes: Array(storedName.utf8),
            usesUTF8: true,
            modifiedUnixTime: entry.modifiedUnixTime,
            isDirectory: entry.isDirectory,
            source: entry.source
        )
    }

    private func detectCollisions(in output: [OutputEntry]) throws {
        var seen: [String: String] = [:]
        for entry in output {
            let path = Self.normalize(nameBytes: entry.nameBytes, usesUTF8Flag: entry.usesUTF8)
            let key = path.precomposedStringWithCanonicalMapping
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
            if let existing = seen[key] {
                let ordered = [existing, path].sorted(by: >)
                throw ArchiveEditorError.pathCollision(ordered[0], ordered[1])
            }
            seen[key] = path
        }
    }

    private static func normalize(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private static func normalize(nameBytes: [UInt8], usesUTF8Flag: Bool) -> String {
        var bytes = nameBytes
        if bytes.last == UInt8(ascii: "/") { bytes.removeLast() }
        let detector = EncodingDetector()
        return detector.detect(rawBytes: bytes, usesUTF8Flag: usesUTF8Flag).decodedName
    }

    private func writeOutputEntry(_ entry: OutputEntry, reader: ZIPBridgeReader, writer: EditorWriter) throws {
        try writer.openEntryRaw(
            nameBytes: entry.nameBytes,
            usesUTF8: entry.usesUTF8,
            uncompressedSize: entry.isDirectory ? 0 : uncompressedSize(of: entry),
            modifiedUnixTime: entry.modifiedUnixTime
        )
        switch entry.source {
        case .directory:
            break
        case let .original(ordinal, uncompressedSize):
            try reader.streamEntryChunks(
                ordinal: ordinal,
                expectedSize: uncompressedSize,
                maximumBytes: uncompressedSize
            ) { chunk in
                try writer.writeChunk(chunk)
            }
        case let .file(fileURL):
            try streamFileToWriter(fileURL, writer: writer)
        }
        try writer.closeEntry()
    }

    private func uncompressedSize(of entry: OutputEntry) -> UInt64 {
        switch entry.source {
        case let .original(_, uncompressedSize):
            return uncompressedSize
        case let .file(fileURL):
            return (try? EditorFileFingerprint(fileURL: fileURL).size) ?? 0
        case .directory:
            return 0
        }
    }

    private func streamFileToWriter(_ fileURL: URL, writer: EditorWriter) throws {
        let before = try EditorFileFingerprint(fileURL: fileURL)
        let descriptor = fileURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw ArchiveEditorError.sourceUnreadable(fileURL.lastPathComponent) }
        defer { Darwin.close(descriptor) }

        var hasher = SHA256()
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
                throw ArchiveEditorError.sourceUnreadable(fileURL.lastPathComponent)
            }
            if count == 0 { break }
            let chunk = Data(buffer.prefix(count))
            hasher.update(data: chunk)
            try writer.writeChunk(chunk)
            totalRead += UInt64(count)
            guard totalRead <= before.size else { throw ArchiveError.sourceChanged }
        }
        guard totalRead == before.size, Data(hasher.finalize()) == before.sha256 else {
            throw ArchiveError.sourceChanged
        }
    }

    private func verify(stageURL: URL, plan: [OutputEntry], fileHashesByOrdinal: [UInt64: Data]) throws {
        let reader = try ZIPBridgeReader(url: stageURL)
        let entries = try reader.allEntries(maximumCount: plan.count + 1)
        guard entries.count == plan.count else { throw ArchiveError.sourceChanged }
        for (ordinal, pair) in zip(entries, plan).enumerated() {
            try Task.checkCancellation()
            let (actual, expected) = pair
            guard actual.nameBytes == expected.nameBytes else { throw ArchiveError.sourceChanged }
            guard actual.isDirectory == expected.isDirectory else { throw ArchiveError.sourceChanged }
            guard actual.isSymbolicLink == false else { throw ArchiveError.sourceChanged }
            guard actual.isEncrypted == false else { throw ArchiveError.sourceChanged }
            let expectedSize = expectedUncompressedSize(of: expected)
            guard actual.uncompressedSize == expectedSize else { throw ArchiveError.sourceChanged }
            if let expectedHash = fileHashesByOrdinal[UInt64(ordinal)] {
                let digest = try reader.sha256Entry(
                    ordinal: UInt64(ordinal),
                    expectedSize: actual.uncompressedSize,
                    maximumBytes: actual.uncompressedSize
                )
                guard digest == expectedHash else { throw ArchiveError.sourceChanged }
            }
        }
    }

    private func expectedUncompressedSize(of entry: OutputEntry) -> UInt64 {
        switch entry.source {
        case let .original(_, uncompressedSize):
            return uncompressedSize
        case let .file(fileURL):
            return (try? EditorFileFingerprint(fileURL: fileURL).size) ?? 0
        case .directory:
            return 0
        }
    }
}

/// Thin wrapper around the minizip writer bridge used by the editor.
private final class EditorWriter {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        var opened: OpaquePointer?
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
            return awb_mz_writer_open(path, &opened)
        }
        guard status == AWB_MZ_OK, let opened else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        handle = opened
    }

    deinit {
        if handle != nil { _ = awb_mz_writer_close(&handle) }
    }

    func openEntryRaw(nameBytes: [UInt8], usesUTF8: Bool, uncompressedSize: UInt64, modifiedUnixTime: Int64) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        let status = nameBytes.withUnsafeBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
            return awb_mz_writer_open_entry_raw(
                handle,
                baseAddress,
                UInt16(nameBytes.count),
                usesUTF8 ? 1 : 0,
                uncompressedSize,
                modifiedUnixTime
            )
        }
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
    }

    func writeChunk(_ chunk: Data) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        try chunk.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let count = awb_mz_writer_write_entry(
                    handle,
                    baseAddress.advanced(by: written).assumingMemoryBound(to: UInt8.self),
                    Int32(rawBuffer.count - written)
                )
                guard count > 0 else {
                    throw ZIPProviderErrorMapper.archiveError(for: count)
                }
                written += Int(count)
            }
        }
    }

    func closeEntry() throws {
        guard let handle else { throw ArchiveError.helperFailed }
        let status = awb_mz_writer_close_entry(handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
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

/// Atomic-publish helpers shared by the editing backend.
enum EditorAtomic {
    static func syncFile(at url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw ArchiveEditorError.io(errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ArchiveEditorError.io(errno) }
    }

    static func syncDirectory(at url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { throw ArchiveEditorError.io(errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ArchiveEditorError.io(errno) }
    }

    static func publish(stageURL: URL, targetURL: URL, allowOverwrite: Bool) throws {
        if allowOverwrite {
            let renameResult = stageURL.withUnsafeFileSystemRepresentation { stagePath in
                targetURL.withUnsafeFileSystemRepresentation { targetPath in
                    guard let stagePath, let targetPath else { return Int32(-1) }
                    return Darwin.rename(stagePath, targetPath)
                }
            }
            guard renameResult == 0 else { throw ArchiveEditorError.io(errno) }
            try syncDirectory(at: targetURL.deletingLastPathComponent())
        } else {
            let linkResult = stageURL.withUnsafeFileSystemRepresentation { stagePath in
                targetURL.withUnsafeFileSystemRepresentation { targetPath in
                    guard let stagePath, let targetPath else { return Int32(-1) }
                    return Darwin.link(stagePath, targetPath)
                }
            }
            guard linkResult == 0 else {
                if errno == EEXIST { throw ArchiveEditorError.outputExists }
                throw ArchiveEditorError.io(errno)
            }
            do {
                try FileManager.default.removeItem(at: stageURL)
                try syncDirectory(at: targetURL.deletingLastPathComponent())
            } catch {
                try? FileManager.default.removeItem(at: targetURL)
                throw error
            }
        }
    }
}
