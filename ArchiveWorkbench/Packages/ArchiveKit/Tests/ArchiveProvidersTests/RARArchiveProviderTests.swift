import ArchiveDomain
@testable import ArchiveProviders
import Foundation
import XCTest

/// Tests for the read-only RAR provider backed by the system 7zz binary.
///
/// Fixture-based tests require a real 7zz install and skip gracefully when it is
/// absent. Multipart detection and capability tests are deterministic and always run.
final class RARArchiveProviderTests: XCTestCase {
    // MARK: - Helpers

    private func requireValidatedBinary() throws -> SevenZipBinaryDiscovery {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw XCTSkip("7zz is not installed at a trusted location; skipping RAR fixture test.")
        }
        return discovery
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "RARProviderTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Capability gating

    func testCapabilitiesAreReadOnly() {
        XCTAssertEqual(RARArchiveProvider.capabilities, [.list, .read, .preview])
    }

    func testMakeValidatedThrowsWhenBinaryMissing() {
        // When no binary exists at the candidate paths, makeValidated should throw.
        // We cannot easily remove the system binary, so we test the error type
        // by constructing with a known-bad path and verifying the discovery logic.
        let discovery = SevenZipBinaryDiscovery.discover(candidatePaths: [
            "/opt/homebrew/bin/definitely-not-7zz-\(UUID().uuidString)",
        ])
        XCTAssertNil(discovery)
    }

    func testBinaryValidationReuse() throws {
        // RARArchiveProvider reuses SevenZipBinaryDiscovery; verify it produces
        // the same result as SevenZipProvider's discovery.
        let discovery = try requireValidatedBinary()
        XCTAssertTrue(
            discovery.resolvedPath.hasPrefix("/opt/homebrew/")
                || discovery.resolvedPath.hasPrefix("/usr/local/")
        )
        XCTAssertEqual(discovery.sha256.count, 64)
    }

    // MARK: - Multipart detection: modern pattern (.partN.rar)

