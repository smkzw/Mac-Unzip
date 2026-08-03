import Darwin
import CryptoKit
import Foundation

public enum PromptSequence: Equatable, Sendable {
    case passwordLines(Int)
}

public struct HelperLimits: Equatable, Sendable {
    public let stdoutBytes: Int
    public let stderrBytes: Int
    public let timeout: Duration
    public let terminationGrace: Duration
    public let drainGrace: Duration

    public init(
        stdoutBytes: Int,
        stderrBytes: Int,
        timeout: Duration,
        terminationGrace: Duration = .milliseconds(250),
        drainGrace: Duration = .seconds(1)
    ) {
        precondition(stdoutBytes >= 0 && stderrBytes >= 0)
        self.stdoutBytes = stdoutBytes
        self.stderrBytes = stderrBytes
        self.timeout = timeout
        self.terminationGrace = terminationGrace
        self.drainGrace = drainGrace
    }

    public static let testDefault = HelperLimits(
        stdoutBytes: 64 * 1_024,
        stderrBytes: 64 * 1_024,
        timeout: .seconds(5)
    )
}

public enum HelperTermination: Equatable, Sendable {
    case exited(Int32)
    case signaled(Int32)
    case timedOut
    case cancelled
    case protocolFailure
}

public struct HelperResult: Equatable, Sendable {
    public let termination: HelperTermination
    public let stdout: Data
    public let stderr: Data
    public let stdoutTotalBytes: Int
    public let stderrTotalBytes: Int
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let stdoutReadError: Int32?
    public let stderrReadError: Int32?
    public let processInspectionAvailable: Bool
    public let processSnapshotContainsExpectedExecutable: Bool
    public let privateInputDetectedInProcessSnapshot: Bool
    public let processSnapshotSHA256: String
    public let directChildReaped: Bool
    public let processGroupGone: Bool
    public let drainTimedOut: Bool
}

public enum HelperError: Error, Equatable, Sendable {
    case invalidExecutable
    case cancelledBeforeSpawn
    case invalidPromptSequence
    case emptyPrivateInput
    case privateInputTooLarge(maximumBytes: Int)
    case unsupportedPrivateInputByte(UInt8)
    case embeddedNUL
    case pipeCreationFailed(Int32)
    case spawnSetupFailed(Int32)
    case spawnFailed(Int32)
    case argumentEncodingFailed
    case inputWriteFailed(Int32)
    case waitFailed(Int32)
}

final class HelperLauncherTestingHooks: @unchecked Sendable {
    let forceWaitFailure: Bool
    let forceStdoutReadFailure: Bool
    let forceCStringAllocationFailureAt: Int?
    let holdStdoutWriterOpen: Bool
    let privateInputLimitOverride: Int?
    private let lock = NSLock()
    private var recordedProcessID: pid_t?

    init(
        forceWaitFailure: Bool = false,
        forceStdoutReadFailure: Bool = false,
        forceCStringAllocationFailureAt: Int? = nil,
        holdStdoutWriterOpen: Bool = false,
        privateInputLimitOverride: Int? = nil
    ) {
        self.forceWaitFailure = forceWaitFailure
        self.forceStdoutReadFailure = forceStdoutReadFailure
        self.forceCStringAllocationFailureAt = forceCStringAllocationFailureAt
        self.holdStdoutWriterOpen = holdStdoutWriterOpen
        self.privateInputLimitOverride = privateInputLimitOverride
    }

    var spawnedProcessID: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return recordedProcessID
    }

    func record(processID: pid_t) {
        lock.lock()
        recordedProcessID = processID
        lock.unlock()
    }
}

public struct HelperLauncher: Sendable {
    private let testingPipeFailureAt: Int?
    private let testingHooks: HelperLauncherTestingHooks?

    public init() {
        testingPipeFailureAt = nil
        testingHooks = nil
    }

    init(testingPipeFailureAt: Int) {
        self.testingPipeFailureAt = testingPipeFailureAt
        testingHooks = nil
    }

