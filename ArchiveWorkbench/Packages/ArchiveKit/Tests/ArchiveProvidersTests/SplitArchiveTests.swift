import ArchiveDomain
@testable import ArchiveProviders
import Foundation
import XCTest

final class SplitArchiveTests: XCTestCase {

    // MARK: - SplitVolumeSize Tests

    func testVolumeSizePresets() {
        XCTAssertEqual(SplitVolumeSize.none.byteSize, nil)
        XCTAssertEqual(SplitVolumeSize.mb4.byteSize, 4 * 1024 * 1024)
        XCTAssertEqual(SplitVolumeSize.mb10.byteSize, 10 * 1024 * 1024)
        XCTAssertEqual(SplitVolumeSize.mb100.byteSize, 100 * 1024 * 1024)
        XCTAssertEqual(SplitVolumeSize.gb1.byteSize, 1024 * 1024 * 1024)
        XCTAssertEqual(SplitVolumeSize.custom(bytes: 5_000_000).byteSize, 5_000_000)
    }

    func testVolumeSizeDisplayLabels() {
        XCTAssertEqual(SplitVolumeSize.none.displayLabel, "无")
        XCTAssertEqual(SplitVolumeSize.mb4.displayLabel, "4 MB")
        XCTAssertEqual(SplitVolumeSize.mb10.displayLabel, "10 MB")
        XCTAssertEqual(SplitVolumeSize.mb100.displayLabel, "100 MB")
        XCTAssertEqual(SplitVolumeSize.gb1.displayLabel, "1 GB")
        XCTAssertEqual(SplitVolumeSize.custom(bytes: 5 * 1024 * 1024).displayLabel, "5 MB")
    }

    func testEstimatedVolumeCount() {
        // 10 MB input with 4 MB volumes: ~7 MB compressed -> 2 volumes
        let estimate = SplitVolumeSize.mb4.estimatedVolumeCount(totalBytes: 10 * 1024 * 1024)
        XCTAssertNotNil(estimate)
        XCTAssertGreaterThanOrEqual(estimate!, 1)
        XCTAssertLessThanOrEqual(estimate!, 3)

        // No splitting returns nil
        XCTAssertNil(SplitVolumeSize.none.estimatedVolumeCount(totalBytes: 10 * 1024 * 1024))

        // Zero input returns nil
        XCTAssertNil(SplitVolumeSize.mb4.estimatedVolumeCount(totalBytes: 0))
    }

    func testMinimumVolumeSize() {
        XCTAssertEqual(SplitVolumeSize.minimumBytes, 64 * 1024)
    }

    // MARK: - SplitVolumeResolver Detection Tests

    func testDetectsZipSpanningPattern() {
        let resolver = SplitVolumeResolver()
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.z01")))
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.z02")))
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.z99")))
        XCTAssertFalse(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.zip")))
        XCTAssertFalse(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.txt")))
    }

    func testDetectsNumberedSuffixPattern() {
        let resolver = SplitVolumeResolver()
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.7z.001")))
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.zip.001")))
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.rar.002")))
        XCTAssertFalse(resolver.isSplitVolume(URL(fileURLWithPath: "/tmp/archive.7z")))
    }

    // MARK: - SplitVolumeResolver Resolution Tests

    func testResolvesZipSpanningSetWithMissingVolume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Create .z01 and .zip but NOT .z02 (gap)
        try Data("vol1".utf8).write(to: directory.appendingPathComponent("test.z01"))
        try Data("vol3-final".utf8).write(to: directory.appendingPathComponent("test.zip"))
        // .z02 is missing — but since .z03 doesn't exist either, the resolver
        // will see .z01 then stop (no gap detected because there's no .z03).
        // Let's create .z03 to force a gap detection:
        try Data("vol3".utf8).write(to: directory.appendingPathComponent("test.z03"))

        let resolver = SplitVolumeResolver()
        let resolution = resolver.resolve(url: directory.appendingPathComponent("test.z01"))
        XCTAssertNotNil(resolution)
        XCTAssertEqual(resolution?.pattern, .zipSpanning)
        XCTAssertTrue(resolution!.hasMissingVolumes)
        XCTAssertTrue(resolution!.missingVolumes.contains { $0.lastPathComponent == "test.z02" })
    }

    func testResolvesCompleteZipSpanningSet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("vol1".utf8).write(to: directory.appendingPathComponent("test.z01"))
        try Data("vol2".utf8).write(to: directory.appendingPathComponent("test.z02"))
        try Data("final".utf8).write(to: directory.appendingPathComponent("test.zip"))

        let resolver = SplitVolumeResolver()
        let resolution = resolver.resolve(url: directory.appendingPathComponent("test.z01"))
        XCTAssertNotNil(resolution)
        XCTAssertEqual(resolution?.pattern, .zipSpanning)
        XCTAssertFalse(resolution!.hasMissingVolumes)
        XCTAssertEqual(resolution?.volumeURLs.count, 3) // .z01, .z02, .zip
        XCTAssertEqual(resolution?.primaryURL.lastPathComponent, "test.zip")
    }

