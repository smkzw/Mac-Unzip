import ArchiveDomain
import ArchiveProviders
import Foundation

/// Maximum nesting depth for nested archive sub-sessions (prevents zip-bomb recursion).
let maximumNestedArchiveDepth = 5

/// Archive extensions recognized as openable nested archives.
private let nestedArchiveExtensions: Set<String> = [
    "zip", "zipx", "7z", "rar", "tar", "gz", "gzip", "tgz",
    "bz2", "bzip2", "tbz2", "xz", "txz", "zst", "zstd",
]

/// Returns true if the given filename looks like a supported archive format
/// that can be opened as a nested sub-session.
func isNestedArchiveFileName(_ filename: String) -> Bool {
    let ext = (filename as NSString).pathExtension.lowercased()
    return nestedArchiveExtensions.contains(ext)
}

/// A breadcrumb segment representing one level in the nested archive hierarchy.
struct BreadcrumbSegment: Identifiable, Equatable {
    let id: Int
    let title: String
}

/// Captures the browsing state of a single archive session so it can be
/// restored when the user navigates back from a nested sub-session.
struct ArchiveSessionSnapshot {
    let sourceURL: URL
    let documentTitle: String
    let entries: [ArchiveEntry]
    let metadataByEntryID: [ArchiveEntryID: ArchiveEntryMetadata]
    let folderSummaries: [ArchiveFolderSummary]
    let selectedEntryID: ArchiveEntryID?
    let currentDirectory: String
    let viewMode: ArchiveViewMode
    let documentItemCount: Int
    let canAdd: Bool
    let canExtract: Bool
    let canTestIntegrity: Bool
    let pendingChanges: [PendingChange]
    let archiveFormatName: String
    let encryptedEntryIDs: Set<ArchiveEntryID>
}
