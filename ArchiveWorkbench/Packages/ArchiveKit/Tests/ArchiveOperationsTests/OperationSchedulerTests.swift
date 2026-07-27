import Foundation
import Testing
@testable import ArchiveOperations

@Suite(.serialized)
struct OperationSchedulerTests {
    @Test func operationSerializationRoundTripsWithoutPrivateInputs() throws {
        let archiveID = ArchiveID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let operation = ArchiveOperation(
            id: ArchiveOperationID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
            kind: .externalRead(archiveID: archiveID),
            state: .queued
        )

        let data = try JSONEncoder().encode(operation)
        let json = String(decoding: data, as: UTF8.self)

        #expect(try JSONDecoder().decode(ArchiveOperation.self, from: data) == operation)
        #expect(!json.localizedCaseInsensitiveContains("password"))
        #expect(!json.contains("/Users/"))
        #expect(!json.contains("file://"))
        #expect(json.lowercased().contains(archiveID.rawValue.uuidString.lowercased()))
        requireArchiveID(operation.kind.archiveID)
    }

    @Test func archiveIdentityCannotDecodeFromRawPathString() {
        let rawPath = Data(#""/Users/example/Private/archive.zip""#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ArchiveID.self, from: rawPath)
        }
    }

    @Test func oneArgumentSubmitQueuesUntilExecutionIsAttached() async {
        let scheduler = OperationScheduler(maxExternalJobs: 2)
        let probe = SchedulerProbe()
        let target = operation(5, .read(archiveID: archive(5)))

        #expect(await scheduler.submit(target) == .accepted)
        #expect(await scheduler.queuedOperationIDs() == [target.id])
        #expect(await scheduler.stateEvents(for: target.id) == [.queued])

        #expect(await scheduler.attachExecution(to: target.id, execution: {
            await probe.started("attached")
        }) { state in
            await probe.completed("attached", state: state)
        } == .attached)

        await probe.waitForStarts(1)
        await probe.waitForCompletions(1)
        #expect(await probe.completionState(for: "attached") == .succeeded)
    }

    @Test func duplicateSubmissionAndBindingReturnDeterministicResults() async {
        let scheduler = OperationScheduler(maxExternalJobs: 2)
        let probe = SchedulerProbe()
        let gate = CancellationAwareGate()
        let active = operation(6, .mutation(archiveID: archive(6)))
        let waiting = operation(7, .mutation(archiveID: archive(6)))

        #expect(await scheduler.submit(active, execution: {
            try await gate.wait()
        }) { state in
            await probe.completed("active", state: state)
        } == .accepted)
        #expect(await scheduler.submit(waiting) == .accepted)
        #expect(await scheduler.submit(waiting) == .duplicateOperation)
        #expect(await scheduler.attachExecution(to: waiting.id, execution: {}) == .attached)
        #expect(await scheduler.attachExecution(to: waiting.id, execution: {}) == .alreadyAttached)
        #expect(await scheduler.attachExecution(to: ArchiveOperationID(), execution: {}) == .unknownOperation)

        await scheduler.cancel(waiting.id)
        await gate.open()
        await probe.waitForCompletions(1)
    }

    @Test func queuedWorkIsFIFOAndMoveToFrontPreservesOtherOrder() async {
        let scheduler = OperationScheduler(maxExternalJobs: 2)
        let probe = SchedulerProbe()
        let blockerGate = CancellationAwareGate()
        let blocker = operation(1, .mutation(archiveID: archive(1)))
        let first = operation(2, .mutation(archiveID: archive(1)))
        let second = operation(3, .mutation(archiveID: archive(1)))
        let promoted = operation(4, .mutation(archiveID: archive(1)))

        await scheduler.submit(blocker, execution: {
            await probe.started("blocker")
            try await blockerGate.wait()
        })
        await probe.waitForStarts(1)
        await scheduler.submit(first, execution: { await probe.started("first") })
        await scheduler.submit(second, execution: { await probe.started("second") })
        await scheduler.submit(promoted, execution: { await probe.started("promoted") })
        await scheduler.moveToFront(promoted.id)

        #expect(await scheduler.queuedOperationIDs() == [promoted.id, first.id, second.id])

        await blockerGate.open()
        await probe.waitForStarts(4)
        #expect(await probe.startOrder == ["blocker", "promoted", "first", "second"])
    }

    @Test func cancelingQueuedOperationNeverStartsIt() async {
        let scheduler = OperationScheduler(maxExternalJobs: 2)
        let probe = SchedulerProbe()
        let gate = CancellationAwareGate()
        let blocker = operation(10, .mutation(archiveID: archive(10)))
        let canceled = operation(11, .mutation(archiveID: archive(10)))

        await scheduler.submit(blocker, execution: {
            await probe.started("blocker")
            try await gate.wait()
        })
        await probe.waitForStarts(1)
        await scheduler.submit(canceled, execution: { await probe.started("canceled") }) { state in
            await probe.completed("canceled", state: state)
        }
        await scheduler.cancel(canceled.id)
        await probe.waitForCompletions(1)
        await gate.open()

        #expect(await probe.startOrder == ["blocker"])
        #expect(await probe.completionCount(for: "canceled") == 1)
        #expect(await scheduler.stateEvents(for: canceled.id) == [.queued, .canceled])
    }

    @Test func externalConcurrencyIsCappedAtTwoAndCapacityIsRestored() async {
        let scheduler = OperationScheduler(maxExternalJobs: 2)
        let probe = SchedulerProbe()
        let gates = (0..<4).map { _ in CancellationAwareGate() }

        for index in 0..<4 {
            await scheduler.submit(operation(20 + index, .externalRead(archiveID: archive(20 + index))), execution: {
                await probe.enterExternal(index)
                try await gates[index].wait()
                await probe.leaveExternal()
            }) { state in
                await probe.completed("external-\(index)", state: state)
            }
        }

        await probe.waitForStarts(2)
        #expect(await probe.maximumExternal == 2)
        #expect(await probe.currentExternal == 2)

        await gates[0].open()
        await gates[1].open()
        await probe.waitForStarts(4)
        #expect(await probe.maximumExternal == 2)

        await gates[2].open()
        await gates[3].open()
        await probe.waitForCompletions(4)
        #expect(await probe.currentExternal == 0)
    }

    @Test func mutationsForSameArchiveAreMutuallyExclusive() async {
        let scheduler = OperationScheduler(maxExternalJobs: 2)
        let probe = SchedulerProbe()
        let firstGate = CancellationAwareGate()
        let secondGate = CancellationAwareGate()

        await scheduler.submit(operation(30, .mutation(archiveID: archive(30))), execution: {
            await probe.enterMutation("A", label: "A1")
            try await firstGate.wait()
            await probe.leaveMutation("A")
        }) { state in
            await probe.completed("A1", state: state)
        }
        await scheduler.submit(operation(31, .mutation(archiveID: archive(30))), execution: {
            await probe.enterMutation("A", label: "A2")
            try await secondGate.wait()
            await probe.leaveMutation("A")
        }) { state in
            await probe.completed("A2", state: state)
        }

        await probe.waitForStarts(1)
        #expect(await probe.maximumMutations(for: "A") == 1)
        await firstGate.open()
        await probe.waitForStarts(2)
        #expect(await probe.maximumMutations(for: "A") == 1)
        await secondGate.open()
        await probe.waitForCompletions(2)
    }

    @Test func mutationsForDifferentArchivesCanOverlap() async {
        let scheduler = OperationScheduler(maxExternalJobs: 1)
        let probe = SchedulerProbe()
        let gateA = CancellationAwareGate()
        let gateB = CancellationAwareGate()

        await scheduler.submit(operation(40, .mutation(archiveID: archive(40))), execution: {
            await probe.enterMutation("A", label: "A")
            try await gateA.wait()
            await probe.leaveMutation("A")
        }) { state in
            await probe.completed("A", state: state)
        }
        await scheduler.submit(operation(41, .mutation(archiveID: archive(41))), execution: {
            await probe.enterMutation("B", label: "B")
            try await gateB.wait()
            await probe.leaveMutation("B")
        }) { state in
            await probe.completed("B", state: state)
        }

        await probe.waitForStarts(2)
        #expect(await probe.maximumTotalMutations == 2)
        await gateA.open()
        await gateB.open()
        await probe.waitForCompletions(2)
    }

    @Test func runningCancellationHasOrderedStatesAndOneCompletion() async {
        let scheduler = OperationScheduler(maxExternalJobs: 1)
        let probe = SchedulerProbe()
        let gate = CancellationAwareGate()
        let target = operation(50, .externalRead(archiveID: archive(50)))

        await scheduler.submit(target, execution: {
            await probe.started("running")
            try await gate.wait()
        }) { state in
            await probe.completed("running", state: state)
        }
        await probe.waitForStarts(1)
        await scheduler.cancel(target.id)
        await probe.waitForCompletions(1)

        #expect(Array(await scheduler.stateEvents(for: target.id).dropFirst()) == [.running, .canceling, .canceled])
        #expect(await probe.completionCount(for: "running") == 1)
        #expect(await probe.completionState(for: "running") == .canceled)
    }

    @Test func concurrentRepeatedCancellationIsIdempotent() async {
        let scheduler = OperationScheduler(maxExternalJobs: 1)
        let probe = SchedulerProbe()
        let gate = CancellationAwareGate()
        let target = operation(55, .externalRead(archiveID: archive(55)))

        await scheduler.submit(target, execution: {
            await probe.started("repeated-cancel")
            try await gate.wait()
        }) { state in
            await probe.completed("repeated-cancel", state: state)
        }
        await probe.waitForStarts(1)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask { await scheduler.cancel(target.id) }
            }
        }
        await probe.waitForCompletions(1)

        let events = await scheduler.stateEvents(for: target.id)
        #expect(events.filter { $0 == .canceling }.count == 1)
        #expect(events.filter { $0 == .canceled }.count == 1)
        #expect(await probe.completionCount(for: "repeated-cancel") == 1)
    }

    @Test func cancelRacingNaturalFinishAlwaysHasOneConsistentTerminalState() async {
        for iteration in 0..<25 {
            let scheduler = OperationScheduler(maxExternalJobs: 1)
            let probe = SchedulerProbe()
            let gate = CancellationAwareGate()
            let label = "race-\(iteration)"
            let target = operation(100 + iteration, .externalRead(archiveID: archive(100 + iteration)))

            await scheduler.submit(target, execution: {
                await probe.started(label)
                try await gate.wait()
            }) { state in
                await probe.completed(label, state: state)
            }
            await probe.waitForStarts(1)

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await scheduler.cancel(target.id) }
                group.addTask { await gate.open() }
            }
            await probe.waitForCompletions(1)

            let events = await scheduler.stateEvents(for: target.id)
            let completion = await probe.completionState(for: label)
            #expect(completion == .succeeded || completion == .canceled)
            #expect(events.last == completion)
            #expect(events.filter { $0 == .succeeded || $0 == .canceled }.count == 1)
            #expect(await probe.completionCount(for: label) == 1)
        }
    }

    @Test func thrownAndCanceledExternalWorkReleasePermits() async {
        let scheduler = OperationScheduler(maxExternalJobs: 1)
        let probe = SchedulerProbe()
        let cancelGate = CancellationAwareGate()
        let thrown = operation(60, .externalRead(archiveID: archive(60)))
        let canceled = operation(61, .externalRead(archiveID: archive(61)))
        let successor = operation(62, .externalRead(archiveID: archive(62)))

        await scheduler.submit(thrown, execution: {
            await probe.started("thrown")
            throw TestFailure.expected
        }) { state in
            await probe.completed("thrown", state: state)
        }
        await scheduler.submit(canceled, execution: {
            await probe.started("cancel")
            try await cancelGate.wait()
        }) { state in
            await probe.completed("cancel", state: state)
        }
        await scheduler.submit(successor, execution: {
            await probe.started("successor")
        }) { state in
            await probe.completed("successor", state: state)
        }

        await probe.waitForStarts(2)
        #expect(await probe.completionState(for: "thrown") == .failed)
        await scheduler.cancel(canceled.id)
        await probe.waitForStarts(3)
        await probe.waitForCompletions(3)

        #expect(await probe.startOrder == ["thrown", "cancel", "successor"])
        #expect(await probe.completionState(for: "cancel") == .canceled)
        #expect(await probe.completionState(for: "successor") == .succeeded)
    }

    @Test func canceledBlockedWaiterDoesNotDeadlockUnrelatedWork() async {
        let scheduler = OperationScheduler(maxExternalJobs: 1)
        let probe = SchedulerProbe()
        let activeGate = CancellationAwareGate()
        let active = operation(70, .externalRead(archiveID: archive(70)))
        let blocked = operation(71, .externalRead(archiveID: archive(71)))
        let successor = operation(72, .externalRead(archiveID: archive(72)))

        await scheduler.submit(active, execution: {
            await probe.started("active")
            try await activeGate.wait()
        })
        await probe.waitForStarts(1)
        await scheduler.submit(blocked, execution: {
            await probe.started("blocked")
        })
        await scheduler.submit(successor, execution: {
            await probe.started("successor")
        }) { state in
            await probe.completed("successor", state: state)
        }
        await scheduler.cancel(blocked.id)
        await activeGate.open()
        await probe.waitForStarts(2)
        await probe.waitForCompletions(1)

        #expect(await probe.startOrder == ["active", "successor"])
        #expect(await scheduler.stateEvents(for: blocked.id) == [.queued, .canceled])
    }

    private func operation(_ suffix: Int, _ kind: ArchiveOperationKind) -> ArchiveOperation {
        let raw = String(format: "00000000-0000-0000-0000-%012d", suffix)
        return ArchiveOperation(
            id: ArchiveOperationID(UUID(uuidString: raw)!),
            kind: kind,
            state: .queued
        )
    }

    private func archive(_ suffix: Int) -> ArchiveID {
        let raw = String(format: "10000000-0000-0000-0000-%012d", suffix)
        return ArchiveID(UUID(uuidString: raw)!)
    }
}

