public enum ArchiveAction: String, Codable, Hashable, Sendable {
    case list, read, preview, create, update, encrypt, split, test, repair
}

public enum ProviderID: String, Codable, Hashable, Sendable {
    case minizipNG, libarchive, sevenZZ, rarLab, diskImage
}

public enum CapabilityUnavailableReason: String, Codable, Hashable, Sendable {
    case formatReadOnly, externalProviderNotValidated, unsupportedByProvider, notYetImplemented
}

public struct ArchiveCapabilitySnapshot: Equatable, Sendable {
    public let actions: Set<ArchiveAction>
    public let primaryProvider: ProviderID?
    public let unavailableReasons: [ArchiveAction: CapabilityUnavailableReason]

    public init(
        actions: Set<ArchiveAction>,
        primaryProvider: ProviderID?,
        unavailableReasons: [ArchiveAction: CapabilityUnavailableReason]
    ) {
        self.actions = actions
        self.primaryProvider = primaryProvider
        self.unavailableReasons = unavailableReasons
    }
}
