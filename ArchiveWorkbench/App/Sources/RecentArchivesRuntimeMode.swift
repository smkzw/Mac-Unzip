import Foundation

/// Resolves how the recent-archives list behaves under normal vs launch-argument modes.
enum RecentArchivesRuntimeMode: Equatable, Sendable {
    /// Persist to UserDefaults + NSDocumentController.
    case live
    /// `-ui-testing` without visual capture: empty in-memory list; never touch real prefs.
    case uiTestingEmpty
    /// `-visual-capture`: fictional Sample paths only; never read/write real prefs.
    case visualCaptureFictional

    static func resolve(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self {
        if arguments.contains("-visual-capture") {
            return .visualCaptureFictional
        }
        if arguments.contains("-ui-testing") {
            return .uiTestingEmpty
        }
        return .live
    }

    /// Public, host-agnostic sample paths for marketing / visual capture.
    static var fictionalURLs: [URL] {
        [
            URL(fileURLWithPath: "/Users/Sample/Documents/Design Assets.zip"),
            URL(fileURLWithPath: "/Users/Sample/Downloads/Product Photos.7z"),
            URL(fileURLWithPath: "/Users/Sample/Desktop/Launch Notes.tar.gz"),
        ]
    }
}
