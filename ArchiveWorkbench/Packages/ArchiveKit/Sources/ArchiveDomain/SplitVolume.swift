import Foundation

/// Preset and custom volume sizes for split (multipart) archive creation.
///
/// Design principle from handoff: "ZIP：分卷" / "7z：分卷"
/// Only formats that support splitting (ZIP, 7z) expose this option.
public enum SplitVolumeSize: Equatable, Sendable, Hashable {
    /// No splitting — single-file archive.
    case none
    /// 4 MB volumes (floppy-era legacy, still common for email attachments).
    case mb4
    /// 10 MB volumes.
    case mb10
    /// 100 MB volumes (CD-era).
    case mb100
    /// 1 GB volumes (USB stick friendly).
    case gb1
    /// User-specified byte count (minimum 64 KB enforced at creation time).
    case custom(bytes: UInt64)

    /// The byte size of each volume, or nil for `.none`.
    public var byteSize: UInt64? {
        switch self {
        case .none: return nil
        case .mb4: return 4 * 1024 * 1024
        case .mb10: return 10 * 1024 * 1024
        case .mb100: return 100 * 1024 * 1024
        case .gb1: return 1024 * 1024 * 1024
        case .custom(let bytes): return bytes
        }
    }

    /// Minimum allowed volume size (64 KB). Smaller values are impractical.
    public static let minimumBytes: UInt64 = 64 * 1024

    /// All preset options for UI pickers (excludes `.custom`).
    public static let presets: [SplitVolumeSize] = [.none, .mb4, .mb10, .mb100, .gb1]

    /// Human-readable label for UI display.
    public var displayLabel: String {
        switch self {
        case .none: return "无"
        case .mb4: return "4 MB"
        case .mb10: return "10 MB"
        case .mb100: return "100 MB"
        case .gb1: return "1 GB"
        case .custom(let bytes): return Self.formatBytes(bytes)
        }
    }

    /// Estimates the number of volumes needed for a given total input size.
    /// Returns nil when splitting is disabled (.none) or input is zero.
    public func estimatedVolumeCount(totalBytes: UInt64) -> Int? {
        guard let size = byteSize, size > 0, totalBytes > 0 else { return nil }
        // Compressed output is typically smaller, but we estimate conservatively
        // assuming ~70% compression ratio for the estimate.
        let estimatedOutput = UInt64(Double(totalBytes) * 0.7)
        let effectiveOutput = max(estimatedOutput, 1)
        return Int((effectiveOutput + size - 1) / size)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            let gb = Double(bytes) / (1024 * 1024 * 1024)
            return gb == gb.rounded() ? "\(Int(gb)) GB" : String(format: "%.1f GB", gb)
        } else if bytes >= 1024 * 1024 {
            let mb = Double(bytes) / (1024 * 1024)
            return mb == mb.rounded() ? "\(Int(mb)) MB" : String(format: "%.1f MB", mb)
        } else if bytes >= 1024 {
            let kb = Double(bytes) / 1024
            return kb == kb.rounded() ? "\(Int(kb)) KB" : String(format: "%.1f KB", kb)
        }
        return "\(bytes) B"
    }
}

/// Detects and resolves split (multipart) archive volume sets.
///
/// Supported patterns:
/// - ZIP spanning: archive.z01, archive.z02, ..., archive.zip (final segment)
/// - Numbered splits: archive.zip.001, archive.zip.002, ... (7z-style)
/// - 7z splits: archive.7z.001, archive.7z.002, ...
public struct SplitVolumeResolver: Sendable {

    public init() {}

    /// Result of resolving a split archive set.
    public struct Resolution: Equatable, Sendable {
        /// The URL to pass to the extraction engine (final .zip or first .001).
        public let primaryURL: URL
        /// All volume URLs in order, if they could be enumerated.
        public let volumeURLs: [URL]
        /// URLs of volumes that are expected but missing on disk.
        public let missingVolumes: [URL]
        /// The detected split pattern.
        public let pattern: Pattern
        /// Total number of volumes (including missing ones, if determinable).
        public let totalVolumes: Int?

        public var hasMissingVolumes: Bool { !missingVolumes.isEmpty }
    }

    public enum Pattern: String, Equatable, Sendable {
        /// ZIP spanning: .z01, .z02, ..., .zip
        case zipSpanning
        /// Numbered suffix: .zip.001, .7z.001, .rar.001, etc.
        case numberedSuffix
    }