private func requireArchiveID(_ archiveID: ArchiveID) {
    _ = archiveID.rawValue
}

private enum TestFailure: Error {
    case expected
}

private actor CancellationAwareGate {
    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if isOpen {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

private actor SchedulerProbe {
    private(set) var startOrder: [String] = []
    private(set) var currentExternal = 0
    private(set) var maximumExternal = 0
    private var currentMutations: [String: Int] = [:]
    private var maximumMutationCounts: [String: Int] = [:]
    private var currentTotalMutations = 0
    private(set) var maximumTotalMutations = 0
    private var completions: [String: [ArchiveOperationState]] = [:]
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var completionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func started(_ label: String) {
        startOrder.append(label)
        resumeSatisfiedStartWaiters()
    }

    func enterExternal(_ index: Int) {
        currentExternal += 1
        maximumExternal = max(maximumExternal, currentExternal)
        started("external-\(index)")
    }

    func leaveExternal() {
        currentExternal -= 1
    }

    func enterMutation(_ archiveID: String, label: String) {
        currentMutations[archiveID, default: 0] += 1
        maximumMutationCounts[archiveID] = max(
            maximumMutationCounts[archiveID, default: 0],
            currentMutations[archiveID, default: 0]
        )
        currentTotalMutations += 1
        maximumTotalMutations = max(maximumTotalMutations, currentTotalMutations)
        started(label)
    }

    func leaveMutation(_ archiveID: String) {
        currentMutations[archiveID, default: 0] -= 1
        currentTotalMutations -= 1
    }

    func maximumMutations(for archiveID: String) -> Int {
        maximumMutationCounts[archiveID, default: 0]
    }

    func completed(_ label: String, state: ArchiveOperationState) {
        completions[label, default: []].append(state)
        resumeSatisfiedCompletionWaiters()
    }

    func completionCount(for label: String) -> Int {
        completions[label, default: []].count
    }

    func completionState(for label: String) -> ArchiveOperationState? {
        completions[label]?.last
    }

    func waitForStarts(_ count: Int) async {
        guard startOrder.count < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func waitForCompletions(_ count: Int) async {
        let currentCount = completions.values.reduce(0) { $0 + $1.count }
        guard currentCount < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append((count, continuation))
        }
    }

    private func resumeSatisfiedStartWaiters() {
        let ready = startWaiters.filter { startOrder.count >= $0.0 }
        startWaiters.removeAll { startOrder.count >= $0.0 }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    private func resumeSatisfiedCompletionWaiters() {
        let count = completions.values.reduce(0) { $0 + $1.count }
        let ready = completionWaiters.filter { count >= $0.0 }
        completionWaiters.removeAll { count >= $0.0 }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }
}
