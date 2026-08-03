import CryptoKit
import Darwin
import Foundation
import Testing
@testable import HelperSpike

@Suite("Pinned 7zz private-input probe", .serialized)
struct SevenZipProbeTests {
    @Test("Bare -p uses one private line and wrong or absent passwords cannot open the archive")
    func encryptedRoundTrip() async throws {
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/7zz")
        let expectedExecutableHash = "2f412eded2d37f2cc52f26138e6964bd205ea0bf2ee6a70b8b990a18107e784d"
        #expect(try sha256(Data(contentsOf: executable)) == expectedExecutableHash)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-task7-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("中英-fixture-\(UUID().uuidString).txt")
        let archive = root.appendingPathComponent("probe.7z")
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let payload = Data("archive-workbench-seven-zip-probe".utf8)
        try payload.write(to: source, options: .atomic)
        let secretText = "probe-\(UUID().uuidString)-口令"

        let create = try await invoke(
            executable, arguments: ["a", "-t7z", "-p", "-mhe=on", archive.path, source.path],
            secret: secretText, promptLines: 1
        )
        expectCleanSuccess(create)
        let list = try await invoke(executable, arguments: ["l", "-slt", archive.path], secret: secretText, promptLines: 1)
        expectCleanSuccess(list)
        let listText = String(decoding: list.stdout, as: UTF8.self)
        #expect(listText.contains(source.lastPathComponent))
        #expect(listText.contains("Encrypted = +"))
        let test = try await invoke(executable, arguments: ["t", archive.path], secret: secretText, promptLines: 1)
        expectCleanSuccess(test)
        let extract = try await invoke(
            executable, arguments: ["x", "-y", "-o\(extracted.path)", archive.path],
            secret: secretText, promptLines: 1
        )
        expectCleanSuccess(extract)

        let protectedOperations = [
            ["l", "-slt", archive.path],
            ["t", archive.path],
            ["x", "-y", "-o\(root.appendingPathComponent("negative").path)", archive.path]
        ]
        for arguments in protectedOperations {
            let wrong = try await invoke(
                executable,
                arguments: arguments,
                secret: "wrong-\(UUID().uuidString)",
                promptLines: 1
            )
            #expect(wrong.termination != .exited(0))
            #expect(wrong.directChildReaped)
            #expect(wrong.processGroupGone)
            #expect(try invokeWithoutPrivateInput(executable, arguments: arguments) != 0)
        }

        let extractedFile = extracted.appendingPathComponent(source.lastPathComponent)
        #expect(try sha256(Data(contentsOf: extractedFile)) == sha256(payload))
        for result in [create, list, test, extract] {
            let channels = result.stdout + result.stderr
            #expect(channels.range(of: Data(secretText.utf8)) == nil)
            #expect(!result.privateInputDetectedInProcessSnapshot)
            #expect(result.processInspectionAvailable)
            #expect(result.processSnapshotContainsExpectedExecutable)
        }

        let record = ProviderSpikeResult(
            provider: .sevenZip,
            version: "26.02-arm64",
            status: .pass,
            commandArgumentHash: sha256(Data("a|l|t|x|-t7z|-p|-mhe=on|-slt|-y".utf8)),
            outputSHA256: sha256(try Data(contentsOf: extractedFile)),
            failureCode: nil
        )
        let encoded = try JSONEncoder().encode(record)
        #expect(encoded.range(of: Data(secretText.utf8)) == nil)
        #expect(encoded.range(of: Data(root.path.utf8)) == nil)
    }
}

private func expectCleanSuccess(_ result: HelperResult, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(result.termination == .exited(0), sourceLocation: sourceLocation)
    #expect(!result.stdoutTruncated, sourceLocation: sourceLocation)
    #expect(!result.stderrTruncated, sourceLocation: sourceLocation)
    #expect(result.stdoutReadError == nil, sourceLocation: sourceLocation)
    #expect(result.stderrReadError == nil, sourceLocation: sourceLocation)
    #expect(!result.drainTimedOut, sourceLocation: sourceLocation)
    #expect(result.directChildReaped, sourceLocation: sourceLocation)
    #expect(result.processGroupGone, sourceLocation: sourceLocation)
    #expect(result.processInspectionAvailable, sourceLocation: sourceLocation)
    #expect(result.processSnapshotContainsExpectedExecutable, sourceLocation: sourceLocation)
}

private func invokeWithoutPrivateInput(_ executable: URL, arguments: [String]) throws -> Int32 {
    var actions: posix_spawn_file_actions_t?
    guard posix_spawn_file_actions_init(&actions) == 0 else { throw POSIXError(.EIO) }
    defer { posix_spawn_file_actions_destroy(&actions) }
    guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
          posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0) == 0,
          posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0 else {
        throw POSIXError(.EIO)
    }
    var argv: [UnsafeMutablePointer<CChar>?] = ([executable.path] + arguments).map { strdup($0) }
    let environment: [String] = [
        "LANG=en_US.UTF-8", "LC_ALL=en_US.UTF-8", "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
    ]
    var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup($0) }
    argv.append(nil)
    envp.append(nil)
    defer {
        argv.dropLast().forEach { free($0) }
        envp.dropLast().forEach { free($0) }
    }
    var processID: pid_t = 0
    let spawnCode = argv.withUnsafeMutableBufferPointer { argvPointer in
        envp.withUnsafeMutableBufferPointer { envPointer in
            posix_spawn(&processID, executable.path, &actions, nil, argvPointer.baseAddress!, envPointer.baseAddress!)
        }
    }
    guard spawnCode == 0 else { throw POSIXError(POSIXErrorCode(rawValue: spawnCode) ?? .EIO) }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    var status: Int32 = 0
    while true {
        let waited = waitpid(processID, &status, WNOHANG)
        if waited == processID { break }
        if waited == -1 { throw POSIXError(.ECHILD) }
        if clock.now >= deadline {
            _ = kill(processID, SIGKILL)
            _ = waitpid(processID, &status, 0)
            throw POSIXError(.ETIMEDOUT)
        }
        usleep(10_000)
    }
    return (status >> 8) & 0xff
}

private func invoke(
    _ executable: URL,
    arguments: [String],
    secret: String,
    promptLines: Int
) async throws -> HelperResult {
    var password = SecureBytes(Array(secret.utf8))
    return try await HelperLauncher().run(
        executable: executable,
        arguments: arguments,
        password: &password,
        promptSequence: .passwordLines(promptLines),
        limits: HelperLimits(stdoutBytes: 256 * 1_024, stderrBytes: 256 * 1_024, timeout: .seconds(20))
    )
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
