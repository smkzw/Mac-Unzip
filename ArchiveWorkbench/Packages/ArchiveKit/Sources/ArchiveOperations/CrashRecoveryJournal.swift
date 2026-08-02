import ArchiveDomain
import Darwin
import Foundation

/// A crash-recovery journal written alongside archive editing operations.
///
/// The journal records enough state to detect an interrupted save and either
/// complete it (recovery) or discard the staging file (deletion). It is
/// written *before* any mutation begins and removed *after* the atomic
/// publish succeeds, so a crash at any point leaves either no journal (save
/// never started or fully completed) or an ``State/inProgress`` journal (save
/// was interrupted).
///
/// Per the design contract, recovery is **never** automatic: the user must
/// explicitly choose to recover or discard.
public struct CrashRecoveryJournal: Codable, Equatable, Sendable {
    public enum State: String, Codable, Equatable, Sendable {
        case inProgress = "in_progress"
        case committed
        case rolledBack = "rolled_back"
    }

    public static let currentVersion = 1
    public static let fileExtension = "awb-journal"

    public let version: Int
    public let operation: String
    public let sourceArchive: String
    public let stagingFile: String
    public let startedAt: String
    public let pendingChanges: [String]
    public var state: State

    public init(
        sourceArchive: URL,
        stagingFile: URL,
        pendingChanges: [PendingChange],
        state: State = .inProgress
    ) {
        version = Self.currentVersion
        operation = "save"
        self.sourceArchive = sourceArchive.path
        self.stagingFile = stagingFile.path
        startedAt = ISO8601DateFormatter().string(from: Date())
        self.pendingChanges = Self.sanitize(pendingChanges)
        self.state = state
    }

    /// Returns sanitized, human-readable descriptions of pending changes.
    ///
    /// Source file URLs are intentionally omitted so the journal never leaks
    /// private filesystem paths or file names outside the archive.
    public static func sanitize(_ changes: [PendingChange]) -> [String] {
        changes.map { change in
            switch change {
            case let .add(_, destinationPath):
                "add:\(destinationPath)"
            case let .remove(entryPath):
                "remove:\(entryPath)"
            case let .rename(from, to):
                "rename:\(from)->\(to)"
            case let .replace(entryPath, _):
                "replace:\(entryPath)"
            }
        }
    }
}

// MARK: - Journal Store

/// File-system helpers for reading, writing, scanning, and acting on
/// crash-recovery journals.
public enum CrashRecoveryJournalStore {
    /// Returns the journal file URL for a given archive URL
    /// (`<archive>.zip.awb-journal`).
    public static func journalURL(forArchiveAt archiveURL: URL) -> URL {
        archiveURL.appendingPathExtension(CrashRecoveryJournal.fileExtension)
    }

