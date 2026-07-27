import AppKit
import Foundation

/// Handles macOS Services menu invocation: "用 Mac解霸 打开".
/// Registered as the app's servicesProvider so Finder context-menu → Services
/// can send archive file URLs to the app.
@MainActor
final class ArchiveServiceProvider: NSObject {
    /// Called by the Services system when the user selects
    /// "用 Mac解霸 打开" from Finder's context menu.
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
            error.pointee = "无法读取所选文件。" as NSString
            return
        }

        // Activate the app and open the archive
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: \.isVisible) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .openArchiveURL, object: firstURL)
    }
}
