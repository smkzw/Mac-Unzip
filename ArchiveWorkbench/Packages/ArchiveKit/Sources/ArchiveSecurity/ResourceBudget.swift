public struct ResourceEstimate: Equatable, Sendable {
    public let compressedBytes: UInt64
    public let expandedBytes: UInt64
    public let entries: UInt64
    public let depth: UInt64

    public init(compressedBytes: UInt64, expandedBytes: UInt64, entries: UInt64, depth: UInt64) {
        self.compressedBytes = compressedBytes
        self.expandedBytes = expandedBytes
        self.entries = entries
        self.depth = depth
    }
}

public enum BudgetReason: Equatable, Sendable {
    case itemBytes
    case totalBytes
    case entryCount
    case depth
    case compressionRatio
}

public enum BudgetDecision: Equatable, Sendable {
    case allow
    case blockOverrideable(BudgetReason)
    case blockNonOverrideable(BudgetReason)
}

public struct ResourceBudget: Sendable {
    public let maxExpandedBytes: UInt64
    public let maxEntries: UInt64
    public let maxDepth: UInt64
    public let maxRatio: UInt64
    public let overrideAllowed: Bool

    public static let previewDefault = Self(
        maxExpandedBytes: 256 << 20,
        maxEntries: 1,
        maxDepth: 1,
        maxRatio: 50,
        overrideAllowed: false
    )

    public static let extractionDefault = Self(
        maxExpandedBytes: 50 << 30,
        maxEntries: 1_000_000,
        maxDepth: 128,
        maxRatio: 100,
        overrideAllowed: true
    )

    public init(
        maxExpandedBytes: UInt64,
        maxEntries: UInt64,
        maxDepth: UInt64,
        maxRatio: UInt64,
        overrideAllowed: Bool
    ) {
        self.maxExpandedBytes = maxExpandedBytes
        self.maxEntries = maxEntries
        self.maxDepth = maxDepth
        self.maxRatio = maxRatio
        self.overrideAllowed = overrideAllowed
    }

    public func evaluate(_ estimate: ResourceEstimate) -> BudgetDecision {
        let reason: BudgetReason?
        if estimate.expandedBytes > maxExpandedBytes {
            reason = .totalBytes
        } else if estimate.entries > maxEntries {
            reason = .entryCount
        } else if estimate.depth > maxDepth {
            reason = .depth
        } else if exceedsRatio(estimate) {
            reason = .compressionRatio
        } else {
            reason = nil
        }

        guard let reason else { return .allow }
        return overrideAllowed ? .blockOverrideable(reason) : .blockNonOverrideable(reason)
    }

    private func exceedsRatio(_ estimate: ResourceEstimate) -> Bool {
        guard estimate.compressedBytes != 0 else {
            return estimate.expandedBytes != 0
        }

        let quotient = estimate.expandedBytes / estimate.compressedBytes
        let remainder = estimate.expandedBytes % estimate.compressedBytes
        return quotient > maxRatio || (quotient == maxRatio && remainder != 0)
    }
}
