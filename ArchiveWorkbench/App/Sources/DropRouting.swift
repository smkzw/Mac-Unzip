import Foundation

/// Shared drop-routing decisions for welcome page, open documents, and create panel.
enum DropRouteContext: Equatable, Sendable {
    /// No document open (welcome / empty window).
    case welcome
    /// An archive document is open.
    case openDocument
    /// Create-archive sheet is collecting inputs.
    case createPanel
}

enum DropRouteDecision: Equatable, Sendable {
    /// Open the first archive; remaining archives are ignored.
    case openFirstArchive(URL, ignoredCount: Int)
    /// Treat the whole batch as create-archive inputs (including any archives).
    case createArchiveInputs([URL])
    /// Add non-archive files into the currently open document.
    case addToOpenDocument([URL])
    /// Mixed archives + other files: caller must present an explicit choice.
    case askMixed(archives: [URL], others: [URL])
}

enum DropRouting {
    /// Pure decision function — no UI side effects. Testable without AppKit sheets.
    static func decide(
        urls: [URL],
        context: DropRouteContext,
        isSupportedArchive: (URL) -> Bool
    ) -> DropRouteDecision? {
        guard !urls.isEmpty else { return nil }

        let classified: [(url: URL, isArchive: Bool)] = urls.map { url in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let archive = exists && !isDir.boolValue && isSupportedArchive(url)
            return (url, archive)
        }
        let archives = classified.filter(\.isArchive).map(\.url)
        let others = classified.filter { !$0.isArchive }.map(\.url)

        switch context {
        case .createPanel:
            // Create panel always treats archives as ordinary inputs.
            return .createArchiveInputs(urls)

        case .welcome:
            if others.isEmpty {
                guard let first = archives.first else { return nil }
                return .openFirstArchive(first, ignoredCount: max(archives.count - 1, 0))
            }
            if archives.isEmpty {
                return .createArchiveInputs(others)
            }
            return .askMixed(archives: archives, others: others)

        case .openDocument:
            if others.isEmpty {
                guard let first = archives.first else { return nil }
                return .openFirstArchive(first, ignoredCount: max(archives.count - 1, 0))
            }
            if archives.isEmpty {
                return .addToOpenDocument(others)
            }
            return .askMixed(archives: archives, others: others)
        }
    }
}
