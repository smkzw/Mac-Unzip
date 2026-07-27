import AppKit
import Foundation
import Observation

/// Manages the list of recently opened archives, persisted in UserDefaults.
/// Respects the user-configurable count from Settings.
@MainActor
@Observable
final class RecentArchivesManager {
    static let shared = RecentArchivesManager()

    private static let storageKey = "recentArchives.urls"

    /// The current list of recent archive URLs (most recent first).
    private(set) var recentURLs: [URL] = []

    private init() {
        load()
    }

    /// The maximum number of recent archives to keep, read from Settings.
    private var maxCount: Int {
        let count = UserDefaults.standard.integer(forKey: SettingsKeys.recentArchivesCount)
        // Default to 10 if never set (integer(forKey:) returns 0 for missing keys)
        return count == 0 && UserDefaults.standard.object(forKey: SettingsKeys.recentArchivesCount) == nil
            ? 10
            : count
    }

    /// Records a newly opened archive URL at the front of the recent list.
    func noteRecentArchive(_ url: URL) {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        recentURLs.removeAll { $0 == resolved }
        recentURLs.insert(resolved, at: 0)
        let limit = maxCount
        if recentURLs.count > limit {
            recentURLs = Array(recentURLs.prefix(limit))
        }
        save()
        // Also inform the system document controller for the standard Open Recent menu
        NSDocumentController.shared.noteNewRecentDocumentURL(resolved)
    }

    /// Clears all recent archives.
    func clearRecent() {
        recentURLs = []
        save()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    /// Removes a single URL from the recent list.
    func remove(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        save()
    }

    /// Prunes entries that no longer exist on disk.
    func pruneMissing() {
        recentURLs.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let paths = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        recentURLs = paths.map { URL(fileURLWithPath: $0) }
    }

    private func save() {
        let paths = recentURLs.map(\.path)
        if let data = try? JSONEncoder().encode(paths) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
