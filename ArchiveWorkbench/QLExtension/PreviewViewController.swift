import AppKit
import QuickLookUI

// MARK: - Minimal ZIP Central Directory Reader

/// A lightweight ZIP reader that parses the central directory to list entries
/// without extracting any file content. Used exclusively by the QL extension
/// to avoid depending on the full ArchiveKit package.
struct ZIPSummaryReader: Sendable {
    struct EntryInfo: Sendable {
        let path: String
        let uncompressedSize: UInt64
        let compressedSize: UInt64
        let isDirectory: Bool
    }

    struct Summary: Sendable {
        let entries: [EntryInfo]
        let totalUncompressedSize: UInt64
        let entryCount: Int
    }

    enum ReadError: Error {
        case notAZipFile
        case truncatedCentralDirectory
        case ioError
    }

    // EOCD signature: 0x06054b50
    private static let eocdSignature: UInt32 = 0x06054B50
    // Central directory entry signature: 0x02014b50
    private static let centralDirSignature: UInt32 = 0x02014B50
    // Maximum comment size to scan backwards
    private static let maxEOCDScan: Int = 65535 + 22

    static func readSummary(from url: URL) throws -> Summary {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ReadError.ioError
        }
        guard data.count >= 22 else { throw ReadError.notAZipFile }

        // Find EOCD by scanning backwards
        guard let eocdOffset = findEOCD(in: data) else { throw ReadError.notAZipFile }

        // Parse EOCD
        let totalEntries = data.readUInt16(at: eocdOffset + 10)
        let centralDirSize = data.readUInt32(at: eocdOffset + 12)
        let centralDirOffset = data.readUInt32(at: eocdOffset + 16)

        guard Int(centralDirOffset) + Int(centralDirSize) <= data.count else {
            throw ReadError.truncatedCentralDirectory
        }

        // Check for ZIP64 EOCD locator
        var entryCount = Int(totalEntries)
        var cdOffset = Int(centralDirOffset)

        if totalEntries == 0xFFFF || centralDirOffset == 0xFFFFFFFF {
            if let zip64Summary = parseZIP64EOCD(in: data, beforeEOCDAt: eocdOffset) {
                entryCount = zip64Summary.entryCount
                cdOffset = zip64Summary.cdOffset

            }
        }

        // Parse central directory entries
        var entries: [EntryInfo] = []
        var offset = cdOffset
        entries.reserveCapacity(min(entryCount, 10000))

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count else { break }
            let sig = data.readUInt32(at: offset)
            guard sig == centralDirSignature else { break }

            let generalFlags = data.readUInt16(at: offset + 8)
            var rawCompressed = UInt64(data.readUInt32(at: offset + 20))
            var rawUncompressed = UInt64(data.readUInt32(at: offset + 24))
            let fileNameLength = Int(data.readUInt16(at: offset + 28))
            let extraFieldLength = Int(data.readUInt16(at: offset + 30))
            let commentLength = Int(data.readUInt16(at: offset + 32))

            // Check for ZIP64 extra field if sizes are 0xFFFFFFFF
            let extraStart = offset + 46 + fileNameLength
            if rawCompressed == 0xFFFFFFFF || rawUncompressed == 0xFFFFFFFF {
                if let zip64Sizes = parseZIP64ExtraField(
                    in: data,
                    extraOffset: extraStart,
                    extraLength: extraFieldLength,
                    needsUncompressed: rawUncompressed == 0xFFFFFFFF,
                    needsCompressed: rawCompressed == 0xFFFFFFFF
                ) {
                    rawUncompressed = zip64Sizes.uncompressed
                    rawCompressed = zip64Sizes.compressed
                }
            }

