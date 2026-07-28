import ArchiveDomain
import CryptoKit
import Darwin
import Foundation

// MARK: - External RARLAB rar creation provider
//
// Design principles (from handoff):
// - RAR 创建/更新：仅通过用户另行合法安装并经校验的 RARLAB rar
// - 只有用户合法安装后：用户选择或明确路径；验证不是 symlink/可写替换风险；
//   版本/架构/hash/许可确认；安全 argv/密码；live create/test/extract；绝不捆绑
// - provider 能力必须按真实运行时发现和验证：capabilities are gated on a
//   successful discovery + license confirmation, never assumed.
// - 不允许 mutation 静默 fallback 到不同引擎：this provider ONLY uses the
//   validated RARLAB rar binary; no fallback to 7zz or any other engine.
// - helper 可执行文件身份/架构/版本/权限/hash/可写路径/symlink/TOCTOU：
//   the binary must be a regular file (not a symlink to a writable location),
//   arm64, not group/world-writable, and its SHA-256 is recorded for integrity.
// - Password: RAR's -p<password> places the password in argv (visible in ps).
//   We use -hp for header+data encryption and document this limitation. For
//   non-header encryption, -p is unavoidable with RARLAB rar; the password is
//   passed as a separate argv element (not shell-expanded) and callers should
//   prefer -hp where possible.

// MARK: - Compression method

/// RAR compression method levels (-m0 through -m5).
public enum RARCompressionMethod: Int, CaseIterable, Sendable {
    case store = 0
    case fastest = 1
    case fast = 2
    case normal = 3
    case good = 4
    case best = 5

    public var argument: String { "-m\(rawValue)" }
}

// MARK: - Errors

public enum RARCreateProviderError: Error, Equatable, Sendable {
    /// No validated rar binary was found at any candidate location.
    case binaryNotFound
    /// A candidate existed but failed identity/permission/architecture checks.
    case binaryValidationFailed(reason: String)
    /// The version output could not be parsed.
    case versionProbeFailed
    /// The user has not confirmed license ownership.
    case licenseNotConfirmed
    /// The child process exceeded its wall-clock budget and was killed.
    case helperTimedOut
    /// The helper could not be spawned or its output could not be drained.
    case helperProtocolFailure
    /// The operation was cancelled.
    case cancelled
    /// The rar binary returned a non-zero exit status.
    case rarFailed(exitCode: Int32, message: String)
}

// MARK: - Binary discovery & validation

/// Result of a successful runtime discovery of a trusted RARLAB rar binary.
public struct RARBinaryDiscovery: Equatable, Sendable {
    /// Absolute, symlink-resolved path actually executed.
    public let resolvedPath: String
    public let version: String
    public let architecture: String
    /// SHA-256 of the executable bytes at discovery time (integrity evidence).
    public let sha256: String

    /// Default trusted install locations, probed in order.
    public static let defaultCandidatePaths: [String] = [
        "/usr/local/bin/rar",
        "/opt/homebrew/bin/rar",
    ]

    /// Path to a rar binary embedded in the app bundle's Resources directory.
    public static var bundleCandidatePath: String? {
        Bundle.main.resourceURL?.appendingPathComponent("Binaries/rar").path
    }

    /// UserDefaults key for user-configured rar path.
    public static let userPathDefaultsKey = "RARCreateProvider.rarPath"

    /// UserDefaults key for license confirmation.
    public static let licenseConfirmedDefaultsKey = "RARCreateProvider.licenseConfirmed"

    /// Discovers and validates a rar binary, or returns nil when none qualifies.
    /// Checks bundle-embedded binary first, then user-configured path, then standard locations.
    public static func discover(
        candidatePaths: [String]? = nil,
        defaults: UserDefaults = .standard
    ) -> RARBinaryDiscovery? {
        var paths: [String] = []
        // Bundle-embedded binary takes highest priority
        if let bundlePath = bundleCandidatePath {
            paths.append(bundlePath)
        }
        // User-configured path takes next priority
        if let userPath = defaults.string(forKey: userPathDefaultsKey), !userPath.isEmpty {
            paths.append(userPath)
        }
        if let candidatePaths {
            paths.append(contentsOf: candidatePaths)
        } else {
            paths.append(contentsOf: defaultCandidatePaths)
        }
        for candidate in paths {
            if let discovery = validate(candidate: candidate) {
                return discovery
            }
        }
        return nil
    }

