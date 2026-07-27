import Foundation

/// A single staged, not-yet-saved edit to an archive.
///
/// Changes are staged in memory and only become durable when the editor
/// publishes a new archive through a transactional save. Each case carries
/// enough information to render a human-readable summary and to apply the
/// edit during save.
public enum PendingChange: Identifiable, Hashable, Sendable {
    /// Add a file from disk into the archive at `destinationPath`.
    case add(sourceURL: URL, destinationPath: String)
    /// Remove an existing entry (and, recursively, anything beneath it).
    case remove(entryPath: String)
    /// Rename or move an existing entry from one path to another.
    case rename(from: String, to: String)
    /// Replace the content of an existing entry with a file from disk.
    case replace(entryPath: String, sourceURL: URL)

    /// Stable identity used by SwiftUI lists and undo bookkeeping.
    public var id: String {
        switch self {
        case let .add(sourceURL, destinationPath):
            return "add:\(destinationPath)<-\(sourceURL.path)"
        case let .remove(entryPath):
            return "remove:\(entryPath)"
        case let .rename(from, to):
            return "rename:\(from)->\(to)"
        case let .replace(entryPath, sourceURL):
            return "replace:\(entryPath)<-\(sourceURL.path)"
        }
    }

    /// The archive path that this change primarily concerns.
    ///
    /// For `add` this is the destination, for `remove`/`replace` the target
    /// entry, and for `rename` the source path.
    public var primaryPath: String {
        switch self {
        case let .add(_, destinationPath):
            return destinationPath
        case let .remove(entryPath):
            return entryPath
        case let .rename(from, _):
            return from
        case let .replace(entryPath, _):
            return entryPath
        }
    }
}