    init(testingHooks: HelperLauncherTestingHooks) {
        testingPipeFailureAt = nil
        self.testingHooks = testingHooks
    }

    public func run(
        executable: URL,
        arguments: [String],
        password: inout SecureBytes,
        promptSequence: PromptSequence,
        limits: HelperLimits
    ) async throws -> HelperResult {
        defer { password.zero() }
        guard !Task.isCancelled else { throw HelperError.cancelledBeforeSpawn }
        guard executable.isFileURL,
              executable.path.hasPrefix("/"),
              access(executable.path, X_OK) == 0 else {
            throw HelperError.invalidExecutable
        }
        guard case let .passwordLines(lineCount) = promptSequence, (1...2).contains(lineCount) else {
            throw HelperError.invalidPromptSequence
        }
        guard password.count > 0 else { throw HelperError.emptyPrivateInput }
        let maximumPasswordBytes = testingHooks?.privateInputLimitOverride ?? (16 * 1_024)
        guard password.count <= maximumPasswordBytes else {
            throw HelperError.privateInputTooLarge(maximumBytes: maximumPasswordBytes)
        }
        let unsupportedByte = password.withUnsafeBytes { bytes -> UInt8? in
            for byte in bytes where byte == 0 || byte == 10 || byte == 13 { return byte }
            return nil
        }
        if let unsupportedByte { throw HelperError.unsupportedPrivateInputByte(unsupportedByte) }

        var ownedPipes: [PipePair] = []
        var spawned = false
        defer {
            if !spawned {
                ownedPipes.forEach { $0.closeBoth() }
            }
        }
        let input = try makePipe(callIndex: 1, forcedFailureAt: testingPipeFailureAt)
        ownedPipes.append(input)
        let output = try makePipe(callIndex: 2, forcedFailureAt: testingPipeFailureAt)
        ownedPipes.append(output)
        let error = try makePipe(callIndex: 3, forcedFailureAt: testingPipeFailureAt)
        ownedPipes.append(error)
        var lifecycleComplete = false
        var cleanupDrainGroup: DispatchGroup?
        var cleanupDrains: [BoundedDrain] = []
        var cleanupProcessID: pid_t?
        var heldOutputWriter: Int32 = -1
        defer {
            if spawned, !lifecycleComplete, let processID = cleanupProcessID {
                input.closeWrite()
                terminateProcessGroup(processID, grace: limits.terminationGrace)
                _ = reap(processID)
                _ = waitForProcessGroupGone(processID, grace: limits.terminationGrace)
                closeDescriptor(&heldOutputWriter)
                if let cleanupDrainGroup,
                   !waitForDrain(cleanupDrainGroup, grace: limits.drainGrace) {
                    cleanupDrains.forEach { $0.cancel() }
                    _ = waitForDrain(cleanupDrainGroup, grace: limits.drainGrace)
                }
            }
            closeDescriptor(&heldOutputWriter)
        }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        let actionInit = posix_spawn_file_actions_init(&actions)
        guard actionInit == 0 else { throw HelperError.spawnSetupFailed(actionInit) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        let attributeInit = posix_spawnattr_init(&attributes)
        guard attributeInit == 0 else { throw HelperError.spawnSetupFailed(attributeInit) }
        defer { posix_spawnattr_destroy(&attributes) }

        try checkSpawnSetup(posix_spawn_file_actions_adddup2(&actions, input.read, STDIN_FILENO))
        try checkSpawnSetup(posix_spawn_file_actions_adddup2(&actions, output.write, STDOUT_FILENO))
        try checkSpawnSetup(posix_spawn_file_actions_adddup2(&actions, error.write, STDERR_FILENO))
        for descriptor in [input.write, output.read, error.read] {
            try checkSpawnSetup(posix_spawn_file_actions_addclose(&actions, descriptor))
        }
        for descriptor in [input.read, output.write, error.write] where descriptor > STDERR_FILENO {
            try checkSpawnSetup(posix_spawn_file_actions_addclose(&actions, descriptor))
        }

        let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP
        try checkSpawnSetup(posix_spawnattr_setflags(&attributes, Int16(flags)))
        try checkSpawnSetup(posix_spawnattr_setpgroup(&attributes, 0))

        let argv = [executable.path] + arguments
        let environment = [
            "LANG=en_US.UTF-8",
            "LC_ALL=en_US.UTF-8",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
        ]
        let argvVector = try CStringVector(
            argv,
            forcedAllocationFailureAt: testingHooks?.forceCStringAllocationFailureAt
        )
        let environmentVector = try CStringVector(environment)
        var processID: pid_t = 0
        let spawnCode = argvVector.withUnsafeMutablePointer { argvPointer in
            environmentVector.withUnsafeMutablePointer { environmentPointer in
                posix_spawn(
                    &processID,
                    executable.path,
                    &actions,
                    &attributes,
                    argvPointer,
                    environmentPointer
                )
            }
        }
        guard spawnCode == 0 else { throw HelperError.spawnFailed(spawnCode) }
        spawned = true
        cleanupProcessID = processID
        testingHooks?.record(processID: processID)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: limits.timeout)

        input.closeRead()
        let inputFlags = fcntl(input.write, F_GETFL)
        guard inputFlags >= 0,
              fcntl(input.write, F_SETFL, inputFlags | O_NONBLOCK) == 0 else {
            throw HelperError.inputWriteFailed(errno)
        }
        if testingHooks?.holdStdoutWriterOpen == true {
            heldOutputWriter = dup(output.write)
            if heldOutputWriter >= 0 { _ = fcntl(heldOutputWriter, F_SETFD, FD_CLOEXEC) }
        }
        output.closeWrite()
        error.closeWrite()
        if testingHooks?.forceStdoutReadFailure == true {
            output.closeRead()
        }

        let stdoutDrain = BoundedDrain(descriptor: output.read, capacity: limits.stdoutBytes)
        let stderrDrain = BoundedDrain(descriptor: error.read, capacity: limits.stderrBytes)
        let drainGroup = DispatchGroup()
        cleanupDrains = [stdoutDrain, stderrDrain]
        cleanupDrainGroup = drainGroup
        let drainQueue = DispatchQueue(label: "com.smkzw.ArchiveWorkbench.helper-drain", attributes: .concurrent)
        drainGroup.enter()
        drainQueue.async {
            stdoutDrain.run()
            drainGroup.leave()
        }
        drainGroup.enter()
        drainQueue.async {
            stderrDrain.run()
            drainGroup.leave()
        }

        // Give the fixed child time to enter its deliberately blocking read so
        // process argv/environment are observed independently while it is alive.
        let processInspection = password.withUnsafeBytes { privateInput in
            inspectProcess(
                processID,
                expectedExecutable: executable.lastPathComponent,
                privateInput: privateInput
            )
        }

        var waitStatus: Int32 = 0
        var terminal: HelperTermination?
        var directChildReaped = false
        var completedLines = 0
        var passwordOffset = 0
        var newlinePending = false
        while terminal == nil {
            if testingHooks?.forceWaitFailure == true {
                throw HelperError.waitFailed(ECHILD)
            }
            let waited = waitpid(processID, &waitStatus, WNOHANG)
            if waited == processID {
                terminal = decodeWaitStatus(waitStatus)
                directChildReaped = true
                break
            }
            if waited == -1 { throw HelperError.waitFailed(errno) }
            if Task.isCancelled {
                terminateProcessGroup(processID, grace: limits.terminationGrace)
                directChildReaped = reap(processID) != nil
                terminal = .cancelled
                break
            }
            if clock.now >= deadline {
                terminateProcessGroup(processID, grace: limits.terminationGrace)
                directChildReaped = reap(processID) != nil
                terminal = .timedOut
                break
            }

            if completedLines < lineCount {
                let writeOutcome: NonblockingWriteOutcome
                if newlinePending {
                    var newline = UInt8(ascii: "\n")
                    writeOutcome = try withUnsafeBytes(of: &newline) { bytes in
                        try writeNonblocking(input.write, bytes: bytes, offset: 0)
                    }
                    if case .progress = writeOutcome {
                        completedLines += 1
                        passwordOffset = 0
                        newlinePending = false
                        if completedLines == lineCount { input.closeWrite() }
                    }
                } else {
                    writeOutcome = try password.withUnsafeBytes { bytes in
                        try writeNonblocking(input.write, bytes: bytes, offset: passwordOffset)
                    }
                    if case let .progress(count) = writeOutcome {
                        passwordOffset += count
                        if passwordOffset == password.count { newlinePending = true }
                    }
                }
                if writeOutcome == .wouldBlock {
                    waitUntilWritable(input.write, maximumMilliseconds: 10)
                }
            } else {
                sleepForNanoseconds(10_000_000)
            }
        }
        input.closeWrite()

        let groupWasGone = processGroupIsGone(processID)
        if !groupWasGone, terminal != .timedOut, terminal != .cancelled {
            terminateProcessGroup(processID, grace: limits.terminationGrace)
            terminal = .protocolFailure
        }
        let processGroupGone = groupWasGone || waitForProcessGroupGone(
            processID,
            grace: limits.terminationGrace
        )

        var drainTimedOut = false
        if !waitForDrain(drainGroup, grace: limits.drainGrace) {
            drainTimedOut = true
            closeDescriptor(&heldOutputWriter)
            stdoutDrain.cancel()
            stderrDrain.cancel()
            _ = waitForDrain(drainGroup, grace: limits.drainGrace)
            terminal = .protocolFailure
        }
        let stdout = stdoutDrain.snapshot()
        let stderr = stderrDrain.snapshot()
        if stdout.readError != nil || stderr.readError != nil {
            terminal = .protocolFailure
        }
        let result = HelperResult(
            termination: terminal!,
            stdout: stdout.data,
            stderr: stderr.data,
            stdoutTotalBytes: stdout.totalBytes,
            stderrTotalBytes: stderr.totalBytes,
            stdoutTruncated: stdout.truncated,
            stderrTruncated: stderr.truncated,
            stdoutReadError: stdout.readError,
            stderrReadError: stderr.readError,
            processInspectionAvailable: processInspection.available,
            processSnapshotContainsExpectedExecutable: processInspection.containsExpectedExecutable,
            privateInputDetectedInProcessSnapshot: processInspection.containsPrivateInput,
            processSnapshotSHA256: processInspection.sha256,
            directChildReaped: directChildReaped,
            processGroupGone: processGroupGone,
            drainTimedOut: drainTimedOut
        )
        lifecycleComplete = true
        return result
    }
}