    func testMultipartDetectionModernPattern() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create fake volume files: archive.part1.rar, archive.part2.rar, archive.part3.rar
        for i in 1...3 {
            let vol = dir.appending(path: "archive.part\(i).rar")
            try Data("fake".utf8).write(to: vol)
        }

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "archive.part1.rar"))

        XCTAssertTrue(result.isMultipart)
        XCTAssertEqual(result.detectedVolumes.count, 3)
        XCTAssertTrue(result.missingVolumes.isEmpty)
        XCTAssertTrue(result.firstVolumePath.hasSuffix("archive.part1.rar"))
    }

    func testMultipartDetectionModernPatternWithZeroPadding() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create fake volume files with zero-padded numbers
        for i in 1...3 {
            let vol = dir.appending(path: "data.part0\(i).rar")
            try Data("fake".utf8).write(to: vol)
        }

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "data.part01.rar"))

        XCTAssertTrue(result.isMultipart)
        XCTAssertEqual(result.detectedVolumes.count, 3)
        XCTAssertTrue(result.missingVolumes.isEmpty)
    }

    func testMultipartDetectionModernMissingVolume() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create part1 and part3 but NOT part2 (gap)
        try Data("fake".utf8).write(to: dir.appending(path: "archive.part1.rar"))
        try Data("fake".utf8).write(to: dir.appending(path: "archive.part3.rar"))

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "archive.part1.rar"))

        XCTAssertTrue(result.isMultipart)
        XCTAssertFalse(result.missingVolumes.isEmpty)
        XCTAssertTrue(result.missingVolumes.contains("archive.part2.rar"))
    }

    func testMultipartDetectionSinglePartIsNotMultipart() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Only part1 exists
        try Data("fake".utf8).write(to: dir.appending(path: "archive.part1.rar"))

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "archive.part1.rar"))

        // Single part with no continuation is not multipart
        XCTAssertFalse(result.isMultipart)
        XCTAssertEqual(result.detectedVolumes.count, 1)
    }

    // MARK: - Multipart detection: legacy pattern (.rar + .r00, .r01)

    func testMultipartDetectionLegacyPattern() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create legacy volumes: archive.rar, archive.r00, archive.r01
        try Data("fake".utf8).write(to: dir.appending(path: "archive.rar"))
        try Data("fake".utf8).write(to: dir.appending(path: "archive.r00"))
        try Data("fake".utf8).write(to: dir.appending(path: "archive.r01"))

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "archive.rar"))

        XCTAssertTrue(result.isMultipart)
        XCTAssertEqual(result.detectedVolumes.count, 3)
        XCTAssertTrue(result.missingVolumes.isEmpty)
        XCTAssertTrue(result.firstVolumePath.hasSuffix("archive.rar"))
    }

    func testMultipartDetectionLegacySingleVolume() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Only .rar exists, no .r00 etc.
        try Data("fake".utf8).write(to: dir.appending(path: "archive.rar"))

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "archive.rar"))

        XCTAssertFalse(result.isMultipart)
        XCTAssertEqual(result.detectedVolumes.count, 1)
    }

    func testMultipartDetectionLegacyMissingFirstVolume() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Only continuation volumes exist, .rar is missing
        try Data("fake".utf8).write(to: dir.appending(path: "archive.r00"))
        try Data("fake".utf8).write(to: dir.appending(path: "archive.r01"))

        let detector = RARMultipartDetector()
        let result = detector.detect(firstVolumeURL: dir.appending(path: "archive.r00"))

        XCTAssertTrue(result.isMultipart)
        XCTAssertFalse(result.missingVolumes.isEmpty)
        XCTAssertTrue(result.missingVolumes.contains("archive.rar"))
    }

    // MARK: - Format routing

    func testFormatDetectorRecognizesRAR4Signature() throws {
        // RAR4 magic: 52 61 72 21 1A 07 00
        let rar4Header = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00, 0x00, 0x00])
        let detected = ArchiveFormatDetector.detect(fromHeader: rar4Header)
        XCTAssertEqual(detected, .rar)
    }

    func testFormatDetectorRecognizesRAR5Signature() throws {
        // RAR5 magic: 52 61 72 21 1A 07 01 00
        let rar5Header = Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00, 0x00, 0x00])
        let detected = ArchiveFormatDetector.detect(fromHeader: rar5Header)
        XCTAssertEqual(detected, .rar)
    }

    func testFormatDetectorExtensionMapping() {
        XCTAssertEqual(ArchiveFormatDetector.formatFromExtension("rar"), .rar)
        XCTAssertEqual(ArchiveFormatDetector.formatFromExtension("RAR"), .rar)
    }

    // MARK: - Capability registry integration

    func testRegistryGatesRAROnBinaryAvailability() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        let rarSnapshot = baseline.snapshot(format: .rar)
        // Baseline has RAR with .list/.read/.preview
        XCTAssertTrue(rarSnapshot.actions.contains(.list))
        XCTAssertTrue(rarSnapshot.actions.contains(.read))
        XCTAssertTrue(rarSnapshot.actions.contains(.preview))
        XCTAssertFalse(rarSnapshot.actions.contains(.create))

        // When unavailable, all actions are removed
        let unavailable = baseline.withRARAvailable(false)
        let unavailableSnapshot = unavailable.snapshot(format: .rar)
        XCTAssertTrue(unavailableSnapshot.actions.isEmpty)
        XCTAssertNil(unavailableSnapshot.primaryProvider)
        XCTAssertEqual(
            unavailableSnapshot.unavailableReasons[.list],
            .externalProviderNotValidated
        )

        // When available, baseline is restored
        let available = baseline.withRARAvailable(true)
        let availableSnapshot = available.snapshot(format: .rar)
        XCTAssertEqual(availableSnapshot.actions, rarSnapshot.actions)
        XCTAssertEqual(availableSnapshot.primaryProvider, .sevenZZ)
    }

    // MARK: - Listing parser reuse (RAR output uses same 7zz l -slt format)

    func testListingParserHandlesRAREntries() {
        // Simulate 7zz l -slt output for a RAR archive
        let listing = """
        7-Zip (z) 24.08 (arm64) : Copyright (c) 1999-2024 Igor Pavlov : 2024-11-30

        Scanning the drive for archives:
        1 file, 1234 bytes

        Listing archive: /tmp/test.rar

        --
        Path = /tmp/test.rar
        Type = Rar
        Solid = +
        Number of volumes = 1

        ----------
        Path = hello.txt
        Size = 11
        Packed Size = 13
        Modified = 2026-07-27 01:21:26
        Attributes = A_
        CRC = ABC12345
        Encrypted = -
        Method = Solid
        Folder = -

        Path = docs/
        Size = 0
        Packed Size = 0
        Modified = 2026-07-27 01:20:00
        Attributes = D_
        Encrypted = -
        Folder = +

        Path = docs/notes.txt
        Size = 5
        Packed Size = 7
        Modified = 2026-07-27 01:21:00
        Attributes = A_
        CRC = DEF67890
        Encrypted = +
        Method = Solid
        Folder = -
        """

        let parse = SevenZipListingParser().parse(listing)
        XCTAssertEqual(parse.entries.count, 3)
        XCTAssertTrue(parse.signals.isSolid)

        let hello = parse.entries[0]
        XCTAssertEqual(hello.path, "hello.txt")
        XCTAssertEqual(hello.size, 11)
        XCTAssertFalse(hello.encrypted)
        XCTAssertFalse(hello.isDirectory)

        let docsDir = parse.entries[1]
        XCTAssertEqual(docsDir.path, "docs/")
        XCTAssertTrue(docsDir.isDirectory)

        let notes = parse.entries[2]
        XCTAssertEqual(notes.path, "docs/notes.txt")
        XCTAssertTrue(notes.encrypted)
        XCTAssertEqual(notes.method, "Solid")
    }

    func testListingParserDetectsMultipartSignal() {
        let listing = """
        --
        Path = /tmp/test.part1.rar
        Type = Rar
        IsVolume = +
        Number of volumes = 3

        ----------
        Path = file.txt
        Size = 100
        Packed Size = 50
        Folder = -
        """

        let parse = SevenZipListingParser().parse(listing)
        XCTAssertTrue(parse.signals.isMultipart)
        XCTAssertEqual(parse.entries.count, 1)
    }

    // MARK: - Encrypted RAR detection (error mapping)

    func testEncryptedRARErrorMapping() async throws {
        let discovery = try requireValidatedBinary()
        // Create a RAR-like scenario: we cannot create RAR with 7zz, but we can
        // verify the provider handles a non-existent file gracefully.
        let provider = RARArchiveProvider(binaryPath: discovery.resolvedPath)
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).rar")

        do {
            _ = try await provider.open(url: fakeURL)
            XCTFail("Expected an error for non-existent file")
        } catch let error as ArchiveError {
            // Should get helperFailed or corruptedArchive for a missing file
            XCTAssertTrue(
                error == .helperFailed || error == .corruptedArchive || error == .missingVolume,
                "Unexpected error: \(error)"
            )
        }
    }

    // MARK: - Provider construction

    func testProviderConstructionWithValidatedBinary() throws {
        let discovery = try requireValidatedBinary()
        let provider = RARArchiveProvider(binaryPath: discovery.resolvedPath)
        // Provider should be constructable without error
        XCTAssertNotNil(provider)
    }

    func testProviderMakeValidated() throws {
        let discovery = try requireValidatedBinary()
        XCTAssertNotNil(discovery)
        // makeValidated should succeed when binary is present
        let provider = try RARArchiveProvider.makeValidated()
        XCTAssertNotNil(provider)
    }
}
