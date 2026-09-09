import ArchiveDomain
import ArchiveSecurity
import CryptoKit
import Darwin
import Foundation

// MARK: - Read-only 7z provider backed by the system 7zz binary
//
// Design principles (from handoff):
// - 7z/RAR 读取走隔离、验证后的 7zz：the executable is discovered at runtime,
//   validated (regular file, not a writable-location symlink, arm64, version
//   banner) and hashed before first use.
// - provider 能力必须按真实运行时发现和验证：capabilities are gated on a
//   successful discovery, never assumed from a design matrix.
// - 不允许 mutation 静默 fallback 到不同引擎：this provider is strictly
//   read-only (.list/.read/.preview). Creation/update are intentionally not
//   implemented and never fall back to another engine.
// - helper 可执行文件身份/架构/版本/权限/hash/可写路径/symlink/TOCTOU：see
//   SevenZipBinaryDiscovery. A residual path-validation->spawn TOCTOU window is
//   acknowledged; the binary must live in a trusted prefix whose resolved
//   target is not group/world writable, and its SHA-256 is recorded so
//   integrity changes are detectable.

/// Capabilities this provider exposes. Deliberately read-only for now.
public enum SevenZipCapability: String, CaseIterable, Sendable {
    case list, read, preview
}

public struct SevenZipExtractionResult: Equatable, Sendable {
    public let completedEntries: Int
    public let expandedBytes: UInt64

    public init(completedEntries: Int, expandedBytes: UInt64) {
        self.completedEntries = completedEntries
        self.expandedBytes = expandedBytes
    }
}

public struct SevenZipExtractionProgress: Equatable, Sendable {
    public let completedEntries: Int
    public let totalEntries: Int
    public let completedBytes: UInt64
    public let totalBytes: UInt64

    public init(completedEntries: Int, totalEntries: Int, completedBytes: UInt64, totalBytes: UInt64) {
        self.completedEntries = completedEntries
        self.totalEntries = totalEntries
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }
}

public enum SevenZipProviderError: Error, Equatable, Sendable {
    /// No validated 7zz binary was found at the known install locations.
    case binaryNotFound
    /// A candidate existed but failed identity/permission/architecture checks.
    case binaryValidationFailed(reason: String)
    /// The version banner could not be read or did not identify arm64.
    case binaryProbeFailed
    /// The child process exceeded its wall-clock budget and was killed.
    case helperTimedOut
    /// The child process was killed after the operation was cancelled.
    case cancelled
    /// The helper could not be spawned or its output could not be drained.
    case helperProtocolFailure
    /// Archive creation failed; carries the helper's stderr diagnostic.
    case creationFailed(message: String)
}

// MARK: - Binary discovery & validation

/// Result of a successful runtime discovery of a trusted 7zz binary.
public struct SevenZipBinaryDiscovery: Equatable, Sendable {
    /// Absolute, symlink-resolved path actually executed.
    public let resolvedPath: String
    public let version: String
    public let architecture: String
    /// SHA-256 of the executable bytes at discovery time (integrity evidence).
    public let sha256: String

    /// Default trusted install locations, probed in order.
    public static let defaultCandidatePaths: [String] = [
        "/opt/homebrew/bin/7zz",
        "/usr/local/bin/7zz",
    ]

    /// Path to a 7zz binary embedded in the app bundle's Resources directory.
    public static var bundleCandidatePath: String? {
        Bundle.main.resourceURL?.appendingPathComponent("Binaries/7zz").path
    }

    /// Discovers and validates a 7zz binary, or returns nil when none qualifies.
    public static func discover(candidatePaths: [String] = defaultCandidatePaths) -> SevenZipBinaryDiscovery? {
        var allPaths: [String] = []
        if let bundlePath = bundleCandidatePath {
            allPaths.append(bundlePath)
        }
        allPaths.append(contentsOf: candidatePaths)
        for candidate in allPaths {
            if let discovery = validate(candidate: candidate) {
                return discovery
            }
        }
        return nil
    }

