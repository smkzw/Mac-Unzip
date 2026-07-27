import ArchiveDomain
@testable import ArchiveProviders
import CMinizipBridge
import Foundation
import XCTest

/// Tests for legacy filename encoding detection, override, and raw-byte preservation.
final class EncodingDetectionTests: XCTestCase {

    // MARK: - Unit tests for EncodingDetector

    func testUTF8FlagGivesDefinitiveConfidence() {
        let detector = EncodingDetector()
        let name = "\u{6587}\u{6863}/\u{6D4B}\u{8BD5}\u{6587}\u{4EF6}.txt"
        let bytes = Array(name.utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: true)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, .definitive)
        XCTAssertEqual(result.decodedName, name)
    }

    func testUTF8WithoutFlagDetectedAsHighConfidence() {
        let detector = EncodingDetector()
        let name = "\u{4E2D}\u{6587}\u{6587}\u{4EF6}.txt"
        let bytes = Array(name.utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: false)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.decodedName, name)
    }

    func testPureASCIIGivesDefinitiveConfidence() {
        let detector = EncodingDetector()
        let bytes = Array("hello/world.txt".utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: false)
        XCTAssertEqual(result.confidence, .definitive)
        XCTAssertEqual(result.decodedName, "hello/world.txt")
    }

    func testGBKEncodedChineseDetected() {
        let detector = EncodingDetector()
        // GBK bytes for Chinese characters followed by .txt
        let gbkBytes: [UInt8] = [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74]
        let result = detector.detect(rawBytes: gbkBytes, usesUTF8Flag: false)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertTrue(result.decodedName.hasSuffix(".txt"))
        XCTAssertFalse(result.decodedName.isEmpty)
    }

    func testShiftJISEncodedJapaneseDetected() {
        let detector = EncodingDetector()
        // Shift-JIS katakana bytes followed by .txt
        let sjisBytes: [UInt8] = [0x83, 0x65, 0x83, 0x58, 0x83, 0x67, 0x2E, 0x74, 0x78, 0x74]
        let result = detector.detect(rawBytes: sjisBytes, usesUTF8Flag: false)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertTrue(result.decodedName.hasSuffix(".txt"))
    }

    func testEUCKREncodedKoreanDetected() {
        let detector = EncodingDetector()
        // EUC-KR Hangul bytes followed by .txt
        let eucKrBytes: [UInt8] = [0xC7, 0xD1, 0xB1, 0xDB, 0x2E, 0x74, 0x78, 0x74]
        let result = detector.detect(rawBytes: eucKrBytes, usesUTF8Flag: false)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertTrue(result.decodedName.hasSuffix(".txt"))
    }

    func testOverrideForcesEncoding() {
        let detector = EncodingDetector()
        let gbkBytes: [UInt8] = [0xB2, 0xE2, 0xCA, 0xD4]
        let result = detector.detect(rawBytes: gbkBytes, usesUTF8Flag: false, override: .gbk)
        XCTAssertEqual(result.confidence, .definitive)
        XCTAssertEqual(result.encoding, LegacyEncodingPreference.gbkEncoding)
    }

    func testOverrideUTF8OnUTF8Bytes() {
        let detector = EncodingDetector()
        let name = "\u{65E5}\u{672C}\u{8A9E}.txt"
        let bytes = Array(name.utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: false, override: .utf8)
        XCTAssertEqual(result.decodedName, name)
        XCTAssertEqual(result.confidence, .definitive)
    }

    func testEmojiAndSupplementaryPlaneInUTF8() {
        let detector = EncodingDetector()
        let name = "\u{1F4C1}folder/\u{1F600}file.txt"
        let bytes = Array(name.utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: true)
        XCTAssertEqual(result.decodedName, name)
        XCTAssertEqual(result.confidence, .definitive)

        let resultNoFlag = detector.detect(rawBytes: bytes, usesUTF8Flag: false)
        XCTAssertEqual(resultNoFlag.decodedName, name)
        XCTAssertEqual(resultNoFlag.confidence, .high)
    }

    func testLatinDiacriticsInUTF8() {
        let detector = EncodingDetector()
        let name = "r\u{E9}sum\u{E9}/na\u{EF}ve/caf\u{E9}.txt"
        let bytes = Array(name.utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: true)
        XCTAssertEqual(result.decodedName, name)

        let resultNoFlag = detector.detect(rawBytes: bytes, usesUTF8Flag: false)
        XCTAssertEqual(resultNoFlag.decodedName, name)
    }

    func testArabicRTLInUTF8() {
        let detector = EncodingDetector()
        let name = "\u{645}\u{62C}\u{644}\u{62F}/\u{645}\u{644}\u{641}.txt"
        let bytes = Array(name.utf8)
        let result = detector.detect(rawBytes: bytes, usesUTF8Flag: true)
        XCTAssertEqual(result.decodedName, name)
    }

    func testDecodeWithOverrideMethod() {
        let detector = EncodingDetector()
        let gbkBytes: [UInt8] = [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74]
        let decoded = detector.decodeWithOverride(rawBytes: gbkBytes, override: .gbk)
        XCTAssertTrue(decoded.hasSuffix(".txt"))
        XCTAssertFalse(decoded.isEmpty)
    }

    // MARK: - Integration tests with actual ZIP files

    func testOpenZIPWithGBKEncodedNames() async throws {
        let zipURL = try createZIPWithRawName(
            rawNameBytes: [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74],
            usesUTF8Flag: false,
            content: Data("hello gbk".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: zipURL)
        XCTAssertEqual(snapshot.entries.count, 1)
        let entry = snapshot.entries[0]
        XCTAssertTrue(entry.entry.displayPath.hasSuffix(".txt"))
        XCTAssertEqual(entry.entry.rawPath.bytes, [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74])
        XCTAssertFalse(entry.usesUTF8FileName)

        let data = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1024)
        XCTAssertEqual(data, Data("hello gbk".utf8))
    }

    func testOpenZIPWithShiftJISEncodedNames() async throws {
        let sjisBytes: [UInt8] = [0x83, 0x65, 0x83, 0x58, 0x83, 0x67, 0x2E, 0x74, 0x78, 0x74]
        let zipURL = try createZIPWithRawName(
            rawNameBytes: sjisBytes,
            usesUTF8Flag: false,
            content: Data("hello sjis".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: zipURL)
        XCTAssertEqual(snapshot.entries.count, 1)
        let entry = snapshot.entries[0]
        XCTAssertTrue(entry.entry.displayPath.hasSuffix(".txt"))
        XCTAssertEqual(entry.entry.rawPath.bytes, sjisBytes)
    }

    func testOpenZIPWithUTF8EmojiNames() async throws {
        let name = "\u{1F4C1}/\u{1F600}readme.txt"
        let zipURL = try createZIPWithRawName(
            rawNameBytes: Array(name.utf8),
            usesUTF8Flag: true,
            content: Data("emoji content".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: zipURL)
        let fileEntries = snapshot.entries.filter { !$0.isDirectory }
        XCTAssertEqual(fileEntries.count, 1)
        XCTAssertTrue(fileEntries[0].entry.displayPath.contains("\u{1F600}"))
    }

    func testEncodingOverrideRedecodesNames() async throws {
        let gbkBytes: [UInt8] = [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74]
        let zipURL = try createZIPWithRawName(
            rawNameBytes: gbkBytes,
            usesUTF8Flag: false,
            content: Data("data".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: zipURL)

        // Override with GBK explicitly
        let overridden = await provider.setEncodingOverride(.gbk)
        XCTAssertNotNil(overridden)
        let gbkDisplay = overridden!.entries[0].entry.displayPath
        XCTAssertTrue(gbkDisplay.hasSuffix(".txt"))

        // Override with Shift-JIS - different interpretation
        let sjisOverridden = await provider.setEncodingOverride(.shiftJIS)
        XCTAssertNotNil(sjisOverridden)
        let sjisDisplay = sjisOverridden!.entries[0].entry.displayPath
        XCTAssertNotEqual(gbkDisplay, sjisDisplay)

        // Raw bytes must remain unchanged regardless of override
        XCTAssertEqual(overridden!.entries[0].entry.rawPath.bytes, gbkBytes)
        XCTAssertEqual(sjisOverridden!.entries[0].entry.rawPath.bytes, gbkBytes)
    }

    func testRawBytesPreservedAfterEditorSave() async throws {
        let gbkBytes: [UInt8] = [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74]
        let zipURL = try createZIPWithTwoEntries(
            rawName1: gbkBytes, usesUTF8Flag1: false, content1: Data("gbk data".utf8),
            rawName2: Array("normal.txt".utf8), usesUTF8Flag2: true, content2: Data("normal data".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let editor = ArchiveEditor()
        try await editor.open(url: zipURL)
        try await editor.stage(.remove(entryPath: "normal.txt"))

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "encoding-preserve-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try await editor.saveAs(to: outputURL)

        let reader = try ZIPBridgeReader(url: outputURL)
        let entries = try reader.allEntries(maximumCount: 100)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].nameBytes, gbkBytes)
        XCTAssertFalse(entries[0].usesUTF8FileName)
    }

    func testRenamedEntryGetsUTF8Encoding() async throws {
        let gbkBytes: [UInt8] = [0xB2, 0xE2, 0xCA, 0xD4, 0x2E, 0x74, 0x78, 0x74]
        let zipURL = try createZIPWithRawName(
            rawNameBytes: gbkBytes,
            usesUTF8Flag: false,
            content: Data("data".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let editor = ArchiveEditor()
        try await editor.open(url: zipURL)

        let detector = EncodingDetector()
        let decodedName = detector.detect(rawBytes: gbkBytes, usesUTF8Flag: false).decodedName
        try await editor.stage(.rename(from: decodedName, to: "renamed.txt"))

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "encoding-rename-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try await editor.saveAs(to: outputURL)

        let reader = try ZIPBridgeReader(url: outputURL)
        let entries = try reader.allEntries(maximumCount: 100)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].nameBytes, Array("renamed.txt".utf8))
        XCTAssertTrue(entries[0].usesUTF8FileName)
    }

    func testSupplementaryPlaneCharactersPreservedThroughSave() async throws {
        let name = "\u{2000B}file.txt"
        let zipURL = try createZIPWithRawName(
            rawNameBytes: Array(name.utf8),
            usesUTF8Flag: true,
            content: Data("supplementary".utf8)
        )
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let editor = ArchiveEditor()
        try await editor.open(url: zipURL)

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "encoding-supp-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try await editor.saveAs(to: outputURL)

        let reader = try ZIPBridgeReader(url: outputURL)
        let entries = try reader.allEntries(maximumCount: 100)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].nameBytes, Array(name.utf8))
        XCTAssertTrue(entries[0].usesUTF8FileName)
    }

    // MARK: - ZIP construction helpers

    private func createZIPWithRawName(
        rawNameBytes: [UInt8],
        usesUTF8Flag: Bool,
        content: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "encoding-test-\(UUID().uuidString).zip")

        var writer: OpaquePointer?
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return awb_mz_writer_open(path, &writer)
        }
        guard status == AWB_MZ_OK, writer != nil else {
            throw NSError(domain: "Test", code: 1)
        }

        let entryStatus = rawNameBytes.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return awb_mz_writer_open_entry_raw(
                writer, base, UInt16(rawNameBytes.count),
                usesUTF8Flag ? 1 : 0, UInt64(content.count),
                Int64(Date().timeIntervalSince1970)
            )
        }
        guard entryStatus == AWB_MZ_OK else {
            _ = awb_mz_writer_close(&writer)
            throw NSError(domain: "Test", code: 2)
        }

        let writeStatus = content.withUnsafeBytes { rawBuffer -> Int32 in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return awb_mz_writer_write_entry(writer, base, Int32(content.count))
        }
        guard writeStatus == Int32(content.count) else {
            _ = awb_mz_writer_close(&writer)
            throw NSError(domain: "Test", code: 3)
        }

        _ = awb_mz_writer_close_entry(writer)
        let closeStatus = awb_mz_writer_close(&writer)
        guard closeStatus == AWB_MZ_OK else {
            throw NSError(domain: "Test", code: 4)
        }
        return url
    }

    private func createZIPWithTwoEntries(
        rawName1: [UInt8], usesUTF8Flag1: Bool, content1: Data,
        rawName2: [UInt8], usesUTF8Flag2: Bool, content2: Data
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "encoding-test2-\(UUID().uuidString).zip")

        var writer: OpaquePointer?
        let status = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return awb_mz_writer_open(path, &writer)
        }
        guard status == AWB_MZ_OK, writer != nil else {
            throw NSError(domain: "Test", code: 1)
        }

        // Entry 1
        let s1 = rawName1.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return awb_mz_writer_open_entry_raw(
                writer, base, UInt16(rawName1.count),
                usesUTF8Flag1 ? 1 : 0, UInt64(content1.count),
                Int64(Date().timeIntervalSince1970)
            )
        }
        guard s1 == AWB_MZ_OK else { _ = awb_mz_writer_close(&writer); throw NSError(domain: "Test", code: 2) }
        _ = content1.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return awb_mz_writer_write_entry(writer, base, Int32(content1.count))
        }
        _ = awb_mz_writer_close_entry(writer)

        // Entry 2
        let s2 = rawName2.withUnsafeBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return awb_mz_writer_open_entry_raw(
                writer, base, UInt16(rawName2.count),
                usesUTF8Flag2 ? 1 : 0, UInt64(content2.count),
                Int64(Date().timeIntervalSince1970)
            )
        }
        guard s2 == AWB_MZ_OK else { _ = awb_mz_writer_close(&writer); throw NSError(domain: "Test", code: 3) }
        _ = content2.withUnsafeBytes { buf -> Int32 in
            guard let base = buf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return awb_mz_writer_write_entry(writer, base, Int32(content2.count))
        }
        _ = awb_mz_writer_close_entry(writer)

        let closeStatus = awb_mz_writer_close(&writer)
        guard closeStatus == AWB_MZ_OK else { throw NSError(domain: "Test", code: 4) }
        return url
    }
}