            // Read filename
            let nameStart = offset + 46
            guard nameStart + fileNameLength <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + fileNameLength))

            let path: String
            let usesUTF8 = (generalFlags & 0x0800) != 0
            if usesUTF8 {
                path = String(decoding: nameData, as: UTF8.self)
            } else {
                path = String(data: nameData, encoding: .utf8)
                    ?? String(data: nameData, encoding: .isoLatin1)
                    ?? nameData.map { String(format: "%02x", $0) }.joined()
            }

            let isDirectory = path.hasSuffix("/")
            entries.append(EntryInfo(
                path: path,
                uncompressedSize: rawUncompressed,
                compressedSize: rawCompressed,
                isDirectory: isDirectory
            ))

            offset += 46 + fileNameLength + extraFieldLength + commentLength
        }

        let totalSize = entries.reduce(UInt64(0)) { $0 + $1.uncompressedSize }
        return Summary(entries: entries, totalUncompressedSize: totalSize, entryCount: entries.count)
    }

    private static func findEOCD(in data: Data) -> Int? {
        let scanStart = max(0, data.count - maxEOCDScan)
        var offset = data.count - 22
        while offset >= scanStart {
            if data.readUInt32(at: offset) == eocdSignature {
                return offset
            }
            offset -= 1
        }
        return nil
    }

    private struct ZIP64EOCDInfo {
        let entryCount: Int
        let cdOffset: Int
        let cdSize: Int
    }

    private static func parseZIP64EOCD(in data: Data, beforeEOCDAt eocdOffset: Int) -> ZIP64EOCDInfo? {
        let locatorOffset = eocdOffset - 20
        guard locatorOffset >= 0 else { return nil }
        guard data.readUInt32(at: locatorOffset) == 0x07064B50 else { return nil }
        let zip64EOCDOffset = Int(data.readUInt64(at: locatorOffset + 8))
        guard zip64EOCDOffset + 56 <= data.count else { return nil }
        guard data.readUInt32(at: zip64EOCDOffset) == 0x06064B50 else { return nil }
        let totalEntries = Int(data.readUInt64(at: zip64EOCDOffset + 32))
        let cdSize = Int(data.readUInt64(at: zip64EOCDOffset + 40))
        let cdOffset = Int(data.readUInt64(at: zip64EOCDOffset + 48))
        return ZIP64EOCDInfo(entryCount: totalEntries, cdOffset: cdOffset, cdSize: cdSize)
    }

    private struct ZIP64Sizes {
        let uncompressed: UInt64
        let compressed: UInt64
    }

    private static func parseZIP64ExtraField(
        in data: Data,
        extraOffset: Int,
        extraLength: Int,
        needsUncompressed: Bool,
        needsCompressed: Bool
    ) -> ZIP64Sizes? {
        var pos = extraOffset
        let end = extraOffset + extraLength
        while pos + 4 <= end, pos + 4 <= data.count {
            let headerID = data.readUInt16(at: pos)
            let dataSize = Int(data.readUInt16(at: pos + 2))
            pos += 4
            guard pos + dataSize <= data.count else { break }
            if headerID == 0x0001 {
                var fieldPos = pos
                var uncompressed: UInt64 = 0
                var compressed: UInt64 = 0
                if needsUncompressed, fieldPos + 8 <= data.count {
                    uncompressed = data.readUInt64(at: fieldPos)
                    fieldPos += 8
                }
                if needsCompressed, fieldPos + 8 <= data.count {
                    compressed = data.readUInt64(at: fieldPos)
                }
                return ZIP64Sizes(uncompressed: uncompressed, compressed: compressed)
            }
            pos += dataSize
        }
        return nil
    }
}

// MARK: - Data Reading Helpers

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        }
    }
}

// MARK: - Archive Format Detection

enum DetectedArchiveFormat: String, Sendable {
    case zip = "ZIP"
    case sevenZip = "7-Zip"
    case rar = "RAR"
    case tar = "TAR"
    case gzip = "Gzip"
    case unknown = "未知"

    static func detect(from url: URL) -> DetectedArchiveFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip", "zipx": return .zip
        case "7z": return .sevenZip
        case "rar": return .rar
        case "tar": return .tar
        case "gz", "tgz": return .gzip
        default:
            guard let handle = try? FileHandle(forReadingFrom: url) else { return .unknown }
            defer { try? handle.close() }
            let header = handle.readData(ofLength: 6)
            if header.count >= 4, header[0] == 0x50, header[1] == 0x4B { return .zip }
            if header.count >= 6, header[0] == 0x37, header[1] == 0x7A,
               header[2] == 0xBC, header[3] == 0xAF,
               header[4] == 0x27, header[5] == 0x1C { return .sevenZip }
            if header.count >= 4, header[0] == 0x52, header[1] == 0x61,
               header[2] == 0x72, header[3] == 0x21 { return .rar }
            if header.count >= 2, header[0] == 0x1F, header[1] == 0x8B { return .gzip }
            return .unknown
        }
    }
}

// MARK: - Preview Text Builder (nonisolated, Sendable)

/// Builds the preview text content off the main actor.
struct PreviewTextBuilder: Sendable {
    static func buildPreview(for url: URL) -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let format = DetectedArchiveFormat.detect(from: url)
        let fileName = url.lastPathComponent