private final class PipePair {
    var read: Int32
    var write: Int32

    init(read: Int32, write: Int32) {
        self.read = read
        self.write = write
    }

    func closeRead() { closeDescriptor(&read) }
    func closeWrite() { closeDescriptor(&write) }
    func closeBoth() { closeRead(); closeWrite() }
}

private func makePipe(callIndex: Int, forcedFailureAt: Int?) throws -> PipePair {
    if forcedFailureAt == callIndex {
        throw HelperError.pipeCreationFailed(EMFILE)
    }
    var descriptors: [Int32] = [-1, -1]
    guard pipe(&descriptors) == 0 else { throw HelperError.pipeCreationFailed(errno) }
    for index in descriptors.indices where descriptors[index] <= STDERR_FILENO {
        let duplicated = fcntl(descriptors[index], F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
        guard duplicated >= 0 else {
            let code = errno
            descriptors.forEach { _ = Darwin.close($0) }
            throw HelperError.pipeCreationFailed(code)
        }
        _ = Darwin.close(descriptors[index])
        descriptors[index] = duplicated
    }
    for descriptor in descriptors {
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            let code = errno
            descriptors.forEach { _ = Darwin.close($0) }
            throw HelperError.pipeCreationFailed(code)
        }
    }
    guard fcntl(descriptors[1], F_SETNOSIGPIPE, 1) == 0 else {
        let code = errno
        descriptors.forEach { _ = Darwin.close($0) }
        throw HelperError.pipeCreationFailed(code)
    }
    return PipePair(read: descriptors[0], write: descriptors[1])
}

