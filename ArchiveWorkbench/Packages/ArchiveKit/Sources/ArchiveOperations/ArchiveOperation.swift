import Foundation

public struct ArchiveOperationID: Hashable, Codable, Equatable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// Opaque identity for an archive document. Filesystem locations and display names live outside
/// the serializable operation contract.
public struct ArchiveID: Hashable, Codable, Equatable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum ArchiveOperationKind: Codable, Equatable, Sendable {
    case read(archiveID: ArchiveID)
    case externalRead(archiveID: ArchiveID)
    case mutation(archiveID: ArchiveID)

    public var archiveID: ArchiveID {
        switch self {
        case let .read(archiveID), let .externalRead(archiveID), let .mutation(archiveID):
            archiveID
        }
    }
}

public enum ArchiveOperationState: String, Codable, Equatable, Sendable {
    case queued
    case waitingForSave
    case running
    case canceling
    case canceled
    case succeeded
    case failed
}

public struct ArchiveOperation: Codable, Equatable, Sendable {
    public let id: ArchiveOperationID
    public let kind: ArchiveOperationKind
    public var state: ArchiveOperationState

    public init(
        id: ArchiveOperationID = ArchiveOperationID(),
        kind: ArchiveOperationKind,
        state: ArchiveOperationState = .queued
    ) {
        self.id = id
        self.kind = kind
        self.state = state
    }
}
