import Foundation

/// Result of format detection, capturing both the detected format and any
/// mismatch between the file's content signature and its extension.
public struct FormatDetectionResult: Equatable, Sendable {
    /// The format determined by content signature (magic bytes).
    public let detectedFormat: ArchiveFormat?
    /// The format inferred from the file extension, if any.
    public let extensionFormat: ArchiveFormat?
    /// True when both are present but disagree.
    public let hasMismatch: Bool

    /// The format to use for opening: prefer signature, fall back to extension.
    public var effectiveFormat: ArchiveFormat? {
        detectedFormat ?? extensionFormat
    }

    public init(detectedFormat: ArchiveFormat?, extensionFormat: ArchiveFormat?) {
        self.detectedFormat = detectedFormat
        self.extensionFormat = extensionFormat
        self.hasMismatch = detectedFormat != nil && extensionFormat != nil && detectedFormat != extensionFormat
    }
}

/// Detects archive format by reading file signatures (magic bytes).
///
/// Design principle: 格式识别以签名与能力为准，不只看扩展名。
/// Signature detection takes priority over extension-based inference.
public struct ArchiveFormatDetector: Sendable {

    // MARK: - Public API

    /// Detect format from a file URL by reading header/trailer bytes.
    /// - Parameter url: File URL to inspect.
    /// - Returns: Detection result with signature-based and extension-based formats.
    /// - Throws: If the file cannot be read.
    public static func detect(from url: URL) throws -> FormatDetectionResult {
        let extensionFormat = formatFromExtension(url.pathExtension)

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        guard fileSize > 0 else {
            return FormatDetectionResult(detectedFormat: nil, extensionFormat: extensionFormat)
        }

        // Read header: enough for all signatures including ISO at offset 32769
        let headerLength = min(fileSize, 32_780)
        try fileHandle.seek(toOffset: 0)
        let header = fileHandle.readData(ofLength: Int(headerLength))

        // Read trailer for DMG koly block (last 512 bytes)
        var trailer = Data()
        if fileSize >= 512 {
            try fileHandle.seek(toOffset: fileSize - 512)
            trailer = fileHandle.readData(ofLength: 512)
        }

        let detectedFormat = detect(fromHeader: header, trailer: trailer, fileSize: fileSize)
        return FormatDetectionResult(detectedFormat: detectedFormat, extensionFormat: extensionFormat)
    }

    /// Detect format from raw header data only (no trailer check for DMG).
    /// Useful for quick detection when the full file is not available.
    /// - Parameter header: At least the first 32_780 bytes of the file (or fewer for small files).
    /// - Returns: Detected format, or nil if unrecognized.
    public static func detect(fromHeader header: Data) -> ArchiveFormat? {
        detect(fromHeader: header, trailer: Data(), fileSize: UInt64(header.count))
    }

    // MARK: - Signature Detection

    private static func detect(fromHeader header: Data, trailer: Data, fileSize: UInt64) -> ArchiveFormat? {
        // Check signatures in order of specificity.
        // RAR5 before RAR4 (RAR5 signature is longer and more specific).
        if matches(header, bytes: rar5Signature) { return .rar }
        if matches(header, bytes: rar4Signature) { return .rar }
        if matches(header, bytes: sevenZipSignature) { return .sevenZip }
        if matches(header, bytes: xzSignature) { return .xz }
        if matches(header, bytes: zstdSignature) { return .zstandard }
        if matches(header, bytes: gzipSignature) { return .gzip }
        if matches(header, bytes: bzip2Signature) { return .bzip2 }
        if matchesZIP(header) { return .zip }
        if matchesTAR(header) { return .tar }
        if matchesISO(header) { return .iso }
        if matchesDMG(trailer: trailer, fileSize: fileSize) { return .dmg }
        return nil
    }

    // MARK: - Extension Mapping

    /// Infer format from file extension (lowercase, no dot).
    public static func formatFromExtension(_ ext: String) -> ArchiveFormat? {
        switch ext.lowercased() {
        case "zip", "zipx": return .zip
        case "7z": return .sevenZip
        case "tar": return .tar
        case "gz", "gzip": return .gzip
        case "bz2", "bzip2": return .bzip2
        case "xz": return .xz
        case "zst", "zstd": return .zstandard
        case "rar": return .rar
        case "dmg": return .dmg
        case "iso": return .iso
        case "tgz": return .gzip
        case "tbz2": return .bzip2
        case "txz": return .xz
        default: return nil
        }
    }

    // MARK: - Signatures

    /// ZIP: PK\x03\x04 (normal), PK\x05\x06 (empty archive), PK\x07\x08 (spanned)
    private static let zipSignatures: [[UInt8]] = [
        [0x50, 0x4B, 0x03, 0x04],
        [0x50, 0x4B, 0x05, 0x06],
        [0x50, 0x4B, 0x07, 0x08],
    ]

    /// 7z: \x37\x7A\xBC\xAF\x27\x1C
    private static let sevenZipSignature: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]

    /// RAR4: \x52\x61\x72\x21\x1A\x07\x00
    private static let rar4Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]

    /// RAR5: \x52\x61\x72\x21\x1A\x07\x01\x00
    private static let rar5Signature: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]

    /// GZIP: \x1F\x8B
    private static let gzipSignature: [UInt8] = [0x1F, 0x8B]

    /// BZIP2: BZh
    private static let bzip2Signature: [UInt8] = [0x42, 0x5A, 0x68]

    /// XZ: \xFD\x37\x7A\x58\x5A\x00
    private static let xzSignature: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]

    /// Zstd: \x28\xB5\x2F\xFD
    private static let zstdSignature: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    // MARK: - Matching Helpers

    private static func matches(_ data: Data, bytes: [UInt8]) -> Bool {
        guard data.count >= bytes.count else { return false }
        let prefix = data.prefix(bytes.count)
        return prefix.elementsEqual(bytes)
    }

    private static func matchesZIP(_ data: Data) -> Bool {
        zipSignatures.contains { matches(data, bytes: $0) }
    }

    /// TAR: "ustar" at offset 257
    private static func matchesTAR(_ data: Data) -> Bool {
        let ustar: [UInt8] = [0x75, 0x73, 0x74, 0x61, 0x72] // "ustar"
        let offset = 257
        guard data.count >= offset + ustar.count else { return false }
        let slice = data.subdata(in: offset..<(offset + ustar.count))
        return slice.elementsEqual(ustar)
    }

    /// ISO 9660: "CD001" at offset 32769 (sector 16, byte 1)
    private static func matchesISO(_ data: Data) -> Bool {
        let cd001: [UInt8] = [0x43, 0x44, 0x30, 0x30, 0x31] // "CD001"
        let offset = 32_769
        guard data.count >= offset + cd001.count else { return false }
        let slice = data.subdata(in: offset..<(offset + cd001.count))
        return slice.elementsEqual(cd001)
    }

    /// DMG: "koly" trailer block in last 512 bytes
    private static func matchesDMG(trailer: Data, fileSize: UInt64) -> Bool {
        let koly: [UInt8] = [0x6B, 0x6F, 0x6C, 0x79] // "koly"
        guard trailer.count >= 512, fileSize >= 512 else { return false }
        // The koly block starts at the beginning of the last 512 bytes
        let prefix = trailer.prefix(koly.count)
        return prefix.elementsEqual(koly)
    }
}