private func closeDescriptor(_ descriptor: inout Int32) {
    guard descriptor >= 0 else { return }
    let ownedDescriptor = descriptor
    descriptor = -1
    // On Darwin an EINTR result does not make retrying close safe: the number
    // may already have been released and reused by another thread.
    _ = Darwin.close(ownedDescriptor)
}

private func checkSpawnSetup(_ code: Int32) throws {
    guard code == 0 else { throw HelperError.spawnSetupFailed(code) }
}

private final class CStringVector {
    private var pointers: [UnsafeMutablePointer<CChar>?] = []

    init(_ strings: [String], forcedAllocationFailureAt: Int? = nil) throws {
        pointers.reserveCapacity(strings.count + 1)
        for (offset, string) in strings.enumerated() {
            guard !string.utf8.contains(0) else {
                pointers.forEach { free($0) }
                pointers.removeAll(keepingCapacity: false)
                throw HelperError.embeddedNUL
            }
            let pointer = forcedAllocationFailureAt == offset + 1 ? nil : strdup(string)
            guard let pointer else {
                pointers.forEach { free($0) }
                pointers.removeAll(keepingCapacity: false)
                throw HelperError.argumentEncodingFailed
            }
            pointers.append(pointer)
        }
        pointers.append(nil)
    }

    deinit {
        pointers.dropLast().forEach { free($0) }
    }

