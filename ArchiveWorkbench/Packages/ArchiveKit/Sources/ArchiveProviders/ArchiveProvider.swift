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

    public init(
        entry: ArchiveEntry,
        compressedSize: UInt64,
        uncompressedSize: UInt64,
        modifiedAt: Date?,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        isEncrypted: Bool,
        usesUTF8FileName: Bool
    ) {
        self.entry = entry
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.modifiedAt = modifiedAt
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.isEncrypted = isEncrypted
        self.usesUTF8FileName = usesUTF8FileName
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
