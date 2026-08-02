import AppKit
import Foundation

/// Handles macOS Services menu invocation: "用 MacUnzip 打开".
/// Registered as the app's servicesProvider so Finder context-menu → Services
/// can send archive file URLs to the app.
@MainActor
final class ArchiveServiceProvider: NSObject {
    /// Called by the Services system when the user selects
    /// "用 MacUnzip 打开" from Finder's context menu.
    /// - Parameters:
    ///   - pasteboard: The pasteboard containing the file URLs.
    ///   - userData: Additional user data (unused).
    ///   - error: On return, an error string if the operation failed.
    @objc func openArchiveFromService(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], let firstURL = urls.first else {
            error.pointee = AppLocalization().string("无法读取所选文件。") as NSString
            return
        }

        // Activate the app and open the archive (opens a new window if none exists)
        NSApp.activate(ignoringOtherApps: true)
        MacUnzipAppDelegate.deliverOpenURL(firstURL, skippedCount: max(0, urls.count - 1))
    }
}