    func withUnsafeMutablePointer<Result>(
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
    ) -> Result {
        pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
    }
}

private enum NonblockingWriteOutcome: Equatable {
    case progress(Int)
    case wouldBlock
}

private func writeNonblocking(
    _ descriptor: Int32,
    bytes: UnsafeRawBufferPointer,
    offset: Int
) throws -> NonblockingWriteOutcome {
    precondition(offset < bytes.count)
    while true {
        let written = Darwin.write(
            descriptor,
            bytes.baseAddress!.advanced(by: offset),
            bytes.count - offset
        )
        if written > 0 { return .progress(written) }
        if written == -1 && errno == EINTR { continue }
        if written == -1 && (errno == EAGAIN || errno == EWOULDBLOCK) { return .wouldBlock }
        throw HelperError.inputWriteFailed(errno)
    }
}

private func waitUntilWritable(_ descriptor: Int32, maximumMilliseconds: Int32) {
    var event = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
    while poll(&event, 1, maximumMilliseconds) == -1 && errno == EINTR {}
}

private struct DrainSnapshot {
    let data: Data
    let totalBytes: Int
    let truncated: Bool
    let readError: Int32?
}

private final class BoundedDrain: @unchecked Sendable {
    private let descriptor: Int32
    private let capacity: Int
    private let lock = NSLock()
    private var data = Data()
    private var totalBytes = 0
    private var readError: Int32?
    private var closed = false
    private var cancelled = false

    init(descriptor: Int32, capacity: Int) {
        self.descriptor = descriptor
        self.capacity = capacity
    }

    func run() {
        defer { closeOnce() }
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                lock.lock()
                totalBytes += count
                let retained = min(count, max(0, capacity - data.count))
                if retained > 0 { data.append(contentsOf: buffer[0..<retained]) }
                lock.unlock()
            } else if count == 0 {
                return
            } else if errno != EINTR {
                lock.lock()
                if !cancelled { readError = errno }
                lock.unlock()
                return
            }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let shouldClose = !closed
        if shouldClose { closed = true }
        lock.unlock()
        if shouldClose { _ = Darwin.close(descriptor) }
    }

    private func closeOnce() {
        lock.lock()
        let shouldClose = !closed
        if shouldClose { closed = true }
        lock.unlock()
        if shouldClose { _ = Darwin.close(descriptor) }
    }

    func snapshot() -> DrainSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DrainSnapshot(
            data: data,
            totalBytes: totalBytes,
            truncated: totalBytes > data.count,
            readError: readError
        )
    }
}

