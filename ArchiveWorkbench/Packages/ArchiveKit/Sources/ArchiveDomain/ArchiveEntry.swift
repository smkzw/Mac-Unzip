import Foundation

public struct ArchiveEntryID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct ArchivePathBytes: Hashable, Codable, Sendable {
    public let bytes: [UInt8]
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
}

public struct ArchiveEntry: Hashable, Codable, Sendable {
    public let id: ArchiveEntryID
    public let rawPath: ArchivePathBytes
    public let displayPath: String
    public init(id: ArchiveEntryID, rawPath: ArchivePathBytes, displayPath: String) {
        self.id = id; self.rawPath = rawPath; self.displayPath = displayPath
    }
}
