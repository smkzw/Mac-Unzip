import CryptoKit
import Darwin
import Foundation

struct FixtureReport: Codable {
    let arguments: [String]
    let environment: [String: String]
    let openFileDescriptors: [Int32]
    let fileDescriptorEnumeration: String
    let processGroup: Int32
    let receivedPasswordSHA256: String
    let passwordLineHashes: [String]
}

func openFileDescriptors() throws -> [Int32] {
    var capacity = 32
    while capacity <= 65_536 {
        var entries = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let returnedBytes = entries.withUnsafeMutableBytes { bytes in
            proc_pidinfo(
                getpid(),
                PROC_PIDLISTFDS,
                0,
                bytes.baseAddress,
                Int32(bytes.count)
            )
        }
        guard returnedBytes >= 0 else { throw POSIXError(.EIO) }
        let count = Int(returnedBytes) / MemoryLayout<proc_fdinfo>.stride
        if returnedBytes < entries.count * MemoryLayout<proc_fdinfo>.stride {
            return entries.prefix(count).map(\.proc_fd).sorted()
        }
        capacity *= 2
    }
    throw POSIXError(.EOVERFLOW)
}

func readLineBytes() throws -> Data {
    var result = Data()
    var byte: UInt8 = 0
    while true {
        let count = read(STDIN_FILENO, &byte, 1)
        if count == 1 {
            if byte == UInt8(ascii: "\n") { return result }
            result.append(byte)
        } else if count == 0 {
            throw POSIXError(.EPIPE)
        } else if errno != EINTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}

func writeRepeated(byte: UInt8, count: Int, descriptor: Int32) throws {
    var chunk = [UInt8](repeating: byte, count: min(16 * 1_024, max(1, count)))
    var remaining = count
    while remaining > 0 {
        let requested = min(remaining, chunk.count)
        let written = Darwin.write(descriptor, &chunk, requested)
        if written > 0 {
            remaining -= written
        } else if written == -1 && errno != EINTR {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

func withCStringVector<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Result
) -> Result {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.dropLast().forEach { free($0) } }
    return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}

func spawnGrandchild(milliseconds: Int, escapeProcessGroup: Bool = false) throws -> pid_t {
    let duration = String(format: "%.3f", Double(milliseconds) / 1_000)
    let arguments = ["/bin/sleep", duration]
    let environment = [
        "LANG=en_US.UTF-8",
        "LC_ALL=en_US.UTF-8",
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
    ]
    var processID: pid_t = 0
    var attributes: posix_spawnattr_t?
    if escapeProcessGroup {
        guard posix_spawnattr_init(&attributes) == 0 else { throw POSIXError(.EIO) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            posix_spawnattr_destroy(&attributes)
            throw POSIXError(.EIO)
        }
    }
    defer { if escapeProcessGroup { posix_spawnattr_destroy(&attributes) } }
    let code = withCStringVector(arguments) { argv in
        withCStringVector(environment) { envp in
            posix_spawn(&processID, "/bin/sleep", nil, &attributes, argv, envp)
        }
    }
    guard code == 0 else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
    return processID
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let lineValue = option("--password-lines", in: arguments),
          let lineCount = Int(lineValue),
          lineCount > 0 else {
        throw CocoaError(.featureUnsupported)
    }

    let stdoutBytes = Int(option("--stdout-bytes", in: arguments) ?? "0") ?? 0
    let stderrBytes = Int(option("--stderr-bytes", in: arguments) ?? "0") ?? 0
    try writeRepeated(byte: UInt8(ascii: "O"), count: stdoutBytes, descriptor: STDOUT_FILENO)
    try writeRepeated(byte: UInt8(ascii: "E"), count: stderrBytes, descriptor: STDERR_FILENO)

    if arguments.contains("--never-read-stdin") {
        usleep(60_000_000)
    }
    let sleepBeforeReadMilliseconds = Int(option("--sleep-before-read-ms", in: arguments) ?? "0") ?? 0
    if sleepBeforeReadMilliseconds > 0 {
        usleep(useconds_t(min(sleepBeforeReadMilliseconds, 60_000) * 1_000))
    }

    var hashes: [String] = []
    hashes.reserveCapacity(lineCount)
    for _ in 0..<lineCount {
        hashes.append(sha256(try readLineBytes()))
    }

    if let grandchildValue = option("--spawn-grandchild-ms", in: arguments),
       let grandchildMilliseconds = Int(grandchildValue),
       grandchildMilliseconds > 0 {
        _ = try spawnGrandchild(milliseconds: grandchildMilliseconds)
    }
    if let grandchildValue = option("--spawn-escaped-grandchild-ms", in: arguments),
       let grandchildMilliseconds = Int(grandchildValue),
       grandchildMilliseconds > 0 {
        let escapedPID = try spawnGrandchild(
            milliseconds: grandchildMilliseconds,
            escapeProcessGroup: true
        )
        FileHandle.standardError.write(Data("escaped-pid:\(escapedPID)\n".utf8))
    }

    let sleepMilliseconds = Int(option("--sleep-ms", in: arguments) ?? "0") ?? 0
    if sleepMilliseconds > 0 {
        usleep(useconds_t(min(sleepMilliseconds, 60_000) * 1_000))
    }

    let report = FixtureReport(
        arguments: arguments,
        environment: ProcessInfo.processInfo.environment,
        openFileDescriptors: try openFileDescriptors(),
        fileDescriptorEnumeration: "proc_pidinfo(PROC_PIDLISTFDS)",
        processGroup: getpgrp(),
        receivedPasswordSHA256: hashes[0],
        passwordLineHashes: hashes
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    let requestedExit = Int32(option("--exit-code", in: arguments) ?? "0") ?? 0
    exit(requestedExit)
} catch {
    let message = "fixture-error:\(type(of: error))\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(64)
}