private func waitForDrain(_ group: DispatchGroup, grace: Duration) -> Bool {
    group.wait(timeout: .now() + .nanoseconds(dispatchNanosecondsForTesting(grace))) == .success
}

func dispatchNanosecondsForTesting(_ duration: Duration) -> Int {
    let components = duration.components
    let seconds = max(Int64(0), components.seconds)
    let nanoseconds = max(Int64(0), Int64(components.attoseconds / 1_000_000_000))
    let total = seconds.multipliedReportingOverflow(by: 1_000_000_000)
    guard !total.overflow else { return Int.max }
    let combined = total.partialValue.addingReportingOverflow(nanoseconds)
    guard !combined.overflow else { return Int.max }
    return Int(min(Int64(Int.max), combined.partialValue))
}

private func decodeWaitStatus(_ status: Int32) -> HelperTermination {
    let signal = status & 0x7f
    if signal == 0 { return .exited((status >> 8) & 0xff) }
    return .signaled(signal)
}

private func reap(_ processID: pid_t) -> Int32? {
    var status: Int32 = 0
    while true {
        let waited = waitpid(processID, &status, 0)
        if waited == processID { return status }
        if waited == -1 && errno == EINTR { continue }
        return nil
    }
}

private func terminateProcessGroup(_ processID: pid_t, grace: Duration) {
    _ = kill(-processID, SIGTERM)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: grace)
    while clock.now < deadline {
        if kill(-processID, 0) == -1 && errno == ESRCH { return }
        sleepForNanoseconds(10_000_000)
    }
    _ = kill(-processID, SIGKILL)
}

private func processGroupIsGone(_ processID: pid_t) -> Bool {
    kill(-processID, 0) == -1 && errno == ESRCH
}

private func waitForProcessGroupGone(_ processID: pid_t, grace: Duration) -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: grace)
    repeat {
        if processGroupIsGone(processID) { return true }
        sleepForNanoseconds(5_000_000)
    } while clock.now < deadline
    return processGroupIsGone(processID)
}

private struct ProcessInspection {
    let available: Bool
    let containsExpectedExecutable: Bool
    let containsPrivateInput: Bool
    let sha256: String
}

private func inspectProcess(
    _ processID: pid_t,
    expectedExecutable: String,
    privateInput: UnsafeRawBufferPointer
) -> ProcessInspection {
    for _ in 0..<20 {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, processID]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return ProcessInspection(
                available: false,
                containsExpectedExecutable: false,
                containsPrivateInput: false,
                sha256: ""
            )
        }
        var bytes = [UInt8](repeating: 0, count: size)
        if sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 {
            let strings = bytes.dropFirst(MemoryLayout<Int32>.size)
                .split(separator: 0)
                .compactMap { String(bytes: $0, encoding: .utf8) }
            let snapshot = strings.joined(separator: "\n")
            if snapshot.contains(expectedExecutable) {
                let observedBytes = Array(bytes.prefix(size))
                let digest = SHA256.hash(data: Data(observedBytes))
                    .map { String(format: "%02x", $0) }
                    .joined()
                return ProcessInspection(
                    available: true,
                    containsExpectedExecutable: true,
                    containsPrivateInput: containsBytes(observedBytes, needle: privateInput),
                    sha256: digest
                )
            }
        }
        sleepForNanoseconds(5_000_000)
    }
    return ProcessInspection(
        available: false,
        containsExpectedExecutable: false,
        containsPrivateInput: false,
        sha256: ""
    )
}

private func containsBytes(_ haystack: [UInt8], needle: UnsafeRawBufferPointer) -> Bool {
    guard needle.count > 0, haystack.count >= needle.count else { return false }
    for start in 0...(haystack.count - needle.count) {
        var equal = true
        for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
            equal = false
            break
        }
        if equal { return true }
    }
    return false
}

private func sleepForNanoseconds(_ nanoseconds: Int) {
    var requested = timespec(tv_sec: 0, tv_nsec: nanoseconds)
    var remainder = timespec()
    while nanosleep(&requested, &remainder) == -1 && errno == EINTR {
        requested = remainder
    }
}
