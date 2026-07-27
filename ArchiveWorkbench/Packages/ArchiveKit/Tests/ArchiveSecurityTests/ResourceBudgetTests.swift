import Testing
@testable import ArchiveSecurity

@Test
func previewDefaultsMatchTheContract() {
    let budget = ResourceBudget.previewDefault

    #expect(budget.maxExpandedBytes == 256 << 20)
    #expect(budget.maxEntries == 1)
    #expect(budget.maxDepth == 1)
    #expect(budget.maxRatio == 50)
    #expect(!budget.overrideAllowed)
}

@Test
func extractionDefaultsMatchTheContract() {
    let budget = ResourceBudget.extractionDefault

    #expect(budget.maxExpandedBytes == 50 << 30)
    #expect(budget.maxEntries == 1_000_000)
    #expect(budget.maxDepth == 128)
    #expect(budget.maxRatio == 100)
    #expect(budget.overrideAllowed)
}

@Test(arguments: [
    ResourceEstimate(compressedBytes: 256 << 20, expandedBytes: 256 << 20, entries: 1, depth: 1),
    ResourceEstimate(compressedBytes: 1, expandedBytes: 50, entries: 1, depth: 1),
    ResourceEstimate(compressedBytes: 0, expandedBytes: 0, entries: 1, depth: 1),
])
func previewAllowsValuesAtItsLimits(_ estimate: ResourceEstimate) {
    #expect(ResourceBudget.previewDefault.evaluate(estimate) == .allow)
}

@Test(arguments: [
    (ResourceEstimate(compressedBytes: 256 << 20, expandedBytes: (256 << 20) + 1, entries: 1, depth: 1), BudgetReason.totalBytes),
    (ResourceEstimate(compressedBytes: 1, expandedBytes: 1, entries: 2, depth: 1), BudgetReason.entryCount),
    (ResourceEstimate(compressedBytes: 1, expandedBytes: 1, entries: 1, depth: 2), BudgetReason.depth),
    (ResourceEstimate(compressedBytes: 2, expandedBytes: 101, entries: 1, depth: 1), BudgetReason.compressionRatio),
    (ResourceEstimate(compressedBytes: 0, expandedBytes: 1, entries: 1, depth: 1), BudgetReason.compressionRatio),
])
func previewViolationsAreNonOverrideable(_ estimate: ResourceEstimate, _ reason: BudgetReason) {
    #expect(ResourceBudget.previewDefault.evaluate(estimate) == .blockNonOverrideable(reason))
}

@Test(arguments: [
    ResourceEstimate(compressedBytes: 50 << 30, expandedBytes: 50 << 30, entries: 1_000_000, depth: 128),
    ResourceEstimate(compressedBytes: 1, expandedBytes: 100, entries: 1, depth: 1),
    ResourceEstimate(compressedBytes: 0, expandedBytes: 0, entries: 0, depth: 0),
])
func extractionAllowsValuesAtItsLimits(_ estimate: ResourceEstimate) {
    #expect(ResourceBudget.extractionDefault.evaluate(estimate) == .allow)
}

@Test(arguments: [
    (ResourceEstimate(compressedBytes: 50 << 30, expandedBytes: (50 << 30) + 1, entries: 1, depth: 1), BudgetReason.totalBytes),
    (ResourceEstimate(compressedBytes: 1, expandedBytes: 1, entries: 1_000_001, depth: 1), BudgetReason.entryCount),
    (ResourceEstimate(compressedBytes: 1, expandedBytes: 1, entries: 1, depth: 129), BudgetReason.depth),
    (ResourceEstimate(compressedBytes: 1_000_000, expandedBytes: 100_000_001, entries: 1, depth: 1), BudgetReason.compressionRatio),
    (ResourceEstimate(compressedBytes: 0, expandedBytes: 1, entries: 1, depth: 1), BudgetReason.compressionRatio),
])
func extractionViolationsAreOverrideable(_ estimate: ResourceEstimate, _ reason: BudgetReason) {
    #expect(ResourceBudget.extractionDefault.evaluate(estimate) == .blockOverrideable(reason))
}

@Test
func ratioEvaluationDoesNotOverflowAtUInt64Boundary() {
    let budget = ResourceBudget(
        maxExpandedBytes: .max,
        maxEntries: .max,
        maxDepth: .max,
        maxRatio: 1,
        overrideAllowed: false
    )

    #expect(budget.evaluate(.init(
        compressedBytes: .max,
        expandedBytes: .max,
        entries: 1,
        depth: 1
    )) == .allow)
}