    func testResolvesNumberedSuffixSet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("vol1".utf8).write(to: directory.appendingPathComponent("data.7z.001"))
        try Data("vol2".utf8).write(to: directory.appendingPathComponent("data.7z.002"))
        try Data("vol3".utf8).write(to: directory.appendingPathComponent("data.7z.003"))

        let resolver = SplitVolumeResolver()
        let resolution = resolver.resolve(url: directory.appendingPathComponent("data.7z.001"))
        XCTAssertNotNil(resolution)
        XCTAssertEqual(resolution?.pattern, .numberedSuffix)
        XCTAssertFalse(resolution!.hasMissingVolumes)
        XCTAssertEqual(resolution?.volumeURLs.count, 3)
        XCTAssertEqual(resolution?.primaryURL.lastPathComponent, "data.7z.001")
    }

    func testResolvesNumberedSuffixWithMissingVolume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("vol1".utf8).write(to: directory.appendingPathComponent("data.7z.001"))
        // .002 is missing
        try Data("vol3".utf8).write(to: directory.appendingPathComponent("data.7z.003"))

        let resolver = SplitVolumeResolver()
        let resolution = resolver.resolve(url: directory.appendingPathComponent("data.7z.001"))
        XCTAssertNotNil(resolution)
        XCTAssertTrue(resolution!.hasMissingVolumes)
        XCTAssertTrue(resolution!.missingVolumes.contains { $0.lastPathComponent == "data.7z.002" })
    }

    func testNonSplitFileReturnsNil() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("single".utf8).write(to: directory.appendingPathComponent("archive.zip"))

        let resolver = SplitVolumeResolver()
        let resolution = resolver.resolve(url: directory.appendingPathComponent("archive.zip"))
        XCTAssertNil(resolution)
    }

    // MARK: - Split ZIP Creation Tests

    func testSplitZIPCreationProducesMultipleVolumes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitCreate-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("split.zip")
        // Use a very small volume size to force multiple volumes
        let volumeSize = SplitVolumeSize.custom(bytes: SplitVolumeSize.minimumBytes)

        let writer = try SplitZIPWriter(url: outputURL, volumeSize: volumeSize)

        // Write enough data to span multiple volumes (>64KB)
        let payload = Data(repeating: 0x42, count: 200_000)
        try writer.openEntry(name: "bigfile.bin", uncompressedSize: UInt64(payload.count), modifiedUnixTime: 1700000000)
        try writer.writeChunk(payload)
        try writer.closeEntry()

        let result = try writer.finish()

        // Should have created multiple volumes
        XCTAssertGreaterThanOrEqual(result.volumeCount, 2)
        // Last volume should be .zip
        XCTAssertEqual(result.volumeURLs.last?.pathExtension, "zip")
        // Preceding volumes should be .z01, .z02, etc.
        if result.volumeCount > 1 {
            XCTAssertEqual(result.volumeURLs.first?.pathExtension, "z01")
        }
        // All volumes should exist on disk
        for volumeURL in result.volumeURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: volumeURL.path),
                          "Volume should exist: \(volumeURL.lastPathComponent)")
        }
        XCTAssertGreaterThan(result.totalBytes, 0)
    }

    func testSplitZIPCreationAndReading() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitRoundTrip-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("roundtrip.zip")
        let volumeSize = SplitVolumeSize.custom(bytes: SplitVolumeSize.minimumBytes)

        // Create split archive
        let writer = try SplitZIPWriter(url: outputURL, volumeSize: volumeSize)
        let payload = Data("Split archive content for round-trip test".utf8)
        // Write enough data to force splitting
        let largePayload = Data(repeating: 0x41, count: 150_000) + payload
        try writer.openEntry(name: "data/content.bin", uncompressedSize: UInt64(largePayload.count), modifiedUnixTime: 1700000000)
        try writer.writeChunk(largePayload)
        try writer.closeEntry()
        let result = try writer.finish()

        XCTAssertGreaterThanOrEqual(result.volumeCount, 2)

        // Read back via the final .zip segment
        let reader = try ZIPBridgeReader(url: outputURL)
        let entries = try reader.allEntries(maximumCount: 100)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(String(bytes: entries[0].nameBytes, encoding: .utf8), "data/content.bin")
        XCTAssertEqual(entries[0].uncompressedSize, UInt64(largePayload.count))

        // Read the entry data back
        let data = try reader.readEntry(ordinal: 0, expectedSize: entries[0].uncompressedSize, maximumBytes: entries[0].uncompressedSize)
        XCTAssertEqual(data, largePayload)
    }

    func testSplitZIPWriterRejectsTooSmallVolumeSize() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitReject-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let outputURL = directory.appendingPathComponent("bad.zip")
        // .none has no byte size
        XCTAssertThrowsError(try SplitZIPWriter(url: outputURL, volumeSize: .none))
        // Custom below minimum
        XCTAssertThrowsError(try SplitZIPWriter(url: outputURL, volumeSize: .custom(bytes: 1024)))
    }

    // MARK: - Missing Volume Detection Tests

    func testMissingVolumeThrowsCorrectError() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitMissing-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Create a split set, then remove a volume.
        // Use pseudo-random data that deflate cannot compress, forcing true multi-volume output.
        let outputURL = directory.appendingPathComponent("incomplete.zip")
        let volumeSize = SplitVolumeSize.custom(bytes: SplitVolumeSize.minimumBytes)
        let writer = try SplitZIPWriter(url: outputURL, volumeSize: volumeSize)
        var state: UInt64 = 0xdeadbeefcafe1234
        let largePayload = Data((0..<200_000).map { _ in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return UInt8(truncatingIfNeeded: state)
        })
        try writer.openEntry(name: "file.bin", uncompressedSize: UInt64(largePayload.count), modifiedUnixTime: 1700000000)
        try writer.writeChunk(largePayload)
        try writer.closeEntry()
        let result = try writer.finish()

        guard result.volumeCount >= 2 else {
            XCTFail("Expected at least 2 volumes for this test")
            return
        }

        // Remove the first volume (.z01)
        let firstVolume = result.volumeURLs[0]
        try FileManager.default.removeItem(at: firstVolume)

        // Attempting to open should detect the missing volume
        let provider = ZIPArchiveProvider()
        do {
            _ = try await provider.open(url: outputURL)
            XCTFail("Expected missingVolume error")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .missingVolume)
        }
    }

    // MARK: - SplitArchiveError Tests

    func testSplitArchiveErrorMapping() {
        XCTAssertEqual(
            SplitArchiveError.missingVolumes(names: ["a.z01"], message: "missing").archiveError,
            .missingVolume
        )
        XCTAssertEqual(
            SplitArchiveError.corruptedVolume(name: "a.z02").archiveError,
            .corruptedArchive
        )
        XCTAssertEqual(
            SplitArchiveError.invalidVolumeSize(requested: 100, minimum: 65536).archiveError,
            .resourceLimit
        )
    }

    // MARK: - Volume Enumeration Tests

    func testEnumerateVolumesForFinalSegment() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitEnum-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Create fake volume files
        try Data("1".utf8).write(to: directory.appendingPathComponent("test.z01"))
        try Data("2".utf8).write(to: directory.appendingPathComponent("test.z02"))
        try Data("3".utf8).write(to: directory.appendingPathComponent("test.z03"))
        try Data("final".utf8).write(to: directory.appendingPathComponent("test.zip"))

        let volumes = SplitZIPWriter.enumerateVolumes(
            forFinalSegment: directory.appendingPathComponent("test.zip")
        )
        XCTAssertEqual(volumes.count, 4)
        XCTAssertEqual(volumes.map(\.lastPathComponent), ["test.z01", "test.z02", "test.z03", "test.zip"])
    }

    // MARK: - 7z Split Volume Detection (SevenZipProvider)

    func testSevenZipProviderDetectsSplitVolumePattern() {
        // The SevenZipProvider.looksLikeSplitVolume is private, but we can test
        // the pattern detection through the public SplitVolumeResolver
        let resolver = SplitVolumeResolver()
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/archives/backup.7z.001")))
        XCTAssertTrue(resolver.isSplitVolume(URL(fileURLWithPath: "/archives/backup.7z.002")))
        XCTAssertFalse(resolver.isSplitVolume(URL(fileURLWithPath: "/archives/backup.7z")))
    }

    // MARK: - Save As Complete Set Tests

    func testSaveAsProducesCompleteVolumeSet() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SplitSaveAs-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // First create a source archive
        let sourceURL = directory.appendingPathComponent("source.zip")
        let sourceWriter = try SplitZIPWriter(url: sourceURL, volumeSize: .custom(bytes: SplitVolumeSize.minimumBytes))
        let payload = Data(repeating: 0x44, count: 150_000)
        try sourceWriter.openEntry(name: "data.bin", uncompressedSize: UInt64(payload.count), modifiedUnixTime: 1700000000)
        try sourceWriter.writeChunk(payload)
        try sourceWriter.closeEntry()
        _ = try sourceWriter.finish()

        // Read source entries
        let sourceReader = try ZIPBridgeReader(url: sourceURL)
        let entries = try sourceReader.allEntries(maximumCount: 100)

        // Save As to a new location with split volumes
        let targetURL = directory.appendingPathComponent("copy.zip")
        let saveAs = SplitArchiveSaveAs()
        let entryTuples = entries.enumerated().map { (index, entry) in
            (
                nameBytes: entry.nameBytes,
                usesUTF8: entry.usesUTF8FileName,
                uncompressedSize: entry.uncompressedSize,
                modifiedUnixTime: entry.modifiedUnixTime,
                isDirectory: entry.isDirectory,
                ordinal: UInt64(index)
            )
        }
        let result = try saveAs.saveCompleteSet(
            sourceReader: sourceReader,
            targetURL: targetURL,
            volumeSize: .custom(bytes: SplitVolumeSize.minimumBytes),
            entries: entryTuples
        )

        // Verify complete set was created
        XCTAssertGreaterThanOrEqual(result.volumeCount, 1)
        for volumeURL in result.volumeURLs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: volumeURL.path))
        }

        // Verify the copy is readable
        let copyReader = try ZIPBridgeReader(url: targetURL)
        let copyEntries = try copyReader.allEntries(maximumCount: 100)
        XCTAssertEqual(copyEntries.count, 1)
        let copyData = try copyReader.readEntry(ordinal: 0, expectedSize: copyEntries[0].uncompressedSize, maximumBytes: copyEntries[0].uncompressedSize)
        XCTAssertEqual(copyData, payload)
    }
}