    static func validate(candidate: String) -> SevenZipBinaryDiscovery? {
        let fileManager = FileManager.default
        guard candidate.hasPrefix("/") else { return nil }
        // Resolve symlinks so the executed identity is the real file, and a
        // symlink cannot redirect execution to an attacker-writable location.
        let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        guard access(resolved, X_OK) == 0 else { return nil }
        // Reject group/world-writable binaries.
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolved),
              let permissions = attributes[.posixPermissions] as? NSNumber else { return nil }
        let mode = permissions.intValue
        guard mode & 0o022 == 0 else { return nil }
        // The resolved target must stay inside a trusted install prefix or the app bundle.
        let bundlePrefix = Bundle.main.resourceURL?.path ?? ""
        guard resolved.hasPrefix("/opt/homebrew/") || resolved.hasPrefix("/usr/local/")
              || (!bundlePrefix.isEmpty && resolved.hasPrefix(bundlePrefix)) else {
            return nil
        }
        guard let hash = sha256(ofFileAt: resolved) else { return nil }
        guard let probe = probeVersion(resolvedPath: resolved) else { return nil }
        return SevenZipBinaryDiscovery(
            resolvedPath: resolved,
            version: probe.version,
            architecture: probe.architecture,
            sha256: hash
        )
    }

    private struct VersionProbe {
        let version: String
        let architecture: String
    }

    private static func probeVersion(resolvedPath: String) -> VersionProbe? {
        let result: SevenZipProcessResult
        do {
            result = try SevenZipProcessRunner().run(
                executablePath: resolvedPath,
                arguments: ["i"],
                timeoutSeconds: 10,
                maximumStdoutBytes: 1 << 20
            )
        } catch {
            return nil
        }
        guard result.exitStatus == 0 else { return nil }
        guard let probe = parseBanner(String(decoding: result.stdout, as: UTF8.self)),
              probe.architecture == "arm64" else { return nil }
        return probe
    }

    /// Parses the leading 7-Zip (z) <version> (<arch>) banner line.
    private static func parseBanner(_ text: String) -> VersionProbe? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(4) {
            guard line.contains("7-Zip") else { continue }
            let scalars = Array(line.unicodeScalars)
            var index = 0
            while index < scalars.count {
                guard isDigit(scalars[index]) else { index += 1; continue }
                var version = ""
                while index < scalars.count, isVersionChar(scalars[index]) {
                    version.unicodeScalars.append(scalars[index])
                    index += 1
                }
                while index < scalars.count, scalars[index] == " " { index += 1 }
                if index < scalars.count, scalars[index] == "(" {
                    var arch = ""
                    index += 1
                    while index < scalars.count, scalars[index] != ")" {
                        arch.unicodeScalars.append(scalars[index])
                        index += 1
                    }
                    if !version.isEmpty, !arch.isEmpty {
                        return VersionProbe(version: version, architecture: arch)
                    }
                }
                index += 1
            }
        }
        return nil
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x30 && scalar.value <= 0x39
    }

    private static func isVersionChar(_ scalar: Unicode.Scalar) -> Bool {
        isDigit(scalar) || scalar == "."
    }

    static func sha256(ofFileAt path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            } catch {
                return nil
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Process runner (posix_spawn, no shell, bounded drain, timeout/cancel)

struct SevenZipProcessResult: Equatable, Sendable {
    let exitStatus: Int32
    let stdout: Data
    let stderr: Data
    let stdoutExceeded: Bool
    let stderrExceeded: Bool
}

enum SevenZipHelperError: Error, Equatable, Sendable {
    case spawnFailed(Int32)
    case timedOut
    case cancelled
    case drainFailure
}

/// Launches a trusted executable with an explicit argv array (never a shell),
/// an allowlisted environment, stdin from /dev/null, a separate process group,
/// concurrently drained stdout/stderr with independent byte budgets, and a
/// monotonic timeout/cancellation loop that kills the whole process group.
struct SevenZipProcessRunner: Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        timeoutSeconds: Int,
        maximumStdoutBytes: Int,
        maximumStderrBytes: Int = 256 * 1024,
        expectedSHA256: String? = nil
    ) throws -> SevenZipProcessResult {
        guard !Task.isCancelled else { throw SevenZipHelperError.cancelled }
        guard access(executablePath, X_OK) == 0 else {
            throw SevenZipProviderError.binaryValidationFailed(reason: "not executable")
        }
        if let expectedSHA256 {
            guard let actual = SevenZipBinaryDiscovery.sha256(ofFileAt: executablePath),
                  actual == expectedSHA256 else {
                throw SevenZipProviderError.binaryValidationFailed(reason: "integrity hash mismatch")
            }
        }

        var stdoutPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdoutPipe) == 0 else { throw SevenZipHelperError.spawnFailed(errno) }
        guard pipe(&stderrPipe) == 0 else {
            closePipe(&stdoutPipe)
            throw SevenZipHelperError.spawnFailed(errno)
        }

        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else {
            closePipe(&stdoutPipe)
            closePipe(&stderrPipe)
            throw SevenZipHelperError.spawnFailed(errno)
        }
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], 2)
        posix_spawn_file_actions_addclose(&actions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&actions, stderrPipe[0])

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            closePipe(&stdoutPipe)
            closePipe(&stderrPipe)
            throw SevenZipHelperError.spawnFailed(errno)
        }
        defer { posix_spawnattr_destroy(&attributes) }
        let flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)

        let argv = [executablePath] + arguments
        var argvVector = argv.map { strdup($0) }
        defer {
            argvVector.forEach { ptr in
                if let ptr {
                    memset_s(ptr, strlen(ptr), 0, strlen(ptr))
                    free(ptr)
                }
            }
        }
        argvVector.append(nil)
        let environment = [
            "LANG=en_US.UTF-8",
            "LC_ALL=en_US.UTF-8",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        var envpVector = environment.map { strdup($0) }
        defer { envpVector.forEach { free($0) } }
        envpVector.append(nil)

        var childPID: pid_t = 0
        let spawnCode = argvVector.withUnsafeMutableBufferPointer { argvPointer in
            envpVector.withUnsafeMutableBufferPointer { envPointer in
                posix_spawn(
                    &childPID,
                    executablePath,
                    &actions,
                    &attributes,
                    argvPointer.baseAddress!,
                    envPointer.baseAddress!
                )
            }
        }
        guard spawnCode == 0 else {
            closePipe(&stdoutPipe)
            closePipe(&stderrPipe)
            throw SevenZipHelperError.spawnFailed(spawnCode)
        }
        // Close the child write ends in the parent so EOF is observed.
        closeWriteEnd(&stdoutPipe)
        closeWriteEnd(&stderrPipe)
        defer {
            closePipe(&stdoutPipe)
            closePipe(&stderrPipe)
        }

        let stdoutDrain = SevenZipBoundedDrain(descriptor: stdoutPipe[0], capacity: maximumStdoutBytes)
        let stderrDrain = SevenZipBoundedDrain(descriptor: stderrPipe[0], capacity: maximumStderrBytes)
        let drainGroup = DispatchGroup()
        let drainQueue = DispatchQueue(
            label: "com.smkzw.MacUnzip.sevenzip-drain",
            attributes: .concurrent
        )
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

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeoutSeconds))
        var waitStatus: Int32 = 0
        var terminal: SevenZipHelperError?
        var exited = false
        while true {
            let waited = waitpid(childPID, &waitStatus, WNOHANG)
            if waited == childPID {
                exited = true
                break
            }
            if waited == -1 {
                if errno == EINTR { continue }
                Self.terminateProcessGroup(childPID)
                terminal = .drainFailure
                break
            }
            if Task.isCancelled {
                Self.terminateProcessGroup(childPID)
                _ = Self.reap(childPID)
                terminal = .cancelled
                break
            }
            if clock.now >= deadline {
                Self.terminateProcessGroup(childPID)
                _ = Self.reap(childPID)
                terminal = .timedOut
                break
            }
            usleep(10_000)
        }

        if drainGroup.wait(timeout: .now() + .seconds(2)) != .success {
            stdoutDrain.cancel()
            stderrDrain.cancel()
            _ = drainGroup.wait(timeout: .now() + .seconds(2))
        }
        // Drains own and close the read-end FDs; prevent double-close in defer.
        stdoutPipe[0] = -1
        stderrPipe[0] = -1

        if let terminal { throw terminal }
        guard exited else { throw SevenZipHelperError.drainFailure }
        let exitCode: Int32
        if (waitStatus & 0x7f) == 0 {
            exitCode = (waitStatus >> 8) & 0xff
        } else {
            exitCode = 128 + (waitStatus & 0x7f)
        }
        return SevenZipProcessResult(
            exitStatus: exitCode,
            stdout: stdoutDrain.snapshotData(),
            stderr: stderrDrain.snapshotData(),
            stdoutExceeded: stdoutDrain.exceeded(),
            stderrExceeded: stderrDrain.exceeded()
        )
    }

    private func closePipe(_ pipe: inout [Int32]) {
        for index in pipe.indices where pipe[index] >= 0 {
            close(pipe[index])
            pipe[index] = -1
        }
    }

    private func closeWriteEnd(_ pipe: inout [Int32]) {
        if pipe.count > 1, pipe[1] >= 0 {
            close(pipe[1])
            pipe[1] = -1
        }
    }

    private static func terminateProcessGroup(_ pid: pid_t) {
        kill(-pid, SIGTERM)
        for _ in 0..<25 {
            if kill(-pid, 0) == -1 && errno == ESRCH { return }
            usleep(10_000)
        }
        kill(-pid, SIGKILL)
    }

    private static func reap(_ pid: pid_t) -> Int32? {
        var status: Int32 = 0
        while true {
            let waited = waitpid(pid, &status, 0)
            if waited == pid { return status }
            if waited == -1 && errno == EINTR { continue }
            return nil
        }
    }
}