    /// Detects whether a URL looks like part of a split archive set.
    public func isSplitVolume(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        // .z01, .z02, ... pattern
        if name.range(of: #"\.z\d{2,}$"#, options: .regularExpression) != nil { return true }
        // .001, .002, ... pattern
        if name.range(of: #"\.\d{3,}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// Resolves the full volume set for a given URL that is part of a split archive.
    /// - Parameter url: Any volume in the set (e.g. the .zip, .z01, or .001 file).
    /// - Returns: Resolution with primary URL, found volumes, and missing volumes.
    public func resolve(url: URL) -> Resolution? {
        let name = url.lastPathComponent
        let directory = url.deletingLastPathComponent()
        let lowerName = name.lowercased()

        // ZIP spanning pattern: archive.z01 -> archive.zip is the primary
        if lowerName.range(of: #"\.z\d{2,}$"#, options: .regularExpression) != nil {
            return resolveZipSpanning(url: url, directory: directory, name: name)
        }

        // Numbered suffix pattern: archive.7z.001 or archive.zip.001
        if lowerName.range(of: #"\.\d{3,}$"#, options: .regularExpression) != nil {
            return resolveNumberedSuffix(url: url, directory: directory, name: name)
        }

        // Check if this is the final .zip of a spanning set (archive.zip with .zNN siblings)
        if lowerName.hasSuffix(".zip") {
            let baseName = String(name.dropLast(4))
            // Scan for any .zNN sibling to detect split sets, even if .z01 is missing
            var hasAnyVolume = false
            for index in 1...99 {
                let volumeName = String(format: "%@.z%02d", baseName, index)
                let volumeURL = directory.appendingPathComponent(volumeName)
                if FileManager.default.fileExists(atPath: volumeURL.path) {
                    hasAnyVolume = true
                    break
                }
            }
            if hasAnyVolume {
                return resolveZipSpanningFromFinal(url: url, directory: directory, baseName: baseName)
            }
        }

        return nil
    }

    // MARK: - Private

    private func resolveZipSpanning(url: URL, directory: URL, name: String) -> Resolution? {
        // Extract base name: "archive.z01" -> "archive"
        guard let dotZRange = name.lowercased().range(of: #"\.z\d{2,}$"#, options: .regularExpression) else {
            return nil
        }
        let baseName = String(name[name.startIndex..<dotZRange.lowerBound])
        let finalURL = directory.appendingPathComponent(baseName + ".zip")
        return resolveZipSpanningFromFinal(url: finalURL, directory: directory, baseName: baseName)
    }

    private func resolveZipSpanningFromFinal(url: URL, directory: URL, baseName: String) -> Resolution {
        var volumeURLs: [URL] = []
        var missingVolumes: [URL] = []
        var volumeIndex = 1

        // Enumerate .z01, .z02, ... until we find a gap
        while true {
            let volumeName = String(format: "%@.z%02d", baseName, volumeIndex)
            let volumeURL = directory.appendingPathComponent(volumeName)
            if FileManager.default.fileExists(atPath: volumeURL.path) {
                volumeURLs.append(volumeURL)
                volumeIndex += 1
            } else {
                // Check if there are more volumes after this gap
                let nextName = String(format: "%@.z%02d", baseName, volumeIndex + 1)
                let nextURL = directory.appendingPathComponent(nextName)
                if FileManager.default.fileExists(atPath: nextURL.path) {
                    missingVolumes.append(volumeURL)
                    volumeIndex += 1
                } else {
                    break
                }
            }
        }

        // The final .zip segment
        let finalURL = directory.appendingPathComponent(baseName + ".zip")
        if FileManager.default.fileExists(atPath: finalURL.path) {
            volumeURLs.append(finalURL)
        } else {
            missingVolumes.append(finalURL)
        }

        let totalVolumes = volumeURLs.count + missingVolumes.count
        return Resolution(
            primaryURL: finalURL,
            volumeURLs: volumeURLs,
            missingVolumes: missingVolumes,
            pattern: .zipSpanning,
            totalVolumes: totalVolumes > 0 ? totalVolumes : nil
        )
    }

    private func resolveNumberedSuffix(url: URL, directory: URL, name: String) -> Resolution? {
        // Extract base and extension: "archive.7z.001" -> base="archive.7z", startNumber=1
        guard let numRange = name.range(of: #"\.\d{3,}$"#, options: .regularExpression) else {
            return nil
        }
        let baseName = String(name[name.startIndex..<numRange.lowerBound])
        let numString = String(name[numRange.lowerBound...]).dropFirst() // drop the dot
        let digitCount = numString.count

        var volumeURLs: [URL] = []
        var missingVolumes: [URL] = []
        var volumeIndex = 1

        // Enumerate .001, .002, ... until we find a gap followed by no more
        while true {
            let volumeName = String(format: "%@.%0*d", baseName, digitCount, volumeIndex)
            let volumeURL = directory.appendingPathComponent(volumeName)
            if FileManager.default.fileExists(atPath: volumeURL.path) {
                volumeURLs.append(volumeURL)
                volumeIndex += 1
            } else {
                // Check one more ahead to detect gaps vs. end
                let nextName = String(format: "%@.%0*d", baseName, digitCount, volumeIndex + 1)
                let nextURL = directory.appendingPathComponent(nextName)
                if FileManager.default.fileExists(atPath: nextURL.path) {
                    missingVolumes.append(volumeURL)
                    volumeIndex += 1
                } else {
                    break
                }
            }
        }

        guard !volumeURLs.isEmpty else { return nil }

        // Primary URL is the first volume (.001)
        let primaryURL = volumeURLs.first ?? url
        let totalVolumes = volumeURLs.count + missingVolumes.count
        return Resolution(
            primaryURL: primaryURL,
            volumeURLs: volumeURLs,
            missingVolumes: missingVolumes,
            pattern: .numberedSuffix,
            totalVolumes: totalVolumes > 0 ? totalVolumes : nil
        )
    }
}