    /// Atomically writes the journal next to the target archive.
    public static func write(
        _ journal: CrashRecoveryJournal,
        forArchiveAt archiveURL: URL
    ) throws {
        let url = journalURL(forArchiveAt: archiveURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(journal)
        try data.write(to: url, options: .atomic)
    }

    /// Reads and decodes a journal from disk, returning `nil` if the file is
    /// missing or unreadable.
    public static func read(at url: URL) -> CrashRecoveryJournal? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CrashRecoveryJournal.self, from: data)
    }

    /// Deletes the journal file for the given archive, ignoring errors.
    public static func deleteJournal(forArchiveAt archiveURL: URL) {
        try? FileManager.default.removeItem(at: journalURL(forArchiveAt: archiveURL))
    }

    /// Scans the given directories for `.awb-journal` files whose state is
    /// ``CrashRecoveryJournal/State/inProgress``.
    public static func scanForUnfinishedJournals(
        in directories: [URL]
    ) -> [(journalURL: URL, journal: CrashRecoveryJournal)] {
        var results: [(journalURL: URL, journal: CrashRecoveryJournal)] = []
        var seenJournalPaths = Set<String>()
        let journalExtension = CrashRecoveryJournal.fileExtension
        for directory in directories {
            guard let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                if enumerator.level > 5 {
                    enumerator.skipDescendants()
                    continue
                }
                guard fileURL.pathExtension == journalExtension else { continue }
                guard let journal = read(at: fileURL),
                      journal.state == .inProgress
                else { continue }
                let expectedSource = fileURL.deletingPathExtension().path
                guard canonicalPath(journal.sourceArchive) == canonicalPath(expectedSource)
                else { continue }
                let stagingDir = URL(fileURLWithPath: journal.stagingFile).deletingLastPathComponent()
                guard canonicalPath(stagingDir.path)
                    == canonicalPath(fileURL.deletingLastPathComponent().path)
                else { continue }
                let canonicalJournalPath = canonicalPath(fileURL.path)
                guard seenJournalPaths.insert(canonicalJournalPath).inserted else { continue }
                results.append((journalURL: fileURL, journal: journal))
            }
        }
        return results
    }

    /// Returns `true` when the journal is consistent with the archive it was
    /// found next to: its recorded source archive resolves to `archiveURL`
    /// (after symlink canonicalization) and its staging file lives in the same
    /// directory as the archive. Mirrors the integrity checks performed during
    /// directory scanning so an open-time check cannot act on a stale or
    /// relocated journal.
    public static func journal(
        _ journal: CrashRecoveryJournal,
        matchesArchiveAt archiveURL: URL
    ) -> Bool {
        let journalURL = journalURL(forArchiveAt: archiveURL)
        let expectedSource = journalURL.deletingPathExtension().path
        guard canonicalPath(journal.sourceArchive) == canonicalPath(expectedSource)
        else { return false }
        let stagingDir = URL(fileURLWithPath: journal.stagingFile).deletingLastPathComponent()
        guard canonicalPath(stagingDir.path)
            == canonicalPath(journalURL.deletingLastPathComponent().path)
        else { return false }
        // Staleness guard: the staging file holds the interrupted save's output
        // and must be at least as new as the on-disk archive. If the archive is
        // newer, it was replaced after the crash (e.g. a fresh archive created
        // at the same path), so recovering would clobber it with stale bytes.
        let stagingURL = URL(fileURLWithPath: journal.stagingFile)
        if
            let archiveDate = (try? archiveURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate,
            let stagingDate = (try? stagingURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate
        {
            return archiveDate <= stagingDate
        }
        return true
    }

    /// Returns `true` when the staging file referenced by the journal still
    /// exists on disk as a non-empty regular file.
    public static func stagingFileExists(for journal: CrashRecoveryJournal) -> Bool {
        let url = URL(fileURLWithPath: journal.stagingFile)
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        ),
            values.isRegularFile == true,
            let size = values.fileSize, size > 0
        else { return false }
        return true
    }

    /// Completes an interrupted save by atomically renaming the staging file
    /// over the source archive, then removes the journal.
    ///
    /// Throws ``CrashRecoveryError/stagingFileMissing`` if the staging file
    /// no longer exists (the save may have already completed).
    public static func recover(_ journal: CrashRecoveryJournal) throws {
        let stagingURL = URL(fileURLWithPath: journal.stagingFile)
        let targetURL = URL(fileURLWithPath: journal.sourceArchive)

        let stagingFD = stagingURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard stagingFD >= 0 else {
            deleteJournal(forArchiveAt: targetURL)
            throw CrashRecoveryError.stagingFileMissing
        }
        var statBuf = stat()
        guard Darwin.fstat(stagingFD, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(stagingFD)
            deleteJournal(forArchiveAt: targetURL)
            throw CrashRecoveryError.stagingFileMissing
        }
        let stagingSize = Int(statBuf.st_size)

        guard stagingSize >= 22 else {
            Darwin.close(stagingFD)
            deleteJournal(forArchiveAt: targetURL)
            throw CrashRecoveryError.stagingFileMissing
        }
        Darwin.close(stagingFD)

        // Refuse to overwrite the original unless the staging file parses as a
        // complete ZIP. A partial staging file (interrupted write) would
        // otherwise destroy the user's intact archive.
        guard ZIPStagingValidator.isValidArchive(at: stagingURL) else {
            deleteJournal(forArchiveAt: targetURL)
            throw CrashRecoveryError.stagingFileInvalid
        }

        let renameResult = stagingURL.withUnsafeFileSystemRepresentation { stagePath in
            targetURL.withUnsafeFileSystemRepresentation { targetPath in
                guard let stagePath, let targetPath else { return Int32(-1) }
                return Darwin.rename(stagePath, targetPath)
            }
        }
        guard renameResult == 0 else {
            throw CrashRecoveryError.renameFailed(errno)
        }

        let verifyFD = targetURL.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        if verifyFD >= 0 {
            var verifyBuf = stat()
            let ok = Darwin.fstat(verifyFD, &verifyBuf) == 0
                && (verifyBuf.st_mode & S_IFMT) == S_IFREG
                && Int(verifyBuf.st_size) == stagingSize
            Darwin.close(verifyFD)
            guard ok else {
                throw CrashRecoveryError.renameFailed(EIO)
            }
        }

        syncDirectory(at: targetURL.deletingLastPathComponent())

        deleteJournal(forArchiveAt: targetURL)
    }

    /// Discards the staging file and removes the journal, leaving the
    /// original archive untouched.
    public static func discard(_ journal: CrashRecoveryJournal) {
        let stagingURL = URL(fileURLWithPath: journal.stagingFile)
        try? FileManager.default.removeItem(at: stagingURL)
        let targetURL = URL(fileURLWithPath: journal.sourceArchive)
        deleteJournal(forArchiveAt: targetURL)
    }

    // MARK: Private

    /// Returns a symlink-canonical form of a path for reliable equality checks.
    ///
    /// Resolves the deepest existing ancestor via `realpath` and re-appends any
    /// remaining (not-yet-created) components lexically. This canonicalizes
    /// symlinked prefixes such as `/var -> /private/var` even when the final
    /// path does not exist yet, matching the resolved URLs the directory
    /// enumerator produces during scanning.
    private static func canonicalPath(_ path: String) -> String {
        var current = path
        var trailing: [String] = []
        while true {
            if let resolved = realpath(current, nil) {
                let base = String(cString: resolved)
                free(resolved)
                guard !trailing.isEmpty else { return base }
                return (base as NSString).appendingPathComponent(trailing.reversed().joined(separator: "/"))
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { return path }
            trailing.append((current as NSString).lastPathComponent)
            current = parent
        }
    }

    private static func syncDirectory(at url: URL) {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else { return }
        fsync(descriptor)
        Darwin.close(descriptor)
    }
}

// MARK: - Errors

public enum CrashRecoveryError: Error, Equatable, Sendable {
    /// The staging file referenced by the journal no longer exists.
    case stagingFileMissing
    /// The staging file exists but is not a structurally complete ZIP archive,
    /// so recovery refuses to overwrite the original.
    case stagingFileInvalid
    /// The atomic rename during recovery failed with the given `errno`.
    case renameFailed(Int32)
}