private final class SevenZipBoundedDrain: @unchecked Sendable {
    private let descriptor: Int32
    private let capacity: Int
    private let lock = NSLock()
    private var data = Data()
    private var totalBytes = 0
    private var closed = false

    init(descriptor: Int32, capacity: Int) {
        self.descriptor = descriptor
        self.capacity = capacity
    }

    func run() {
        defer { closeOnce() }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                lock.lock()
                totalBytes += count
                let retained = min(count, max(0, capacity - data.count))
                if retained > 0 { data.append(contentsOf: buffer[0..<retained]) }
                lock.unlock()
            } else if count == 0 {
                return
            } else if errno != EINTR {
                return
            }
        }
    }

    func cancel() {
        closeOnce()
    }

    private func closeOnce() {
        lock.lock()
        let shouldClose = !closed
        if shouldClose { closed = true }
        lock.unlock()
        if shouldClose { close(descriptor) }
    }

    func snapshotData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func exceeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return totalBytes > data.count
    }
}

// MARK: - Technical listing parser

/// One entry parsed from 7zz l -slt output.
struct SevenZipParsedEntry: Equatable, Sendable {
    var path = ""
    var isDirectory = false
    var isSymbolicLink = false
    var size: UInt64 = 0
    var packedSize: UInt64 = 0
    var modifiedAt: Date?
    var crc = ""
    var attributes = ""
    var encrypted = false
    var method = ""
}

