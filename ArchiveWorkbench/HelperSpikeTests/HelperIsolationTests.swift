import Foundation
import Darwin
import Testing
@testable import HelperSpike

@Suite("Helper process isolation")
struct HelperIsolationTests {
    @Test("Very large drain durations saturate instead of overflowing")
    func drainDurationConversionSaturates() {
        #expect(dispatchNanosecondsForTesting(.seconds(Int64.max)) == Int.max)
    }

    @Test("A task cancelled before launch has no spawn side effect")
    func preCancelledTaskDoesNotSpawn() async {
        let hooks = HelperLauncherTestingHooks()
        let operation = Task { () -> (HelperError?, Bool) in
            var password = SecureBytes(Array("pre-cancelled".utf8))
            var observedError: HelperError?
            do {
                _ = try await HelperLauncher(testingHooks: hooks).run(
                    executable: fixtureExecutable,
                    arguments: ["--password-lines", "1"],
                    password: &password,
                    promptSequence: .passwordLines(1),
                    limits: .testDefault
                )
            } catch let error as HelperError {
                observedError = error
            } catch {}
            return (observedError, password.isZeroed)
        }
        operation.cancel()

        let (observedError, zeroed) = await operation.value

        #expect(observedError == .cancelledBeforeSpawn)
        #expect(hooks.spawnedProcessID == nil)
        #expect(zeroed)
    }

    @Test("Pipe endpoints are safe when the launcher starts with 0, 1, and 2 closed")
    func closedStandardDescriptorsCannotAliasPipeEndpoints() {
        var processID: pid_t = 0
        let arguments = [lowFDHarness.path, fixtureExecutable.path]
        let environment = ["LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8", "PATH=/usr/bin:/bin:/usr/sbin:/sbin"]
        let spawnCode = withCStringVector(arguments) { argv in
            withCStringVector(environment) { envp in
                posix_spawn(&processID, lowFDHarness.path, nil, nil, argv, envp)
            }
        }
        #expect(spawnCode == 0)
        var status: Int32 = 0
        #expect(waitpid(processID, &status, 0) == processID)
        #expect((status & 0x7f) == 0)
        #expect(((status >> 8) & 0xff) == 0)
    }

    @Test(
        "Pipe setup failures close every descriptor opened earlier",
        arguments: [2, 3]
    )
    func stagedPipeFailureDoesNotLeakDescriptors(failingCall: Int) async {
        let baseline = openDescriptorSet()
        var password = SecureBytes(Array("pipe-failure-\(UUID().uuidString)".utf8))
        var observedError: HelperError?

        do {
            _ = try await HelperLauncher(testingPipeFailureAt: failingCall).run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", "1"],
                password: &password,
                promptSequence: .passwordLines(1),
                limits: .testDefault
            )
        } catch let error as HelperError {
            observedError = error
        } catch {}

