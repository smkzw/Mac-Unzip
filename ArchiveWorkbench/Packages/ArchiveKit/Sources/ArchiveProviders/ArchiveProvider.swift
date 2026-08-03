import ArchiveDomain
import Foundation

public struct ArchiveEntrySnapshot: Equatable, Sendable {
    public let entry: ArchiveEntry
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let modifiedAt: Date?
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let isEncrypted: Bool
    public let usesUTF8FileName: Bool
    /// True when the entry name had no UTF-8 flag and was auto-repaired from a
    /// legacy CJK encoding (GBK/Shift-JIS/EUC-KR) by the detector. Surfaced in
    /// the UI so the auto-fix selling point is visible.
    public let legacyEncodingRepaired: Bool

    public init(
        entry: ArchiveEntry,
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        modifiedAt: Date?,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        isEncrypted: Bool,
        usesUTF8FileName: Bool,
        legacyEncodingRepaired: Bool = false
    ) {
        self.entry = entry
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.isEncrypted = isEncrypted
        self.usesUTF8FileName = usesUTF8FileName
        self.legacyEncodingRepaired = legacyEncodingRepaired
    }
}

public struct ArchiveDocumentSnapshot: Equatable, Sendable {
    public let sourceURL: URL
    public let format: ArchiveFormat
    public let entries: [ArchiveEntrySnapshot]

    public init(sourceURL: URL, format: ArchiveFormat, entries: [ArchiveEntrySnapshot]) {
        self.sourceURL = sourceURL
        self.format = format
        self.entries = entries
    }
}

public protocol ArchiveProvider: Actor {
    func open(url: URL) throws -> ArchiveDocumentSnapshot
    func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data
}