        var fileSize: UInt64 = 0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            fileSize = size.uint64Value
        }

        switch format {
        case .zip:
            return buildZIPPreview(url: url, fileName: fileName, fileSize: fileSize)
        default:
            return buildGenericPreview(format: format, fileName: fileName, fileSize: fileSize)
        }
    }

    private static func buildZIPPreview(url: URL, fileName: String, fileSize: UInt64) -> String {
        do {
            let summary = try ZIPSummaryReader.readSummary(from: url)
            return formatZIPSummary(summary, fileName: fileName, fileSize: fileSize)
        } catch {
            return buildErrorPreview(fileName: fileName, fileSize: fileSize)
        }
    }

    private static func formatZIPSummary(
        _ summary: ZIPSummaryReader.Summary,
        fileName: String,
        fileSize: UInt64
    ) -> String {
        var lines: [String] = []
        lines.append("┌─────────────────────────────────────────┐")
        lines.append("│  \(fileName)")
        lines.append("└─────────────────────────────────────────┘")
        lines.append("")
        lines.append("格式：ZIP")
        lines.append("文件大小：\(formatBytes(fileSize))")
        lines.append("包含项目：\(summary.entryCount) 项")
        lines.append("解压后大小：\(formatBytes(summary.totalUncompressedSize))")
        if fileSize > 0, summary.totalUncompressedSize > 0 {
            let ratio = Double(fileSize) / Double(summary.totalUncompressedSize) * 100
            lines.append("压缩率：\(String(format: "%.1f%%", ratio))")
        }
        lines.append("")
        lines.append("── 文件列表 ──────────────────────────────")
        lines.append("")

        let displayEntries = summary.entries.prefix(20)
        for entry in displayEntries {
            let icon = entry.isDirectory ? "📁" : "📄"
            let sizeInfo = entry.isDirectory ? "" : "  (\(formatBytes(entry.uncompressedSize)))"
            let displayPath = entry.path.hasSuffix("/")
                ? String(entry.path.dropLast())
                : entry.path
            lines.append("\(icon) \(displayPath)\(sizeInfo)")
        }

        if summary.entryCount > 20 {
            lines.append("")
            lines.append("… 还有 \(summary.entryCount - 20) 个项目")
            lines.append("  使用 ArchiveWorkbench 打开查看完整内容")
        }

        lines.append("")
        lines.append("── 由 ArchiveWorkbench 生成预览 ──")
        return lines.joined(separator: "\n")
    }

    private static func buildGenericPreview(
        format: DetectedArchiveFormat,
        fileName: String,
        fileSize: UInt64
    ) -> String {
        var lines: [String] = []
        lines.append("┌─────────────────────────────────────────┐")
        lines.append("│  \(fileName)")
        lines.append("└─────────────────────────────────────────┘")
        lines.append("")
        lines.append("格式：\(format.rawValue)")
        lines.append("文件大小：\(formatBytes(fileSize))")
        lines.append("")
        lines.append("此格式的详细内容预览需要 ArchiveWorkbench 应用。")
        lines.append("右键点击文件 → 打开方式 → ArchiveWorkbench")
        lines.append("")
        lines.append("── 由 ArchiveWorkbench 生成预览 ──")
        return lines.joined(separator: "\n")
    }

    private static func buildErrorPreview(fileName: String, fileSize: UInt64) -> String {
        var lines: [String] = []
        lines.append("┌─────────────────────────────────────────┐")
        lines.append("│  \(fileName)")
        lines.append("└─────────────────────────────────────────┘")
        lines.append("")
        lines.append("文件大小：\(formatBytes(fileSize))")
        lines.append("")
        lines.append("无法读取此压缩包的内容。")
        lines.append("文件可能已损坏或使用了不支持的加密方式。")
        lines.append("")
        lines.append("── 由 ArchiveWorkbench 生成预览 ──")
        return lines.joined(separator: "\n")
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }
}

// MARK: - Preview View Controller

final class PreviewViewController: NSViewController, QLPreviewingController {
    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        view = scrollView
    }

    // MARK: - QLPreviewingController

    nonisolated func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping @Sendable (Error?) -> Void) {
        let previewText = PreviewTextBuilder.buildPreview(for: url)
        Task { @MainActor [weak self] in
            self?.textView.string = previewText
            self?.textView.scrollToBeginningOfDocument(nil)
            handler(nil)
        }
    }
}
