import Foundation
import UniformTypeIdentifiers

/// Supported archive file types for open/save panels and drag-and-drop.
enum ArchiveFileTypes {
    static let pathExtensions: Set<String> = [
        "zip", "zipx", "7z", "rar", "tar", "gz", "gzip", "tgz",
        "bz2", "bzip2", "tbz2", "xz", "txz", "zst", "zstd",
        "dmg", "iso",
    ]

    static let contentTypes: [UTType] = {
        var types: [UTType] = [.zip, .gzip]
        for ext in ["7z", "rar", "tar", "zipx", "zst", "tgz", "bz2", "tbz2", "xz", "txz", "dmg", "iso"] {
            if let ut = UTType(filenameExtension: ext) {
                types.append(ut)
            }
        }
        return types
    }()

    static func isSupportedArchive(_ url: URL) -> Bool {
        pathExtensions.contains(url.pathExtension.lowercased())
    }
}