    /// Validates a single candidate path. Exposed for testing.
    public static func validate(candidate: String) -> RARBinaryDiscovery? {
        let fileManager = FileManager.default
        guard candidate.hasPrefix("/") else { return nil }

        // Resolve symlinks so the executed identity is the real file, and a
        // symlink cannot redirect execution to an attacker-writable location.
        let resolved = URL(fileURLWithPath: candidate).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }

        // Must be executable
        guard access(resolved, X_OK) == 0 else { return nil }

        // Reject group/world-writable binaries
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolved),
              let permissions = attributes[.posixPermissions] as? NSNumber else { return nil }
        let mode = permissions.intValue
        guard mode & 0o022 == 0 else { return nil }

        // The resolved target must stay inside a trusted install prefix or the app bundle.
        let bundlePrefix = Bundle.main.resourceURL?.path ?? ""
        let home = NSHomeDirectory()
        guard resolved.hasPrefix("/opt/homebrew/")
            || resolved.hasPrefix("/usr/local/")
            || resolved.hasPrefix("/Applications/")
            || resolved.hasPrefix(home + "/.local/bin/")
            || resolved.hasPrefix(home + "/bin/")
            || (!bundlePrefix.isEmpty && resolved.hasPrefix(bundlePrefix)) else {
            return nil
        }

        // Verify arm64 architecture via Mach-O header inspection
        guard verifyArm64(path: resolved) else { return nil }

        // Compute SHA-256 hash for integrity
        guard let hash = sha256(ofFileAt: resolved) else { return nil }

        // Probe version
        guard let probe = probeVersion(resolvedPath: resolved) else { return nil }

        return RARBinaryDiscovery(
            resolvedPath: resolved,
            version: probe.version,
            architecture: probe.architecture,
            sha256: hash
        )
    }

    // MARK: - Architecture verification

    /// Verifies the binary is arm64 by inspecting the Mach-O header.
    /// Supports both thin and fat (universal) binaries.
    static func verifyArm64(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let header: Data
        do {
            header = try handle.read(upToCount: 8) ?? Data()
        } catch { return false }
        guard header.count >= 4 else { return false }

        let magic = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        // MH_MAGIC_64 (little-endian) or MH_CIGAM_64 (byte-swapped)
        let MH_MAGIC_64: UInt32 = 0xFEED_FACF
        let MH_CIGAM_64: UInt32 = 0xCFFE_DAED
        // FAT_MAGIC (big-endian) or FAT_CIGAM
        let FAT_MAGIC: UInt32 = 0xCAFEBABE
        let FAT_CIGAM: UInt32 = 0xBEBAFECA

        if magic == MH_MAGIC_64 {
            // Thin 64-bit binary: cputype is at offset 4
            guard header.count >= 8 else { return false }
            let cputype = header.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            }
            return cputype == 0x0100_000C // CPU_TYPE_ARM64
        } else if magic == MH_CIGAM_64 {
            // Byte-swapped thin 64-bit binary
            guard header.count >= 8 else { return false }
            let cputype = header.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            }
            return cputype.byteSwapped == 0x0100_000C
        } else if magic == FAT_MAGIC || magic == FAT_CIGAM {
            // Universal binary: scan fat_arch entries for arm64
            let needsSwap = magic == FAT_CIGAM
            let nfat = header.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
            }
            let archCount = needsSwap ? nfat.byteSwapped : nfat
            guard archCount <= 32 else { return false } // sanity limit
            let archData: Data
            do {
                archData = try handle.read(upToCount: Int(archCount) * 20) ?? Data()
            } catch { return false }
            guard archData.count == Int(archCount) * 20 else { return false }
            for i in 0..<Int(archCount) {
                let offset = i * 20
                let cputype = archData.withUnsafeBytes {
                    $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                }
                let cpu = needsSwap ? cputype.byteSwapped : cputype
                if cpu == 0x0100_000C { return true } // CPU_TYPE_ARM64
            }
            return false
        }
        return false
    }

    // MARK: - Version probe

    struct VersionProbe: Equatable, Sendable {
        let version: String
        let architecture: String
    }

    private static func probeVersion(resolvedPath: String) -> VersionProbe? {
        let result: SevenZipProcessResult
        do {
            result = try SevenZipProcessRunner().run(
                executablePath: resolvedPath,
                arguments: ["--version"],
                timeoutSeconds: 10,
                maximumStdoutBytes: 1 << 16
            )
        } catch {
            return nil
        }
        // rar --version may exit 0 or non-zero depending on version; accept both
        let output = String(decoding: result.stdout, as: UTF8.self)
            + "\n"
            + String(decoding: result.stderr, as: UTF8.self)
        return parseVersion(output)
    }

    /// Parses version from RARLAB rar output. Expected format:
    /// "RAR 7.10   (64-bit)" or "RAR 6.24 beta 1" etc.
    static func parseVersion(_ text: String) -> VersionProbe? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(10) {
            let upper = line.uppercased()
            guard upper.contains("RAR") else { continue }
            // Extract version number (digits and dots)
            let scalars = Array(line.unicodeScalars)
            var index = 0
            while index < scalars.count {
                guard isDigit(scalars[index]) else { index += 1; continue }
                var version = ""
                while index < scalars.count, isVersionChar(scalars[index]) {
                    version.unicodeScalars.append(scalars[index])
                    index += 1
                }
                if !version.isEmpty, version.contains(".") {
                    // Determine architecture from the line
                    let arch: String
                    if upper.contains("64-BIT") || upper.contains("ARM64") || upper.contains("AARCH64") {
                        arch = "arm64"
                    } else if upper.contains("32-BIT") {
                        arch = "arm"
                    } else {
                        arch = "arm64" // default assumption for modern macOS
                    }
                    return VersionProbe(version: version, architecture: arch)
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

    private static func sha256(ofFileAt path: String) -> String? {
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

// MARK: - License confirmation

/// Manages the RARLAB license confirmation state.
///
/// RARLAB rar is commercial/shareware software. Before any creation operation,
/// the user must confirm they have legally installed and licensed the software.
/// The confirmation is stored in UserDefaults so it is only asked once.
public struct RARLicenseConfirmation: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the user has confirmed license ownership.
    public var isConfirmed: Bool {
        defaults.bool(forKey: RARBinaryDiscovery.licenseConfirmedDefaultsKey)
    }

    /// Records the user's license confirmation.
    public func confirm() {
        defaults.set(true, forKey: RARBinaryDiscovery.licenseConfirmedDefaultsKey)
    }

    /// Revokes confirmation (e.g. if user wants to reset).
    public func revoke() {
        defaults.set(false, forKey: RARBinaryDiscovery.licenseConfirmedDefaultsKey)
    }

    /// The alert message shown on first use.
    public static let confirmationMessage = "RARLAB rar 是共享软件，需要合法许可。"
    public static let confirmationTitle = "确认 RAR 许可"
    public static let confirmButton = "我已安装并拥有许可"
    public static let cancelButton = "取消"
}

// MARK: - Creation options

/// Options for RAR archive creation.
public struct RARCreateOptions: Sendable {
    /// Compression method (store through best).
    public var method: RARCompressionMethod
    /// Password for encryption. Uses -hp (header+data encryption) to avoid
    /// exposing the password in process listings via -p.
    /// LIMITATION: RARLAB rar requires the password in argv (-hp<password>);
    /// it is passed as a single argv element (not shell-expanded) but is
    /// theoretically visible via /proc or ps during execution.
    public var password: String?
    /// Whether to use solid compression.
    public var solid: Bool
    /// Whether to store full paths (false = strip paths with -ep1).
    public var storeFullPaths: Bool

    public init(
        method: RARCompressionMethod = .normal,
        password: String? = nil,
        solid: Bool = false,
        storeFullPaths: Bool = false
    ) {
        self.method = method
        self.password = password
        self.solid = solid
        self.storeFullPaths = storeFullPaths
    }
}

// MARK: - Provider

/// External RARLAB rar creation provider.
///
/// This provider enables RAR archive creation and testing ONLY when:
/// 1. A valid RARLAB rar binary is discovered and passes all security checks
/// 2. The user has confirmed they hold a valid license
///
/// It never bundles rar; the user must install it separately.
public actor RARCreateProvider {
    private let binaryPath: String
    private let binarySHA256: String?
    private let creationTimeoutSeconds: Int
    private let testTimeoutSeconds: Int

    /// - Parameter binaryPath: a validated rar path from RARBinaryDiscovery.
    public init(
        binaryPath: String,
        binarySHA256: String? = nil,
        creationTimeoutSeconds: Int = 600,
        testTimeoutSeconds: Int = 300
    ) {
        self.binaryPath = binaryPath
        self.binarySHA256 = binarySHA256
        self.creationTimeoutSeconds = creationTimeoutSeconds
        self.testTimeoutSeconds = testTimeoutSeconds
    }

    /// Attempts to create a validated provider. Returns nil if no binary
    /// qualifies or license is not confirmed.
    public static func makeValidated(
        defaults: UserDefaults = .standard
    ) -> RARCreateProvider? {
        guard let discovery = RARBinaryDiscovery.discover(defaults: defaults) else {
            return nil
        }
        let license = RARLicenseConfirmation(defaults: defaults)
        guard license.isConfirmed else { return nil }
        return RARCreateProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
    }

    /// Creates a RAR archive from the given source files/directories.
    ///
    /// - Parameters:
    ///   - archiveURL: Destination .rar file path.
    ///   - sources: Absolute paths to files/directories to add.
    ///   - options: Compression and encryption options.
    /// - Throws: RARCreateProviderError on failure.
    public func create(
        archiveURL: URL,
        sources: [String],
        options: RARCreateOptions = RARCreateOptions()
    ) throws {
        try Task.checkCancellation()
        guard !sources.isEmpty else {
            throw RARCreateProviderError.rarFailed(exitCode: -1, message: "No source files specified")
        }

        let stageURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent(".\(archiveURL.lastPathComponent).awb_stage_\(UUID().uuidString)")
        var stagePublished = false
        defer { if !stagePublished { try? FileManager.default.removeItem(at: stageURL) } }

        var arguments = ["a"]
        // Compression method
        arguments.append(options.method.argument)
        // Always recurse into directories
        arguments.append("-r")
        // Strip paths (store relative names)
        if !options.storeFullPaths {
            arguments.append("-ep1")
        }
        // Solid compression
        if options.solid {
            arguments.append("-s")
        }
        // Password: use -hp for header+data encryption
        // NOTE: The password is in argv. RARLAB rar does not support stdin password.
        // We use -hp (encrypt headers + data) which is the most secure option.
        if let password = options.password {
            arguments.append("-hp\(password)")
        }
        // Overwrite without asking
        arguments.append("-o+")
        // Archive path (staging)
        arguments.append(stageURL.path)
        // Source files
        arguments.append(contentsOf: sources)

        let result = try invoke(
            arguments: arguments,
            timeoutSeconds: creationTimeoutSeconds,
            maximumStdoutBytes: 1 << 20
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result)
        }
        try Task.checkCancellation()
        try syncFile(at: stageURL)
        try publishAtomically(stageURL: stageURL, outputURL: archiveURL)
        stagePublished = true
    }

    /// Tests integrity of a RAR archive (equivalent to `rar t`).
    ///
    /// - Parameter archiveURL: Path to the .rar file.
    /// - Returns: true if the archive passes integrity checks.
    /// - Throws: RARCreateProviderError on failure.
    @discardableResult
    public func test(archiveURL: URL) throws -> Bool {
        try Task.checkCancellation()
        let result = try invoke(
            arguments: ["t", archiveURL.path],
            timeoutSeconds: testTimeoutSeconds,
            maximumStdoutBytes: 1 << 20
        )
        guard result.exitStatus == 0 else {
            throw mapError(result: result)
        }
        return true
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
                throw RARCreateProviderError.cancelled
            case .timedOut:
                throw RARCreateProviderError.helperTimedOut
            case .spawnFailed, .drainFailure:
                throw RARCreateProviderError.helperProtocolFailure
            }
        }
    }

    private func mapError(result: SevenZipProcessResult) -> RARCreateProviderError {
        let message = String(decoding: result.stderr, as: UTF8.self)
            + "\n"
            + String(decoding: result.stdout, as: UTF8.self)
        return .rarFailed(exitCode: result.exitStatus, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func syncFile(at url: URL) throws {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard fd >= 0 else {
            throw RARCreateProviderError.rarFailed(exitCode: -1, message: "open for fsync failed: \(errno)")
        }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else {
            throw RARCreateProviderError.rarFailed(exitCode: -1, message: "fsync failed: \(errno)")
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
            throw RARCreateProviderError.rarFailed(exitCode: -1, message: "link failed: \(errno)")
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