/// Aggregate signals parsed from the archive-level Properties block.
struct SevenZipArchiveSignals: Equatable, Sendable {
    var isSolid = false
    var isMultipart = false
}

struct SevenZipListingParse: Equatable, Sendable {
    var entries: [SevenZipParsedEntry]
    var signals: SevenZipArchiveSignals
}

/// Parses the stable technical listing produced by 7zz l -slt.
///
/// The technical listing has two sections: an archive-level Properties block
/// (introduced by a "--" line) and the per-file entries (introduced by a
/// "----------" line). Only the section after "----------" holds real entries;
/// the archive block also carries a "Path =" field (the archive path) and must
/// never be mistaken for a member entry.
struct SevenZipListingParser: Sendable {
    private static let entrySeparator = "----------"

    func parse(_ text: String) -> SevenZipListingParse {
        var entries: [SevenZipParsedEntry] = []
        var signals = SevenZipArchiveSignals()
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        let sections = normalized.components(separatedBy: Self.entrySeparator)
        let propertiesSection = sections.count > 1 ? sections[0] : normalized
        let entriesSection = sections.count > 1
            ? sections.dropFirst().joined(separator: Self.entrySeparator)
            : ""

        // Archive-level signals (Solid, split volume) live in the properties block.
        for block in propertiesSection.components(separatedBy: "\n\n") {
            accumulateSignals(from: Self.fields(in: block), into: &signals)
        }

        for block in entriesSection.components(separatedBy: "\n\n") {
            let fields = Self.fields(in: block)
            accumulateSignals(from: fields, into: &signals)
            guard let path = fields["Path"], !path.isEmpty else { continue }
            // The archive Properties block carries a "Type" field; member entries
            // never do. This guards against the archive block leaking in.
            guard fields["Type"] == nil else { continue }
            var entry = SevenZipParsedEntry()
            entry.path = path
            entry.isDirectory = fields["Folder"] == "+" || path.hasSuffix("/")
            entry.size = UInt64(fields["Size"] ?? "") ?? 0
            entry.packedSize = UInt64(fields["Packed Size"] ?? "") ?? 0
            entry.modifiedAt = Self.parseDate(fields["Modified"] ?? "")
            entry.crc = fields["CRC"] ?? ""
            entry.attributes = fields["Attributes"] ?? ""
            entry.encrypted = fields["Encrypted"] == "+"
            entry.method = fields["Method"] ?? ""
            // 7zz technical listing flags symlinks via a Symbolic Link field.
            // Unix attributes may also appear as mode-like tokens (e.g. lrwxrwxrwx).
            let attributes = entry.attributes
            entry.isSymbolicLink =
                fields["Symbolic Link"] != nil
                || fields["Symbolik Link"] != nil
                || attributes.hasPrefix("l")
                || attributes.contains(" lrwx")
            entries.append(entry)
        }
        return SevenZipListingParse(entries: entries, signals: signals)
    }

