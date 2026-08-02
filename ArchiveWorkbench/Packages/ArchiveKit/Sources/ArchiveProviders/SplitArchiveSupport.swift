import ArchiveDomain
import CMinizipBridge
import Foundation

// MARK: - Split ZIP Writer

/// Result of a split archive creation operation.
public struct SplitArchiveResult: Equatable, Sendable {
    /// URLs of all created volume files, in order (.z01, .z02, ..., .zip).
    public let volumeURLs: [URL]
    /// Total bytes written across all volumes.
    public let totalBytes: UInt64

    public var volumeCount: Int { volumeURLs.count }

    public init(volumeURLs: [URL], totalBytes: UInt64) {
        self.volumeURLs = volumeURLs
        self.totalBytes = totalBytes
    }
}

/// Creates split (multipart) ZIP archives using minizip-ng's disk spanning.
///
/// Design principle from handoff:
/// "multipart 永远另存为完整集合，不虚假承诺原子就地覆盖"
/// Split archives are always written as a complete new set; we never attempt
/// to update individual volumes in place.
public final class SplitZIPWriter {
    private var handle: OpaquePointer?
    private let outputURL: URL
    private let diskSize: UInt64

    /// Creates a split ZIP writer.
    /// - Parameters:
    ///   - url: Output path ending in .zip. Volumes will be named .z01, .z02, etc.
    ///   - volumeSize: Maximum bytes per volume. Must be >= SplitVolumeSize.minimumBytes.
    public init(url: URL, volumeSize: SplitVolumeSize) throws {
        guard let bytes = volumeSize.byteSize, bytes >= SplitVolumeSize.minimumBytes else {
            throw ArchiveError.resourceLimit
        }
        self.outputURL = url
        self.diskSize = bytes

        var opened: OpaquePointer?
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
            return awb_mz_writer_open_split(path, bytes, &opened)
        }
        guard status == AWB_MZ_OK, let opened else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
        handle = opened
    }

    deinit {
        if handle != nil { _ = awb_mz_writer_close(&handle) }
    }

    /// Opens a new entry in the archive for writing.
    public func openEntry(name: String, uncompressedSize: UInt64, modifiedUnixTime: Int64) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        let status = awb_mz_writer_open_entry(handle, name, uncompressedSize, modifiedUnixTime)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
    }

    /// Opens a new entry with raw name bytes (preserves original encoding).
    public func openEntryRaw(nameBytes: [UInt8], usesUTF8: Bool, uncompressedSize: UInt64, modifiedUnixTime: Int64) throws {
        guard let handle else { throw ArchiveError.helperFailed }
        guard let nameLength = UInt16(exactly: nameBytes.count) else { throw ArchiveError.helperFailed }
        let status = nameBytes.withUnsafeBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return Int32(AWB_MZ_INVALID_ARGUMENT) }
            return awb_mz_writer_open_entry_raw(
                handle,
                baseAddress,
                nameLength,
                usesUTF8 ? 1 : 0,
                uncompressedSize,
                modifiedUnixTime
            )
        }
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
    }

    /// Writes a chunk of data to the currently open entry.
    public func writeChunk(_ chunk: Data) throws {
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

    /// Closes the currently open entry.
    public func closeEntry() throws {
        guard let handle else { throw ArchiveError.helperFailed }
        let status = awb_mz_writer_close_entry(handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }
    }

    /// Finishes writing and closes the archive. Returns the set of created volume files.
    ///
    /// "multipart 永远另存为完整集合" — this always produces a complete set.
    @discardableResult
    public func finish() throws -> SplitArchiveResult {
        guard handle != nil else { throw ArchiveError.helperFailed }
        let status = awb_mz_writer_close(&handle)
        guard status == AWB_MZ_OK else {
            throw ZIPProviderErrorMapper.archiveError(for: status)
        }

        // Enumerate created volumes: .z01, .z02, ..., .zip
        let volumes = Self.enumerateVolumes(forFinalSegment: outputURL)
        var totalBytes: UInt64 = 0
        for volume in volumes {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: volume.path),
               let size = attrs[.size] as? UInt64 {
                totalBytes += size
            }
        }
        return SplitArchiveResult(volumeURLs: volumes, totalBytes: totalBytes)
    }

    /// Enumerates all volume files for a split archive given the final .zip segment.
    public static func enumerateVolumes(forFinalSegment finalURL: URL) -> [URL] {
        let directory = finalURL.deletingLastPathComponent()
        let baseName = finalURL.deletingPathExtension().lastPathComponent
        var volumes: [URL] = []

        // Collect .z01, .z02, ... in order
        var index = 1
        while true {
            let volumeName = String(format: "%@.z%02d", baseName, index)
            let volumeURL = directory.appendingPathComponent(volumeName)
            guard FileManager.default.fileExists(atPath: volumeURL.path) else { break }
            volumes.append(volumeURL)
            index += 1
        }

        // The final .zip segment
        if FileManager.default.fileExists(atPath: finalURL.path) {
            volumes.append(finalURL)
        }

        return volumes
    }
}

// MARK: - Split Archive Errors

/// Errors specific to split (multipart) archive operations.
public enum SplitArchiveError: Error, Equatable, Sendable {
    /// One or more volumes in the set are missing.
    case missingVolumes(names: [String], message: String)
    /// A volume's data is corrupted (CRC mismatch, truncated).
    case corruptedVolume(name: String)
    /// The volume size is too small or invalid.
    case invalidVolumeSize(requested: UInt64, minimum: UInt64)

    /// Maps to the domain ArchiveError for unified error handling.
    public var archiveError: ArchiveError {
        switch self {
        case .missingVolumes: return .missingVolume
        case .corruptedVolume: return .corruptedArchive
        case .invalidVolumeSize: return .resourceLimit
        }
    }
}

// MARK: - Save As for Split Archives

/// Handles "Save As" for split archives, always producing a complete new set.
///
/// Design principle: "multipart 永远另存为完整集合，不虚假承诺原子就地覆盖"
/// We never try to update individual volumes in place. Save As creates a
/// complete new set of volumes at the target location.
struct SplitArchiveSaveAs {
    init() {}

    /// Saves a split archive to a new location as a complete volume set.
    /// - Parameters:
    ///   - sourceReader: An open reader for the source archive.
    ///   - targetURL: The target .zip path for the new set.
    ///   - volumeSize: The volume size for the new set.
    ///   - entries: The entries to write (from the source archive).
    /// - Returns: Result with all created volume URLs.
    func saveCompleteSet(
        sourceReader: ZIPBridgeReader,
        targetURL: URL,
        volumeSize: SplitVolumeSize,
        entries: [(nameBytes: [UInt8], usesUTF8: Bool, uncompressedSize: UInt64, modifiedUnixTime: Int64, isDirectory: Bool, ordinal: UInt64)]
    ) throws -> SplitArchiveResult {
        let writer = try SplitZIPWriter(url: targetURL, volumeSize: volumeSize)

        for entry in entries {
            try Task.checkCancellation()
            try writer.openEntryRaw(
                nameBytes: entry.nameBytes,
                usesUTF8: entry.usesUTF8,
                uncompressedSize: entry.isDirectory ? 0 : entry.uncompressedSize,
                modifiedUnixTime: entry.modifiedUnixTime
            )
            if !entry.isDirectory {
                try sourceReader.streamEntryChunks(
                    ordinal: entry.ordinal,
                    expectedSize: entry.uncompressedSize,
                    maximumBytes: entry.uncompressedSize
                ) { chunk in
                    try writer.writeChunk(chunk)
                }
            }
            try writer.closeEntry()
        }

        return try writer.finish()
    }
}
