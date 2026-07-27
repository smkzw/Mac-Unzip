public actor OperationScheduler {
    public typealias Execution = @Sendable () async throws -> Void
    public typealias Completion = @Sendable (ArchiveOperationState) async -> Void

    private struct RuntimeJob: Sendable {
        let execution: Execution
        let completion: Completion
    }

    public enum SubmissionResult: Equatable, Sendable {
        case accepted
        case duplicateOperation
    }

    public enum ExecutionAttachmentResult: Equatable, Sendable {
        case attached
        case unknownOperation
        case alreadyAttached
        case operationNotQueued
    }

    private let maxExternalJobs: Int
    private var runningExternalJobs = 0
    private var mutatingArchiveIDs: Set<ArchiveID> = []
    private var queue: [ArchiveOperationID] = []
    private var operations: [ArchiveOperationID: ArchiveOperation] = [:]
    private var events: [ArchiveOperationID: [ArchiveOperationState]] = [:]
    private var jobs: [ArchiveOperationID: RuntimeJob] = [:]
    private var runningTasks: [ArchiveOperationID: Task<Void, Never>] = [:]

    public init(maxExternalJobs: Int = 2) {
        precondition((1...2).contains(maxExternalJobs), "maxExternalJobs must be in 1...2")
        self.maxExternalJobs = maxExternalJobs
    }

    /// Registers serializable queued state without attaching executable runtime behavior.
    @discardableResult
    public func submit(_ operation: ArchiveOperation) -> SubmissionResult {
        guard operations[operation.id] == nil else { return .duplicateOperation }

        var queuedOperation = operation
        queuedOperation.state = .queued
        operations[operation.id] = queuedOperation
        events[operation.id] = [.queued]
        queue.append(operation.id)
        return .accepted
    }

    /// Attaches ephemeral executable work to an already registered queued operation.
    ///
    /// The closures are runtime-only and are removed when the operation reaches a terminal state.
    /// Execution receives structured task cancellation and must leave suspension points cooperatively;
    /// permits remain held until it actually returns or throws.
    @discardableResult
    public func attachExecution(
        to id: ArchiveOperationID,
        execution: @escaping Execution,
        completion: @escaping Completion = { _ in }
    ) -> ExecutionAttachmentResult {
        guard let operation = operations[id] else { return .unknownOperation }
        guard operation.state == .queued else { return .operationNotQueued }
        guard jobs[id] == nil else { return .alreadyAttached }

        jobs[id] = RuntimeJob(execution: execution, completion: completion)
        scheduleEligibleOperations()
        return .attached
    }

    /// Convenience for registering state and binding runtime execution as one actor-isolated action.
    @discardableResult
    public func submit(
        _ operation: ArchiveOperation,
        execution: @escaping Execution,
        completion: @escaping Completion = { _ in }
    ) -> SubmissionResult {
        let result = submit(operation)
        guard result == .accepted else { return result }
        let attachment = attachExecution(to: operation.id, execution: execution, completion: completion)
        precondition(attachment == .attached)
        return .accepted
    }

    public func cancel(_ id: ArchiveOperationID) async {
        guard let operation = operations[id] else { return }

        switch operation.state {
        case .queued, .waitingForSave:
            queue.removeAll { $0 == id }
            transition(id, to: .canceled)
            let completion = jobs.removeValue(forKey: id)?.completion
            scheduleEligibleOperations()
            await completion?(.canceled)
        case .running:
            transition(id, to: .canceling)
            runningTasks[id]?.cancel()
        case .canceling, .canceled, .succeeded, .failed:
            return
        }
    }

    public func moveToFront(_ id: ArchiveOperationID) {
        guard operations[id]?.state == .queued,
              let index = queue.firstIndex(of: id),
              index != queue.startIndex
        else {
            return
        }

        queue.insert(queue.remove(at: index), at: queue.startIndex)
        scheduleEligibleOperations()
    }

    public func operation(for id: ArchiveOperationID) -> ArchiveOperation? {
        operations[id]
    }

    public func stateEvents(for id: ArchiveOperationID) -> [ArchiveOperationState] {
        events[id, default: []]
    }

    public func queuedOperationIDs() -> [ArchiveOperationID] {
        queue
    }

    private func scheduleEligibleOperations() {
        while let index = queue.firstIndex(where: isEligible) {
            let id = queue.remove(at: index)
            start(id)
        }
    }

    private func isEligible(_ id: ArchiveOperationID) -> Bool {
        guard let operation = operations[id], operation.state == .queued, jobs[id] != nil else {
            return false
        }

        switch operation.kind {
        case .read:
            return true
        case .externalRead:
            return runningExternalJobs < maxExternalJobs
        case let .mutation(archiveID):
            return !mutatingArchiveIDs.contains(archiveID)
        }
    }

    private func start(_ id: ArchiveOperationID) {
        guard let operation = operations[id], let job = jobs[id] else { return }

        acquirePermit(for: operation.kind)
        transition(id, to: .running)

        let task = Task {
            do {
                try Task.checkCancellation()
                try await job.execution()
                await self.finish(id, proposedState: .succeeded)
            } catch is CancellationError {
                await self.finish(id, proposedState: .canceled)
            } catch {
                await self.finish(id, proposedState: .failed)
            }
        }
        runningTasks[id] = task
    }

    private func finish(_ id: ArchiveOperationID, proposedState: ArchiveOperationState) async {
        guard let operation = operations[id], operation.state == .running || operation.state == .canceling else {
            return
        }

        releasePermit(for: operation.kind)
        runningTasks.removeValue(forKey: id)
        let completion = jobs.removeValue(forKey: id)?.completion
        let terminalState: ArchiveOperationState = operation.state == .canceling ? .canceled : proposedState
        transition(id, to: terminalState)
        scheduleEligibleOperations()
        await completion?(terminalState)
    }

    private func acquirePermit(for kind: ArchiveOperationKind) {
        switch kind {
        case .read:
            break
        case .externalRead:
            runningExternalJobs += 1
        case let .mutation(archiveID):
            mutatingArchiveIDs.insert(archiveID)
        }
    }

    private func releasePermit(for kind: ArchiveOperationKind) {
        switch kind {
        case .read:
            break
        case .externalRead:
            runningExternalJobs -= 1
        case let .mutation(archiveID):
            mutatingArchiveIDs.remove(archiveID)
        }
    }

    private func transition(_ id: ArchiveOperationID, to state: ArchiveOperationState) {
        guard var operation = operations[id] else { return }
        operation.state = state
        operations[id] = operation
        events[id, default: []].append(state)
    }
}
