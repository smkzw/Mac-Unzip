import CryptoKit
import Foundation
import Testing
@testable import HelperSpike

@Suite("Secure password ownership")
struct PasswordTransportTests {
    @Test("The owned password buffer can be explicitly zeroed")
    func explicitZeroizationOverwritesOwnedBytes() {
        var password = SecureBytes(Array("一次性测试口令".utf8))

        let startedNonzero = !password.isZeroed
        #expect(startedNonzero)
        password.zero()

        let endedZeroed = password.isZeroed
        #expect(endedZeroed)
    }

    @Test("An empty password is rejected before spawn and zeroized")
    func emptyPasswordIsRejected() async {
        let hooks = HelperLauncherTestingHooks()
        var password = SecureBytes([])
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

        #expect(observedError == .emptyPrivateInput)
        #expect(hooks.spawnedProcessID == nil)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Only the one-line and two-line provider contracts are accepted", arguments: [0, 3])
    func unsupportedPromptCountsAreRejected(lineCount: Int) async {
        let hooks = HelperLauncherTestingHooks()
        var password = SecureBytes(Array("prompt-contract".utf8))
        var observedError: HelperError?

        do {
            _ = try await HelperLauncher(testingHooks: hooks).run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", String(lineCount)],
                password: &password,
                promptSequence: .passwordLines(lineCount),
                limits: .testDefault
            )
        } catch let error as HelperError {
            observedError = error
        } catch {}

        #expect(observedError == .invalidPromptSequence)
        #expect(hooks.spawnedProcessID == nil)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Passwords above the explicit provider boundary are rejected")
    func oversizedPasswordIsRejected() async {
        let hooks = HelperLauncherTestingHooks()
        var password = SecureBytes([UInt8](repeating: 0x41, count: 16_385))
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

        #expect(observedError == .privateInputTooLarge(maximumBytes: 16_384))
        #expect(hooks.spawnedProcessID == nil)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Embedded NUL in argv is rejected instead of silently truncated")
    func embeddedNULIsRejected() async {
        let hooks = HelperLauncherTestingHooks()
        var password = SecureBytes(Array("nul-check".utf8))
        var observedError: HelperError?

        do {
            _ = try await HelperLauncher(testingHooks: hooks).run(
                executable: fixtureExecutable,
                arguments: ["--password-lines", "1", "safe\0hidden"],
                password: &password,
                promptSequence: .passwordLines(1),
                limits: .testDefault
            )
        } catch let error as HelperError {
            observedError = error
        } catch {}

        #expect(observedError == .embeddedNUL)
        #expect(hooks.spawnedProcessID == nil)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Line-protocol control bytes are rejected before spawn", arguments: [UInt8(0), 10, 13])
    func privateInputControlBytesAreRejected(byte: UInt8) async {
        let hooks = HelperLauncherTestingHooks()
        var password = SecureBytes([0x41, byte, 0x42])
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

        #expect(observedError == .unsupportedPrivateInputByte(byte))
        #expect(hooks.spawnedProcessID == nil)
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("The password travels only through the child-private input pipe")
    func passwordUsesOnlyPrivateInputChannel() async throws {
        let secretText = "task7-\(UUID().uuidString)-口令"
        let secretBytes = Array(secretText.utf8)
        let expectedDigest = SHA256.hash(data: Data(secretBytes))
            .map { String(format: "%02x", $0) }
            .joined()
        var password = SecureBytes(secretBytes)

        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: .testDefault
        )

        let report = try JSONDecoder().decode(FixtureReport.self, from: result.stdout)
        let captured = result.stdout + result.stderr
        let secretWasCaptured = captured.range(of: Data(secretBytes)) != nil
        let bufferWasZeroed = password.isZeroed
        #expect(result.termination == .exited(0))
        #expect(report.receivedPasswordSHA256 == expectedDigest)
        #expect(report.arguments == ["--password-lines", "1"])
        #expect(report.environment["LANG"] == "en_US.UTF-8")
        #expect(report.environment["LC_ALL"] == "en_US.UTF-8")
        #expect(report.environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        // Darwin may inject this CoreFoundation locale key after exec. It is
        // not inherited from the parent and cannot contain caller secrets.
        #expect(Set(report.environment.keys).subtracting([
            "LANG", "LC_ALL", "PATH", "__CF_USER_TEXT_ENCODING"
        ]).isEmpty)
        #expect(report.openFileDescriptors == [0, 1, 2])
        #expect(report.fileDescriptorEnumeration == "proc_pidinfo(PROC_PIDLISTFDS)")
        #expect(result.processInspectionAvailable)
        #expect(result.processSnapshotContainsExpectedExecutable)
        #expect(!result.privateInputDetectedInProcessSnapshot)
        #expect(result.processSnapshotSHA256.count == 64)
        #expect(!secretWasCaptured)
        #expect(bufferWasZeroed)
    }

    @Test("An explicit two-prompt protocol sends the same borrowed bytes twice")
    func twoPromptSequenceIsExact() async throws {
        let secret = Array("two-lines-\(UUID().uuidString)".utf8)
        let digest = SHA256.hash(data: Data(secret)).map { String(format: "%02x", $0) }.joined()
        var password = SecureBytes(secret)

        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "2"],
            password: &password,
            promptSequence: .passwordLines(2),
            limits: .testDefault
        )

        let report = try JSONDecoder().decode(FixtureReport.self, from: result.stdout)
        #expect(report.passwordLineHashes == [digest, digest])
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("Parent-only descriptors are not inherited by the child")
    func unrelatedParentDescriptorsAreClosedOnExec() async throws {
        let descriptors = (0..<64).compactMap { _ -> Int32? in
            let descriptor = Darwin.open("/dev/null", O_RDONLY)
            return descriptor >= 0 ? descriptor : nil
        }
        defer { descriptors.forEach { _ = Darwin.close($0) } }
        let highDescriptor = fcntl(descriptors[0], F_DUPFD_CLOEXEC, 300)
        #expect(highDescriptor >= 300)
        defer { if highDescriptor >= 0 { _ = Darwin.close(highDescriptor) } }
        var password = SecureBytes(Array("fd-isolation".utf8))

        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: .testDefault
        )

        let report = try JSONDecoder().decode(FixtureReport.self, from: result.stdout)
        #expect(report.openFileDescriptors == [0, 1, 2])
        let zeroed = password.isZeroed
        #expect(zeroed)
    }

    @Test("A nonzero child exit still clears the owned password")
    func childFailureStillZeroesPassword() async throws {
        var password = SecureBytes(Array("child-failure".utf8))
        let result = try await HelperLauncher().run(
            executable: fixtureExecutable,
            arguments: ["--password-lines", "1", "--exit-code", "23"],
            password: &password,
            promptSequence: .passwordLines(1),
            limits: .testDefault
        )
        #expect(result.termination == .exited(23))
        let zeroed = password.isZeroed
        #expect(zeroed)
    }
}

private struct FixtureReport: Decodable {
    let arguments: [String]
    let environment: [String: String]
    let receivedPasswordSHA256: String
    let passwordLineHashes: [String]
    let openFileDescriptors: [Int32]
    let fileDescriptorEnumeration: String
}

private final class TestBundleMarker: NSObject {}

private let fixtureExecutable = Bundle(for: TestBundleMarker.self)
    .bundleURL
    .deletingLastPathComponent()
    .appendingPathComponent("HelperFixture")
