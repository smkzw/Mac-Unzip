import Foundation
import Testing
@testable import ArchiveDomain

// MARK: - Signature Detection Tests

@Test func detectsZIPNormalSignature() {
    let header = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .zip)
}

@Test func detectsZIPEmptyArchiveSignature() {
    let header = Data([0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .zip)
}

@Test func detectsZIPSpannedSignature() {
    let header = Data([0x50, 0x4B, 0x07, 0x08, 0x00, 0x00, 0x00, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .zip)
}

@Test func detects7zSignature() {
    let header = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .sevenZip)
}

@Test func detectsRAR4Signature() {
    let header = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0xCF])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .rar)
}

@Test func detectsRAR5Signature() {
    let header = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .rar)
}

@Test func detectsGZIPSignature() {
    let header = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .gzip)
}

@Test func detectsBZIP2Signature() {
    let header = Data([0x42, 0x5A, 0x68, 0x39, 0x31, 0x41, 0x59, 0x26])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .bzip2)
}

@Test func detectsXZSignature() {
    let header = Data([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00, 0x00, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .xz)
}

@Test func detectsZstdSignature() {
    let header = Data([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x58, 0xA5, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .zstandard)
}

@Test func detectsTARByUstarAtOffset257() {
    var bytes = [UInt8](repeating: 0, count: 512)
    let ustar: [UInt8] = [0x75, 0x73, 0x74, 0x61, 0x72]
    for (i, b) in ustar.enumerated() {
        bytes[257 + i] = b
    }
    let header = Data(bytes)
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .tar)
}

@Test func detectsISOByCD001AtOffset32769() {
    var bytes = [UInt8](repeating: 0, count: 32_780)
    let cd001: [UInt8] = [0x43, 0x44, 0x30, 0x30, 0x31]
    for (i, b) in cd001.enumerated() {
        bytes[32_769 + i] = b
    }
    let header = Data(bytes)
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == .iso)
}

// MARK: - Unknown / Corrupt / Empty

@Test func returnsNilForUnknownSignature() {
    let header = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == nil)
}

@Test func returnsNilForEmptyData() {
    let header = Data()
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == nil)
}

@Test func returnsNilForTruncatedSignature() {
    let header = Data([0x37, 0x7A, 0xBC])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == nil)
}

@Test func returnsNilForRandomGarbage() {
    let header = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])
    #expect(ArchiveFormatDetector.detect(fromHeader: header) == nil)
}

// MARK: - Extension Mapping

@Test func mapsCommonExtensions() {
    #expect(ArchiveFormatDetector.formatFromExtension("zip") == .zip)
    #expect(ArchiveFormatDetector.formatFromExtension("ZIP") == .zip)
    #expect(ArchiveFormatDetector.formatFromExtension("7z") == .sevenZip)
    #expect(ArchiveFormatDetector.formatFromExtension("tar") == .tar)
    #expect(ArchiveFormatDetector.formatFromExtension("gz") == .gzip)
    #expect(ArchiveFormatDetector.formatFromExtension("bz2") == .bzip2)
    #expect(ArchiveFormatDetector.formatFromExtension("xz") == .xz)
    #expect(ArchiveFormatDetector.formatFromExtension("zst") == .zstandard)
    #expect(ArchiveFormatDetector.formatFromExtension("rar") == .rar)
    #expect(ArchiveFormatDetector.formatFromExtension("dmg") == .dmg)
    #expect(ArchiveFormatDetector.formatFromExtension("iso") == .iso)
    #expect(ArchiveFormatDetector.formatFromExtension("tgz") == .gzip)
}

@Test func returnsNilForUnknownExtension() {
    #expect(ArchiveFormatDetector.formatFromExtension("pdf") == nil)
    #expect(ArchiveFormatDetector.formatFromExtension("") == nil)
    #expect(ArchiveFormatDetector.formatFromExtension("txt") == nil)
}

// MARK: - Mismatch Detection

@Test func detectsMismatchWhenExtensionDisagreesWithContent() {
    let result = FormatDetectionResult(detectedFormat: .sevenZip, extensionFormat: .zip)
    #expect(result.hasMismatch)
    #expect(result.effectiveFormat == .sevenZip)
}

@Test func noMismatchWhenSignatureAndExtensionAgree() {
    let result = FormatDetectionResult(detectedFormat: .zip, extensionFormat: .zip)
    #expect(!result.hasMismatch)
    #expect(result.effectiveFormat == .zip)
}

@Test func noMismatchWhenNoExtension() {
    let result = FormatDetectionResult(detectedFormat: .gzip, extensionFormat: nil)
    #expect(!result.hasMismatch)
    #expect(result.effectiveFormat == .gzip)
}

@Test func fallsBackToExtensionWhenNoSignature() {
    let result = FormatDetectionResult(detectedFormat: nil, extensionFormat: .rar)
    #expect(!result.hasMismatch)
    #expect(result.effectiveFormat == .rar)
}

@Test func effectiveFormatNilWhenNothingDetected() {
    let result = FormatDetectionResult(detectedFormat: nil, extensionFormat: nil)
    #expect(!result.hasMismatch)
    #expect(result.effectiveFormat == nil)
}

// MARK: - File-based Detection

@Test func detectsFormatFromTemporaryZIPFile() throws {
    let zipHeader: [UInt8] = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00]
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("test_\(UUID().uuidString).zip")
    try Data(zipHeader).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try ArchiveFormatDetector.detect(from: url)
    #expect(result.detectedFormat == .zip)
    #expect(result.extensionFormat == .zip)
    #expect(!result.hasMismatch)
    #expect(result.effectiveFormat == .zip)
}

@Test func detectsMismatchFromMisnamedFile() throws {
    let sevenZBytes: [UInt8] = [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x04]
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("misnamed_\(UUID().uuidString).zip")
    try Data(sevenZBytes).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try ArchiveFormatDetector.detect(from: url)
    #expect(result.detectedFormat == .sevenZip)
    #expect(result.extensionFormat == .zip)
    #expect(result.hasMismatch)
    #expect(result.effectiveFormat == .sevenZip)
}

@Test func handlesEmptyFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("empty_\(UUID().uuidString).tar")
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try ArchiveFormatDetector.detect(from: url)
    #expect(result.detectedFormat == nil)
    #expect(result.extensionFormat == .tar)
    #expect(!result.hasMismatch)
    #expect(result.effectiveFormat == .tar)
}

@Test func handlesUnknownFileWithNoExtension() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("noext_\(UUID().uuidString)")
    try Data([0x01, 0x02, 0x03, 0x04]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try ArchiveFormatDetector.detect(from: url)
    #expect(result.detectedFormat == nil)
    #expect(result.extensionFormat == nil)
    #expect(result.effectiveFormat == nil)
}

@Test func detectsDMGFromTrailer() throws {
    var content = [UInt8](repeating: 0, count: 1024)
    let koly: [UInt8] = [0x6B, 0x6F, 0x6C, 0x79]
    for (i, b) in koly.enumerated() {
        content[512 + i] = b
    }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("disk_\(UUID().uuidString).dmg")
    try Data(content).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let result = try ArchiveFormatDetector.detect(from: url)
    #expect(result.detectedFormat == .dmg)
    #expect(result.extensionFormat == .dmg)
    #expect(!result.hasMismatch)
}

// MARK: - RAR version distinction

@Test func rar5TakesPriorityOverRAR4Prefix() {
    let rar5 = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00])
    #expect(ArchiveFormatDetector.detect(fromHeader: rar5) == .rar)

    let rar4 = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x90])
    #expect(ArchiveFormatDetector.detect(fromHeader: rar4) == .rar)
}