        let after = openDescriptorSet()
        let zeroed = password.isZeroed
        #expect(observedError == .pipeCreationFailed(EMFILE))
        #expect(after == baseline)
        #expect(zeroed)
    }

    @Test("Unexpected wait failures still terminate, reap, and join every channel")
    func unexpectedWaitFailureUsesTheSingleLifecycleOwner() async {
        let baseline = openDescriptorSet()
        let hooks = HelperLauncherTestingHooks(forceWaitFailure: true)
        var password = SecureBytes(Array("wait-failure-\(UUID().uuidString)".utf8))
        var observedError: HelperError?

        do {
            _ = try await HelperLauncher(testingHooks: hooks).run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", "1", "--sleep-ms", "5000"],
                password: &password,
                promptSequence: .passwordLines(1),
                limits: .testDefault
            )
        } catch let error as HelperError {
            observedError = error
        } catch {}

        let processID = hooks.spawnedProcessID
        let directProcessGone = processID.map { kill($0, 0) == -1 && errno == ESRCH } ?? false
        let processGroupGone = processID.map { kill(-$0, 0) == -1 && errno == ESRCH } ?? false
        let zeroed = password.isZeroed
        #expect(observedError == .waitFailed(ECHILD))
        #expect(directProcessGone)
        #expect(processGroupGone)
        #expect(openDescriptorSet() == baseline)
        #expect(zeroed)
    }

    @Test("A channel read error is surfaced and cannot be accepted as success")
    func drainReadErrorBecomesProtocolFailure() async throws {
        let hooks = HelperLauncherTestingHooks(forceStdoutReadFailure: true)
        var password = SecureBytes(Array("drain-failure-\(UUID().uuidString)".utf8))

        let result = try await HelperLauncher(testingHooks: hooks).run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: .testDefault
        )

        let zeroed = password.isZeroed
        #expect(result.termination == .protocolFailure)
        #expect(result.stdoutReadError == EBADF)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(zeroed)
    }

    @Test("CString allocation failure cannot truncate argv or leak setup resources")
    func cStringAllocationFailureIsExplicit() async {
        let baseline = openDescriptorSet()
        let hooks = HelperLauncherTestingHooks(forceCStringAllocationFailureAt: 2)
        var password = SecureBytes(Array("cstring-failure-\(UUID().uuidString)".utf8))
        var observedError: HelperError?

        do {
            _ = try await HelperLauncher(testingHooks: hooks).run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", "1"],
                password: &password,
                promptSequence: .passwordLines(1),
                limits: .testDefault
            )
        } catch let error as HelperError {
            observedError = error
        } catch {}

        let zeroed = password.isZeroed
        #expect(observedError == .argumentEncodingFailed)
        #expect(hooks.spawnedProcessID == nil)
        #expect(openDescriptorSet() == baseline)
        #expect(zeroed)
    }

    @Test("Spawn failure clears the password and every setup descriptor")
    func spawnFailureIsOwned() async throws {
        let baseline = openDescriptorSet()
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-task7-bogus-\(UUID().uuidString)")
        try Data("not a Mach-O executable".utf8).write(to: bogus)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bogus.path)
        defer { try? FileManager.default.removeItem(at: bogus) }
        var password = SecureBytes(Array("spawn-failure".utf8))
        var observedError: HelperError?

        do {
            _ = try await HelperLauncher().run(
                executable: bogus,
                arguments: [],
                password: &password,
                promptSequence: .passwordLines(1),
                limits: .testDefault
            )
        } catch let error as HelperError {
            observedError = error
        }

        if case .spawnFailed = observedError {} else {
            Issue.record("Expected spawnFailed, got \(String(describing: observedError))")
        }
        #expect(openDescriptorSet() == baseline)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Both output streams keep draining after their retention caps")
    func outputIsBoundedButFullyDrained() async throws {
        var password = SecureBytes(Array("output-\(UUID().uuidString)".utf8))
        let limits = HelperLimits(
            stdoutBytes: 1_024,
            stderrBytes: 2_048,
            timeout: .seconds(5)
        )

        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: [
                "--password-lines", "1",
                "--stdout-bytes", "262144",
                "--stderr-bytes", "196608"
            ],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: limits
        )

        let zeroed = password.isZeroed
        #expect(result.termination == .exited(0))
        #expect(result.stdout.count == 1_024)
        #expect(result.stderr.count == 2_048)
        #expect(result.stdoutTotalBytes >= 262_144)
        #expect(result.stderrTotalBytes >= 196_608)
        #expect(result.stdoutTruncated)
        #expect(result.stderrTruncated)
        #expect(zeroed)
    }

    @Test("A monotonic timeout terminates and reaps the child process group")
    func timeoutTerminatesAndReapsProcessGroup() async throws {
        var password = SecureBytes(Array("timeout-\(UUID().uuidString)".utf8))
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1", "--sleep-ms", "5000"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: HelperLimits(
                stdoutBytes: 4_096,
                stderrBytes: 4_096,
                timeout: .milliseconds(100),
                terminationGrace: .milliseconds(50)
            )
        )

        let elapsed = started.duration(to: clock.now)
        let zeroed = password.isZeroed
        #expect(result.termination == .timedOut)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(elapsed < .seconds(2))
        #expect(zeroed)
    }

    @Test("Timeout remains bounded while private stdin is backpressured")
    func timeoutDuringBackpressuredPrivateInput() async throws {
        let baseline = openDescriptorSet()
        let hooks = HelperLauncherTestingHooks(privateInputLimitOverride: 2 * 1_024 * 1_024)
        var password = SecureBytes([UInt8](repeating: 0x41, count: 1 * 1_024 * 1_024))
        let clock = ContinuousClock()
        let started = clock.now

        let result = try await HelperLauncher(testingHooks: hooks).run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "2", "--never-read-stdin"],
            password: &password,
            promptSequence: .passwordLines(2),
            limits: HelperLimits(
                stdoutBytes: 4_096,
                stderrBytes: 4_096,
                timeout: .milliseconds(100),
                terminationGrace: .milliseconds(50),
                drainGrace: .milliseconds(200)
            )
        )

        #expect(result.termination == .timedOut)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(started.duration(to: clock.now) < .seconds(2))
        #expect(hooks.spawnedProcessID.map { kill($0, 0) == -1 && errno == ESRCH } == true)
        #expect(openDescriptorSet() == baseline)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Cancellation remains bounded while private stdin is backpressured")
    func cancellationDuringBackpressuredPrivateInput() async throws {
        let baseline = openDescriptorSet()
        let hooks = HelperLauncherTestingHooks(privateInputLimitOverride: 2 * 1_024 * 1_024)
        let clock = ContinuousClock()
        let started = clock.now
        let operation = Task { () throws -> (HelperResult, Bool) in
            var password = SecureBytes([UInt8](repeating: 0x42, count: 1 * 1_024 * 1_024))
            let result = try await HelperLauncher(testingHooks: hooks).run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", "2", "--never-read-stdin"],
                password: &password,
                promptSequence: .passwordLines(2),
                limits: HelperLimits(
                    stdoutBytes: 4_096,
                    stderrBytes: 4_096,
                    timeout: .seconds(10),
                    terminationGrace: .milliseconds(50),
                    drainGrace: .milliseconds(200)
                )
            )
            return (result, password.isZeroed)
        }

        try await Task.sleep(for: .milliseconds(100))
        operation.cancel()
        let (result, zeroed) = try await operation.value
        #expect(result.termination == .cancelled)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(started.duration(to: clock.now) < .seconds(2))
        #expect(hooks.spawnedProcessID.map { kill($0, 0) == -1 && errno == ESRCH } == true)
        #expect(openDescriptorSet() == baseline)
        #expect(zeroed)
    }

    @Test("Task cancellation terminates the group and has one reaping owner")
    func cancellationTerminatesAndReapsProcessGroup() async throws {
        let operation = Task { () throws -> (HelperResult, Bool) in
            var password = SecureBytes(Array("cancel-\(UUID().uuidString)".utf8))
            let result = try await HelperLauncher().run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", "1", "--sleep-ms", "5000"],
                password: &password,
                promptSequence: .passwordLines(1),
                limits: HelperLimits(
                    stdoutBytes: 4_096,
                    stderrBytes: 4_096,
                    timeout: .seconds(10),
                    terminationGrace: .milliseconds(50)
                )
            )
            return (result, password.isZeroed)
        }

        try await Task.sleep(for: .milliseconds(100))
        operation.cancel()
        let (result, zeroed) = try await operation.value
        #expect(result.termination == .cancelled)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(zeroed)
    }

    @Test("A residual grandchild cannot hold output pipes open after its parent exits")
    func residualProcessGroupIsTerminatedBeforeDrainDeadline() async throws {
        var password = SecureBytes(Array("grandchild-\(UUID().uuidString)".utf8))
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: [
                "--password-lines", "1",
                "--spawn-grandchild-ms", "5000"
            ],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: HelperLimits(
                stdoutBytes: 4_096,
                stderrBytes: 4_096,
                timeout: .seconds(5),
                terminationGrace: .milliseconds(50)
            )
        )

        let elapsed = started.duration(to: clock.now)
        let zeroed = password.isZeroed
        #expect(result.termination == .protocolFailure)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(elapsed < .seconds(1))
        #expect(zeroed)
    }

    @Test("A retained writer cannot make output drain wait forever")
    func drainDeadlineIsBounded() async throws {
        let hooks = HelperLauncherTestingHooks(holdStdoutWriterOpen: true)
        var password = SecureBytes(Array("drain-deadline".utf8))
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await HelperLauncher(testingHooks: hooks).run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: HelperLimits(
                stdoutBytes: 4_096,
                stderrBytes: 4_096,
                timeout: .seconds(2),
                terminationGrace: .milliseconds(50),
                drainGrace: .milliseconds(100)
            )
        )
        #expect(result.termination == .protocolFailure)
        #expect(result.drainTimedOut)
        #expect(started.duration(to: clock.now) < .seconds(1))
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("A descendant that escapes the provider process group cannot hold drains forever")
    func escapedProcessGroupWriterHitsDrainDeadline() async throws {
        var password = SecureBytes(Array("escaped-writer".utf8))
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1", "--spawn-escaped-grandchild-ms", "5000"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: HelperLimits(
                stdoutBytes: 4_096,
                stderrBytes: 4_096,
                timeout: .seconds(2),
                terminationGrace: .milliseconds(50),
                drainGrace: .milliseconds(100)
            )
        )
        let stderrText = String(decoding: result.stderr, as: UTF8.self)
        let escapedPID = stderrText.split(separator: "\n")
            .first(where: { $0.hasPrefix("escaped-pid:") })
            .flatMap { pid_t($0.dropFirst("escaped-pid:".count)) }
        let escapedProcessGone = escapedPID.map(terminateEscapedTestProcess) ?? false

        #expect(result.termination == .protocolFailure)
        #expect(result.drainTimedOut)
        #expect(result.directChildReaped)
        #expect(result.processGroupGone)
        #expect(escapedPID != nil)
        #expect(started.duration(to: clock.now) < .seconds(1))
        #expect(escapedProcessGone)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }
}

private func terminateEscapedTestProcess(_ processID: pid_t) -> Bool {
    _ = kill(processID, SIGKILL)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    repeat {
        if kill(processID, 0) == -1 && errno == ESRCH { return true }
        usleep(5_000)
    } while clock.now < deadline
    return kill(processID, 0) == -1 && errno == ESRCH
}

private func openDescriptorSet() -> Set<Int32> {
    Set((Int32(0)..<Int32(512)).filter { descriptor in
        errno = 0
        return !(fcntl(descriptor, F_GETFD) == -1 && errno == EBADF)
    })
}

private final class IsolationTestBundleMarker: NSObject {}

private let fixtureExecutable = Bundle(for: IsolationTestBundleMarker.self)
    .bundleURL
    .deletingLastPathComponent()
    .appendingPathComponent("HelperFixture")

private let lowFDHarness = Bundle(for: IsolationTestBundleMarker.self)
    .bundleURL
    .deletingLastPathComponent()
    .appendingPathComponent("LowFDHarness")

private func withCStringVector<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    var pointers: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.dropLast().forEach { free($0) } }
    return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}