    private func accumulateSignals(
        from fields: [String: String],
        into signals: inout SevenZipArchiveSignals
    ) {
        if fields["Method"] == "Solid" || fields["Solid"] == "+" {
            signals.isSolid = true
        }
        if fields["IsVolume"] == "+" {
            signals.isMultipart = true
        }
    }

    static func fields(in block: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in block.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            fields[key] = value
        }
        return fields
    }

    static func parseDate(_ value: String) -> Date? {
        var trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // 7zz appends fractional seconds (e.g. "2026-07-27 01:21:26.6364049");
        // drop the fraction so the fixed formats below can parse the timestamp.
        if let dot = trimmed.firstIndex(of: ".") {
            trimmed = String(trimmed[..<dot])
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Provider

public actor SevenZipProvider: ArchiveProvider {
    private let binaryPath: String
    private let binarySHA256: String?
    private let listingTimeoutSeconds: Int
    private let extractionTimeoutSeconds: Int
    private let listingEntryLimit: Int
    private let maximumStdoutListingBytes: Int
    private var archiveURL: URL?
    private var entriesByID: [ArchiveEntryID: ArchiveEntrySnapshot] = [:]
    private var isSolidArchive = false
    private var looksLikeMultipartVolume = false
    private var currentPassword: SecurePassword?

    /// The capabilities this provider exposes. Read-only by design.
    public static let capabilities: Set<SevenZipCapability> = [.list, .read, .preview]

    /// - Parameter binaryPath: a validated 7zz path. Use makeValidated() to
    ///   discover and validate the system binary first.
    public init(
        binaryPath: String,
        binarySHA256: String? = nil,
        listingTimeoutSeconds: Int = 30,
        extractionTimeoutSeconds: Int = 600,
        listingEntryLimit: Int = 1_000_000
    ) {
        self.binaryPath = binaryPath
        self.binarySHA256 = binarySHA256
        self.listingTimeoutSeconds = listingTimeoutSeconds
        self.extractionTimeoutSeconds = extractionTimeoutSeconds
        self.listingEntryLimit = listingEntryLimit
        // Listing output is bounded so a hostile archive cannot exhaust memory.
        self.maximumStdoutListingBytes = 256 * 1024 * 1024
    }

    /// Discovers and validates the system 7zz binary, then constructs a provider.
    /// Throws SevenZipProviderError.binaryNotFound when no binary qualifies.
    public static func makeValidated() throws -> SevenZipProvider {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw SevenZipProviderError.binaryNotFound
        }
        return SevenZipProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
    }

    /// True when the opened archive uses solid compression, where extracting a
    /// single entry may require decoding preceding data and can be slow.
    public var isSolid: Bool { isSolidArchive }

    /// True when the source name matches a split-volume pattern (.001/.7z.001).
    public var isMultipartVolume: Bool { looksLikeMultipartVolume }

    public func open(url: URL) throws -> ArchiveDocumentSnapshot {
        try openInternal(url: url, password: nil)
    }

    public func openWithPassword(url: URL, password: String) throws -> ArchiveDocumentSnapshot {
        try openInternal(url: url, password: password)
    }

    private func openInternal(url: URL, password: String?) throws -> ArchiveDocumentSnapshot {
        archiveURL = nil
        entriesByID = [:]
        isSolidArchive = false
        currentPassword = password.map { SecurePassword($0) }
        looksLikeMultipartVolume = Self.looksLikeSplitVolume(url)

        var arguments = ["l", "-slt"]
        if let password {
            // 7zz has no stdin/askpass password interface; the password is briefly visible in argv (ps).
            arguments.append("-p\(password)")
        }
        arguments.append(url.path)
        let result = try invoke(
            arguments: arguments,
            timeoutSeconds: listingTimeoutSeconds,
            maximumStdoutBytes: maximumStdoutListingBytes
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: true)
        }
        guard !result.stdoutExceeded else { throw ArchiveError.resourceLimit }

        let parse = SevenZipListingParser().parse(String(decoding: result.stdout, as: UTF8.self))
        isSolidArchive = parse.signals.isSolid
        looksLikeMultipartVolume = parse.signals.isMultipart || looksLikeMultipartVolume

        guard parse.entries.count <= listingEntryLimit else {
            throw ArchiveError.resourceLimit
        }

        var snapshots: [ArchiveEntrySnapshot] = []
        snapshots.reserveCapacity(parse.entries.count)
        for parsed in parse.entries {
            let normalized = parsed.path.replacingOccurrences(of: "\\", with: "/")
            let isDirectory = parsed.isDirectory || normalized.hasSuffix("/")
            let validationPath = isDirectory && normalized.hasSuffix("/")
                ? String(normalized.dropLast())
                : normalized
            do {
                try ArchivePathPolicy().validate(validationPath)
            } catch {
                throw ArchiveError.unsafePath
            }
            // Reject symlink members at open so listing never presents an entry
            // that extractAll would refuse, and so `7zz x` never gets a chance
            // to write through a symlink before post-hoc verification.
            if parsed.isSymbolicLink {
                throw ArchiveError.unsafePath
            }
            let entry = ArchiveEntry(
                id: ArchiveEntryID(),
                rawPath: ArchivePathBytes(Array(parsed.path.utf8)),
                displayPath: validationPath
            )
            snapshots.append(ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: parsed.packedSize,
                uncompressedSize: parsed.size,
                modifiedAt: parsed.modifiedAt,
                isDirectory: isDirectory,
                isSymbolicLink: parsed.isSymbolicLink,
                isEncrypted: parsed.encrypted,
                usesUTF8FileName: true
            ))
        }

        archiveURL = url
        entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
        return ArchiveDocumentSnapshot(sourceURL: url, format: .sevenZip, entries: snapshots)
    }

    public func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data {
        guard let snapshot = entriesByID[id], let archiveURL else {
            throw ArchiveError.helperFailed
        }
        guard !snapshot.isDirectory else { throw ArchiveError.unsafePath }
        if snapshot.isEncrypted && currentPassword == nil { throw ArchiveError.passwordRequired }
        guard snapshot.uncompressedSize <= maximumBytes,
              snapshot.uncompressedSize <= UInt64(Int.max) else {
            throw ArchiveError.resourceLimit
        }
        let stdoutLimit = Int(clamping: maximumBytes) == Int.max ? Int.max : Int(clamping: maximumBytes) + 1
        var arguments = ["x", "-so", "-y", "-spd", "-bso0", "-bsp0"]
        if let password = currentPassword {
            // 7zz has no stdin/askpass password interface; the password is briefly visible in argv (ps).
            password.withCString { ptr in
                arguments.append("-p" + String(cString: ptr))
            }
        }
        arguments.append(archiveURL.path)
        arguments.append("-i!" + String(decoding: snapshot.entry.rawPath.bytes, as: UTF8.self))
        let result = try invoke(
            arguments: arguments,
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: stdoutLimit
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: false)
        }
        guard UInt64(result.stdout.count) == snapshot.uncompressedSize else {
            throw ArchiveError.corruptedArchive
        }
        return result.stdout
    }

    public func materializeEntry(
        id: ArchiveEntryID,
        under rootURL: URL,
        budget: ResourceBudget = .previewDefault
    ) throws -> URL {
        try Task.checkCancellation()
        guard let snapshot = entriesByID[id] else { throw ArchiveError.helperFailed }
        let decision = budget.evaluate(ResourceEstimate(
            compressedBytes: snapshot.compressedSize,
            expandedBytes: snapshot.uncompressedSize,
            entries: 1,
            depth: 1
        ))
        guard decision == .allow else { throw ArchiveError.resourceLimit }
        let data = try readEntry(id: id, maximumBytes: budget.maxExpandedBytes)
        try Task.checkCancellation()
        let output = try SecureFileMaterializer(rootURL: rootURL).write(
            data,
            relativePath: snapshot.entry.displayPath
        )
        try Task.checkCancellation()
        return output
    }

    /// Extracts every entry under rootURL using 7zz x, after pre-validating
    /// paths, rejecting encrypted archives and symlink entries, enforcing the
    /// resource budget, and post-validating that nothing escaped the root and no
    /// symlink was published.
    public func extractAll(
        under rootURL: URL,
        budget: ResourceBudget = .extractionDefault,
        progress: @Sendable (SevenZipExtractionProgress) -> Void = { _ in }
    ) throws -> SevenZipExtractionResult {
        try Task.checkCancellation()
        guard let archiveURL else { throw ArchiveError.helperFailed }
        let snapshots = entriesByID.values.sorted {
            $0.entry.displayPath < $1.entry.displayPath
        }
        if snapshots.contains(where: { $0.isEncrypted }) && currentPassword == nil {
            throw ArchiveError.passwordRequired
        }
        // Refuse to start a tree extract when any member is a symlink: `7zz x`
        // would write through it before post-hoc verification could run.
        guard !snapshots.contains(where: { $0.isSymbolicLink }) else {
            throw ArchiveError.unsafePath
        }
        try validateExtractionPaths(snapshots)

        var compressedBytes: UInt64 = 0
        var expandedBytes: UInt64 = 0
        var maximumDepth: UInt64 = 0
        for snapshot in snapshots {
            let (nextCompressed, compressedOverflow) = compressedBytes
                .addingReportingOverflow(snapshot.compressedSize)
            let (nextExpanded, expandedOverflow) = expandedBytes
                .addingReportingOverflow(snapshot.uncompressedSize)
            guard !compressedOverflow, !expandedOverflow else { throw ArchiveError.resourceLimit }
            compressedBytes = nextCompressed
            expandedBytes = nextExpanded
            maximumDepth = max(
                maximumDepth,
                UInt64(snapshot.entry.displayPath.split(separator: "/").count)
            )
        }
        guard budget.evaluate(ResourceEstimate(
            compressedBytes: compressedBytes,
            expandedBytes: expandedBytes,
            entries: UInt64(snapshots.count),
            depth: maximumDepth
        )) == .allow else {
            throw ArchiveError.resourceLimit
        }

        progress(SevenZipExtractionProgress(
            completedEntries: 0,
            totalEntries: snapshots.count,
            completedBytes: 0,
            totalBytes: expandedBytes
        ))

        // Extract into a private staging directory inside rootURL, then
        // re-publish through the secure materializer with validated paths.
        let stagingURL = rootURL.appending(
            path: ".sevenzip-staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var published = false
        defer {
            if !published { try? FileManager.default.removeItem(at: stagingURL) }
        }

        var extractArguments = ["x", "-y", "-bso0", "-bsp0"]
        if let password = currentPassword {
            password.withCString { ptr in
                extractArguments.append("-p" + String(cString: ptr))
            }
        }
        extractArguments.append("-o\(stagingURL.path)")
        extractArguments.append(archiveURL.path)
        let result = try invoke(
            arguments: extractArguments,
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: 1 << 20
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result, forListing: false)
        }
        try Task.checkCancellation()
        let stagingSize = FileManager.default
            .enumerator(at: stagingURL, includingPropertiesForKeys: [.fileSizeKey])?
            .compactMap { (try? ($0 as? URL)?.resourceValues(forKeys: [.fileSizeKey]))?.fileSize }
            .reduce(0, +) ?? 0
        guard UInt64(stagingSize) <= budget.maxExpandedBytes else {
            throw ArchiveError.resourceLimit
        }
        try verifyNoSymlinksAndContained(under: stagingURL)
        try Task.checkCancellation()

        let materializer = SecureFileMaterializer(rootURL: rootURL)
        var completedEntries = 0
        var writtenBytes: UInt64 = 0
        for snapshot in snapshots {
            try Task.checkCancellation()
            let path = snapshot.entry.displayPath
            if snapshot.isDirectory {
                _ = try materializer.createDirectory(relativePath: path)
            } else {
                let stagedFile = stagingURL.appending(path: path)
                var fileBytes: UInt64 = 0
                _ = try materializer.write(relativePath: path) { writer in
                    let fd = stagedFile.withUnsafeFileSystemRepresentation { p -> Int32 in
                        guard let p else { return -1 }
                        return Darwin.open(p, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                    }
                    guard fd >= 0 else {
                        throw SevenZipProviderError.helperProtocolFailure
                    }
                    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                    defer { try? handle.close() }
                    while true {
                        try Task.checkCancellation()
                        let chunk: Data
                        do {
                            chunk = try handle.read(upToCount: 1 << 20) ?? Data()
                        } catch {
                            throw SevenZipProviderError.helperProtocolFailure
                        }
                        if chunk.isEmpty { break }
                        try writer.write(chunk)
                        fileBytes += UInt64(chunk.count)
                    }
                }
                if snapshot.uncompressedSize > 0, fileBytes != snapshot.uncompressedSize {
                    throw ArchiveError.corruptedArchive
                }
                writtenBytes += fileBytes
            }
            completedEntries += 1
            progress(SevenZipExtractionProgress(
                completedEntries: completedEntries,
                totalEntries: snapshots.count,
                completedBytes: writtenBytes,
                totalBytes: expandedBytes
            ))
        }
        published = true
        try? FileManager.default.removeItem(at: stagingURL)
        return SevenZipExtractionResult(
            completedEntries: completedEntries,
            expandedBytes: writtenBytes
        )
    }

    // MARK: - Creation

    public func createArchive(
        at outputURL: URL,
        inputs: [URL],
        password: String?
    ) async throws {
        try Task.checkCancellation()
        let stageURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(outputURL.lastPathComponent).awb_stage_\(UUID().uuidString)")
        var stagePublished = false
        defer { if !stagePublished { try? FileManager.default.removeItem(at: stageURL) } }

        var arguments = ["a", "-t7z", "-mx=5", "-spd"]
        if let password, !password.isEmpty {
            arguments.append("-mhe=on")
            // 7zz has no stdin/askpass password interface; the password is briefly visible in argv (ps).
            arguments.append("-p\(password)")
        }
        arguments.append(stageURL.path)
        for input in inputs {
            arguments.append(input.path)
        }
        let result = try invoke(
            arguments: arguments,
            timeoutSeconds: extractionTimeoutSeconds,
            maximumStdoutBytes: 1 << 20
        )
        guard result.exitStatus == 0 else {
            let message = String(data: result.stderr, encoding: .utf8) ?? "7z creation failed"
            throw SevenZipProviderError.creationFailed(message: message)
        }
        try Task.checkCancellation()
        try syncFile(at: stageURL)
        try publishAtomically(stageURL: stageURL, outputURL: outputURL)
        stagePublished = true
    }

    // MARK: Private helpers

    private func invoke(
        arguments: [String],
        timeoutSeconds: Int,
        maximumStdoutBytes: Int
    ) throws -> SevenZipProcessResult {
        do {
            return try SevenZipProcessRunner().run(
                executablePath: binaryPath,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds,
                maximumStdoutBytes: maximumStdoutBytes,
                expectedSHA256: binarySHA256
            )
        } catch let error as SevenZipHelperError {
            switch error {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw SevenZipProviderError.helperTimedOut
            case .spawnFailed, .drainFailure:
                throw ArchiveError.helperFailed
            }
        }
    }

    private func mapError(
        result: SevenZipProcessResult,
        forListing: Bool
    ) -> ArchiveError {
        let text = (String(decoding: result.stderr, as: UTF8.self)
            + "\n"
            + String(decoding: result.stdout, as: UTF8.self)).lowercased()
        if text.contains("wrong password")
            || text.contains("enter password")
            || text.contains("cannot open encrypted archive") {
            return .passwordRequired
        }
        if text.contains("unsupported encryption") {
            return .unsupportedEncryption
        }
        if text.contains("unsupported method") {
            return .unsupportedMethod
        }
        if text.contains("cannot open archive")
            || text.contains("no more files")
            || text.contains("unexpected end") {
            return .missingVolume
        }
        if text.contains("data error")
            || text.contains("crc failed")
            || text.contains("headers error")
            || text.contains("is not supported archive") {
            return .corruptedArchive
        }
        return .helperFailed
    }

    private func validateExtractionPaths(_ snapshots: [ArchiveEntrySnapshot]) throws {
        var canonicalPaths: Set<String> = []
        for snapshot in snapshots {
            let canonical = snapshot.entry.displayPath
                .decomposedStringWithCanonicalMapping
                .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard canonicalPaths.insert(canonical).inserted else {
                throw ArchiveError.unsafePath
            }
        }
    }

    private static func looksLikeSplitVolume(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        guard let range = name.range(of: "[.](7z|zip|rar)?[.]?[0-9][0-9][0-9]+$", options: .regularExpression) else {
            return false
        }
        return range.lowerBound != name.startIndex
    }

    private func verifyNoSymlinksAndContained(under root: URL) throws {
        let rootPath = root.standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else { return }
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ArchiveError.unsafePath }
            guard fileURL.standardizedFileURL.path.hasPrefix(rootPath + "/") else {
                throw ArchiveError.unsafePath
            }
        }
    }

    private func syncFile(at url: URL) throws {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fd >= 0 else {
            throw SevenZipProviderError.creationFailed(message: "open for fsync failed: \(errno)")
        }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else {
            throw SevenZipProviderError.creationFailed(message: "fsync failed: \(errno)")
        }
    }

    private func publishAtomically(stageURL: URL, outputURL: URL) throws {
        let linkResult = stageURL.withUnsafeFileSystemRepresentation { stagePath in
            outputURL.withUnsafeFileSystemRepresentation { outputPath in
                guard let stagePath, let outputPath else { return Int32(-1) }
                return Darwin.link(stagePath, outputPath)
            }
        }
        guard linkResult == 0 else {
            throw SevenZipProviderError.creationFailed(message: "link failed: \(errno)")
        }
        try? FileManager.default.removeItem(at: stageURL)
        let dirFD = outputURL.deletingLastPathComponent().withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_DIRECTORY)
        }
        if dirFD >= 0 {
            fsync(dirFD)
            Darwin.close(dirFD)
        }
    }
}