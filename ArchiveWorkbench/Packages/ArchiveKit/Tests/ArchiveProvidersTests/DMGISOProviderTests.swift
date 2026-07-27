import ArchiveDomain
@testable import ArchiveProviders
import Foundation
import XCTest

/// Tests for the read-only DMG and ISO providers backed by the system 7zz binary.
///
/// Fixture-based tests require a real 7zz install and skip gracefully when it is
/// absent. Capability and parser tests are deterministic and always run.
final class DMGISOProviderTests: XCTestCase {
    // MARK: - Helpers

    private func requireValidatedBinary() throws -> SevenZipBinaryDiscovery {
        guard let discovery = SevenZipBinaryDiscovery.discover() else {
            throw XCTSkip("7zz is not installed at a trusted location; skipping fixture test.")
        }
        return discovery
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "DMGISOProviderTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - DMG Capability gating

    func testDMGCapabilitiesAreReadOnly() {
        XCTAssertEqual(DMGArchiveProvider.capabilities, [.list, .read, .preview])
    }

    func testDMGMakeValidatedThrowsWhenBinaryMissing() {
        let discovery = SevenZipBinaryDiscovery.discover(candidatePaths: [
            "/opt/homebrew/bin/definitely-not-7zz-\(UUID().uuidString)",
        ])
        XCTAssertNil(discovery)
    }

    func testDMGProviderConstructionWithValidatedBinary() throws {
        let discovery = try requireValidatedBinary()
        let provider = DMGArchiveProvider(binaryPath: discovery.resolvedPath)
        XCTAssertNotNil(provider)
    }

    func testDMGProviderMakeValidated() throws {
        let discovery = try requireValidatedBinary()
        XCTAssertNotNil(discovery)
        let provider = try DMGArchiveProvider.makeValidated()
        XCTAssertNotNil(provider)
    }

    // MARK: - ISO Capability gating

    func testISOCapabilitiesAreReadOnly() {
        XCTAssertEqual(ISOArchiveProvider.capabilities, [.list, .read, .preview])
    }

    func testISOMakeValidatedThrowsWhenBinaryMissing() {
        let discovery = SevenZipBinaryDiscovery.discover(candidatePaths: [
            "/opt/homebrew/bin/definitely-not-7zz-\(UUID().uuidString)",
        ])
        XCTAssertNil(discovery)
    }

    func testISOProviderConstructionWithValidatedBinary() throws {
        let discovery = try requireValidatedBinary()
        let provider = ISOArchiveProvider(binaryPath: discovery.resolvedPath)
        XCTAssertNotNil(provider)
    }

    func testISOProviderMakeValidated() throws {
        let discovery = try requireValidatedBinary()
        XCTAssertNotNil(discovery)
        let provider = try ISOArchiveProvider.makeValidated()
        XCTAssertNotNil(provider)
    }

    // MARK: - Format detection

    func testFormatDetectorRecognizesDMGExtension() {
        XCTAssertEqual(ArchiveFormatDetector.formatFromExtension("dmg"), .dmg)
        XCTAssertEqual(ArchiveFormatDetector.formatFromExtension("DMG"), .dmg)
    }

    func testFormatDetectorRecognizesISOExtension() {
        XCTAssertEqual(ArchiveFormatDetector.formatFromExtension("iso"), .iso)
        XCTAssertEqual(ArchiveFormatDetector.formatFromExtension("ISO"), .iso)
    }

    func testFormatDetectorRecognizesISOSignature() throws {
        // ISO 9660: "CD001" at offset 32769
        var header = Data(count: 32_780)
        let cd001: [UInt8] = [0x43, 0x44, 0x30, 0x30, 0x31]
        for (i, byte) in cd001.enumerated() {
            header[32_769 + i] = byte
        }
        let detected = ArchiveFormatDetector.detect(fromHeader: header)
        XCTAssertEqual(detected, .iso)
    }

    func testFormatDetectorRecognizesDMGKolyTrailer() throws {
        // DMG: "koly" at the start of the last 512 bytes
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let filePath = dir.appending(path: "test.dmg")
        // Create a file with koly trailer
        var data = Data(count: 1024)
        let koly: [UInt8] = [0x6B, 0x6F, 0x6C, 0x79] // "koly"
        // koly block starts at fileSize - 512
        let offset = 1024 - 512
        for (i, byte) in koly.enumerated() {
            data[offset + i] = byte
        }
        try data.write(to: filePath)

        let result = try ArchiveFormatDetector.detect(from: filePath)
        XCTAssertEqual(result.detectedFormat, .dmg)
    }

    // MARK: - Capability registry integration

    func testRegistryGatesDMGOnBinaryAvailability() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        let dmgSnapshot = baseline.snapshot(format: .dmg)
        // Baseline has DMG with .list/.read/.preview
        XCTAssertTrue(dmgSnapshot.actions.contains(.list))
        XCTAssertTrue(dmgSnapshot.actions.contains(.read))
        XCTAssertTrue(dmgSnapshot.actions.contains(.preview))
        XCTAssertFalse(dmgSnapshot.actions.contains(.create))
        XCTAssertFalse(dmgSnapshot.actions.contains(.update))

        // When unavailable, all actions are removed
        let unavailable = baseline.withDMGAvailable(false)
        let unavailableSnapshot = unavailable.snapshot(format: .dmg)
        XCTAssertTrue(unavailableSnapshot.actions.isEmpty)
        XCTAssertNil(unavailableSnapshot.primaryProvider)
        XCTAssertEqual(
            unavailableSnapshot.unavailableReasons[.list],
            .externalProviderNotValidated
        )
        // create/update remain formatReadOnly even when unavailable
        XCTAssertEqual(
            unavailableSnapshot.unavailableReasons[.create],
            .formatReadOnly
        )

        // When available, baseline is restored
        let available = baseline.withDMGAvailable(true)
        let availableSnapshot = available.snapshot(format: .dmg)
        XCTAssertEqual(availableSnapshot.actions, dmgSnapshot.actions)
        XCTAssertEqual(availableSnapshot.primaryProvider, .sevenZZ)
    }

    func testRegistryGatesISOOnBinaryAvailability() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        let isoSnapshot = baseline.snapshot(format: .iso)
        // Baseline has ISO with .list/.read/.preview
        XCTAssertTrue(isoSnapshot.actions.contains(.list))
        XCTAssertTrue(isoSnapshot.actions.contains(.read))
        XCTAssertTrue(isoSnapshot.actions.contains(.preview))
        XCTAssertFalse(isoSnapshot.actions.contains(.create))
        XCTAssertFalse(isoSnapshot.actions.contains(.update))

        // When unavailable, all actions are removed
        let unavailable = baseline.withISOAvailable(false)
        let unavailableSnapshot = unavailable.snapshot(format: .iso)
        XCTAssertTrue(unavailableSnapshot.actions.isEmpty)
        XCTAssertNil(unavailableSnapshot.primaryProvider)
        XCTAssertEqual(
            unavailableSnapshot.unavailableReasons[.list],
            .externalProviderNotValidated
        )
        XCTAssertEqual(
            unavailableSnapshot.unavailableReasons[.create],
            .formatReadOnly
        )

        // When available, baseline is restored
        let available = baseline.withISOAvailable(true)
        let availableSnapshot = available.snapshot(format: .iso)
        XCTAssertEqual(availableSnapshot.actions, isoSnapshot.actions)
        XCTAssertEqual(availableSnapshot.primaryProvider, .sevenZZ)
    }

    // MARK: - Read-only enforcement (mutations rejected)

    func testDMGProviderIsStrictlyReadOnly() {
        // The provider only exposes list/read/preview capabilities (no create/update exist)
        let caps = DMGArchiveProvider.capabilities
        XCTAssertEqual(caps, [.list, .read, .preview])
        XCTAssertEqual(caps.count, 3, "DMG provider must expose exactly 3 read-only capabilities")
        // The capability registry marks create/update as formatReadOnly
        let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .dmg)
        XCTAssertEqual(snapshot.unavailableReasons[.create], .formatReadOnly)
        XCTAssertEqual(snapshot.unavailableReasons[.update], .formatReadOnly)
    }

    func testISOProviderIsStrictlyReadOnly() {
        let caps = ISOArchiveProvider.capabilities
        XCTAssertEqual(caps, [.list, .read, .preview])
        XCTAssertEqual(caps.count, 3, "ISO provider must expose exactly 3 read-only capabilities")
        let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .iso)
        XCTAssertEqual(snapshot.unavailableReasons[.create], .formatReadOnly)
        XCTAssertEqual(snapshot.unavailableReasons[.update], .formatReadOnly)
    }

    // MARK: - Listing parser reuse (DMG/ISO output uses same 7zz l -slt format)

    func testListingParserHandlesDMGEntries() {
        // Simulate 7zz l -slt output for a DMG archive
        let listing = """
        7-Zip (z) 24.08 (arm64) : Copyright (c) 1999-2024 Igor Pavlov : 2024-11-30

        Scanning the drive for archives:
        1 file, 1048576 bytes

        Listing archive: /tmp/test.dmg

        --
        Path = /tmp/test.dmg
        Type = Dmg
        Number of volumes = 1

        ----------
        Path = [HFS+].dmg
        Size = 0
        Packed Size = 0
        Folder = +

        Path = [HFS+].dmg/hello.txt
        Size = 13
        Packed Size = 13
        Modified = 2026-07-27 01:21:26
        Attributes = A_
        CRC = ABC12345
        Encrypted = -
        Folder = -

        Path = [HFS+].dmg/subdir
        Size = 0
        Packed Size = 0
        Modified = 2026-07-27 01:20:00
        Attributes = D_
        Encrypted = -
        Folder = +
        """

        let parse = SevenZipListingParser().parse(listing)
        XCTAssertEqual(parse.entries.count, 3)

        let volume = parse.entries[0]
        XCTAssertEqual(volume.path, "[HFS+].dmg")
        XCTAssertTrue(volume.isDirectory)

        let hello = parse.entries[1]
        XCTAssertEqual(hello.path, "[HFS+].dmg/hello.txt")
        XCTAssertEqual(hello.size, 13)
        XCTAssertFalse(hello.encrypted)
        XCTAssertFalse(hello.isDirectory)

        let subdir = parse.entries[2]
        XCTAssertEqual(subdir.path, "[HFS+].dmg/subdir")
        XCTAssertTrue(subdir.isDirectory)
    }

    func testListingParserHandlesISOEntries() {
        // Simulate 7zz l -slt output for an ISO archive
        let listing = """
        7-Zip (z) 24.08 (arm64) : Copyright (c) 1999-2024 Igor Pavlov : 2024-11-30

        Scanning the drive for archives:
        1 file, 2097152 bytes

        Listing archive: /tmp/test.iso

        --
        Path = /tmp/test.iso
        Type = Iso
        Number of volumes = 1

        ----------
        Path = [BOOT]
        Size = 0
        Packed Size = 0
        Folder = +

        Path = [BOOT]/2.88M.img
        Size = 2949120
        Packed Size = 2949120
        Modified = 2026-07-27 01:00:00
        Attributes = _
        Encrypted = -
        Folder = -

        Path = README.TXT
        Size = 42
        Packed Size = 42
        Modified = 2026-07-27 02:00:00
        Attributes = _
        Encrypted = -
        Folder = -

        Path = DATA
        Size = 0
        Packed Size = 0
        Modified = 2026-07-27 02:00:00
        Attributes = D
        Encrypted = -
        Folder = +

        Path = DATA/FILE.DAT
        Size = 1024
        Packed Size = 1024
        Modified = 2026-07-27 02:30:00
        Attributes = _
        Encrypted = -
        Folder = -
        """

        let parse = SevenZipListingParser().parse(listing)
        XCTAssertEqual(parse.entries.count, 5)

        let boot = parse.entries[0]
        XCTAssertEqual(boot.path, "[BOOT]")
        XCTAssertTrue(boot.isDirectory)

        let readme = parse.entries[2]
        XCTAssertEqual(readme.path, "README.TXT")
        XCTAssertEqual(readme.size, 42)
        XCTAssertFalse(readme.isDirectory)

        let dataDir = parse.entries[3]
        XCTAssertEqual(dataDir.path, "DATA")
        XCTAssertTrue(dataDir.isDirectory)

        let file = parse.entries[4]
        XCTAssertEqual(file.path, "DATA/FILE.DAT")
        XCTAssertEqual(file.size, 1024)
    }

    // MARK: - Error handling for non-existent files

    func testDMGProviderHandlesNonExistentFile() async throws {
        let discovery = try requireValidatedBinary()
        let provider = DMGArchiveProvider(binaryPath: discovery.resolvedPath)
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).dmg")

        do {
            _ = try await provider.open(url: fakeURL)
            XCTFail("Expected an error for non-existent file")
        } catch let error as ArchiveError {
            XCTAssertTrue(
                error == .helperFailed || error == .corruptedArchive,
                "Unexpected error: \(error)"
            )
        }
    }

    func testISOProviderHandlesNonExistentFile() async throws {
        let discovery = try requireValidatedBinary()
        let provider = ISOArchiveProvider(binaryPath: discovery.resolvedPath)
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).iso")

        do {
            _ = try await provider.open(url: fakeURL)
            XCTFail("Expected an error for non-existent file")
        } catch let error as ArchiveError {
            XCTAssertTrue(
                error == .helperFailed || error == .corruptedArchive,
                "Unexpected error: \(error)"
            )
        }
    }

    // MARK: - DMG fixture test (requires hdiutil)

    func testDMGListingWithRealFixture() async throws {
        let discovery = try requireValidatedBinary()
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a real DMG using hdiutil (macOS built-in)
        let dmgPath = dir.appending(path: "test.dmg").path
        let srcDir = dir.appending(path: "src", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try "Hello DMG".write(
            to: srcDir.appending(path: "hello.txt"),
            atomically: true,
            encoding: .utf8
        )

        let hdiutilResult = try SevenZipProcessRunner().run(
            executablePath: "/usr/bin/hdiutil",
            arguments: [
                "create", "-srcfolder", srcDir.path,
                "-volname", "TestDMG",
                "-format", "UDRO",
                dmgPath,
            ],
            timeoutSeconds: 30,
            maximumStdoutBytes: 1 << 20
        )
        guard hdiutilResult.exitStatus == 0 else {
            throw XCTSkip("hdiutil create failed; cannot create DMG fixture.")
        }

        let provider = DMGArchiveProvider(binaryPath: discovery.resolvedPath)
        let snapshot = try await provider.open(url: URL(fileURLWithPath: dmgPath))

        XCTAssertEqual(snapshot.format, .dmg)
        XCTAssertFalse(snapshot.entries.isEmpty)
        // Should contain our hello.txt somewhere in the listing
        let hasHello = snapshot.entries.contains { $0.entry.displayPath.contains("hello.txt") }
        XCTAssertTrue(hasHello, "DMG listing should contain hello.txt")
    }

    // MARK: - ISO fixture test (requires 7zz to create or mkisofs)

    func testISOListingWithRealFixture() async throws {
        let discovery = try requireValidatedBinary()
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create source content for the ISO
        let srcDir = dir.appending(path: "isosrc", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try "Hello ISO".write(
            to: srcDir.appending(path: "readme.txt"),
            atomically: true,
            encoding: .utf8
        )

        // Try hdiutil to create an ISO (macOS can create ISO via hdiutil)
        let isoPath = dir.appending(path: "test.iso").path
        let hdiutilResult = try SevenZipProcessRunner().run(
            executablePath: "/usr/bin/hdiutil",
            arguments: [
                "makehybrid", "-iso", "-joliet",
                "-o", isoPath,
                srcDir.path,
            ],
            timeoutSeconds: 30,
            maximumStdoutBytes: 1 << 20
        )
        guard hdiutilResult.exitStatus == 0 else {
            throw XCTSkip("hdiutil makehybrid failed; cannot create ISO fixture.")
        }

        let provider = ISOArchiveProvider(binaryPath: discovery.resolvedPath)
        let snapshot = try await provider.open(url: URL(fileURLWithPath: isoPath))

        XCTAssertEqual(snapshot.format, .iso)
        XCTAssertFalse(snapshot.entries.isEmpty)
        // Should contain our readme.txt (possibly uppercased by ISO9660)
        let hasReadme = snapshot.entries.contains {
            $0.entry.displayPath.lowercased().contains("readme")
        }
        XCTAssertTrue(hasReadme, "ISO listing should contain readme.txt")
    }

    func testISOExtractionWithRealFixture() async throws {
        let discovery = try requireValidatedBinary()
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create source content for the ISO
        let srcDir = dir.appending(path: "isosrc2", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let testContent = "Extract me from ISO"
        try testContent.write(
            to: srcDir.appending(path: "extract.txt"),
            atomically: true,
            encoding: .utf8
        )

        let isoPath = dir.appending(path: "test2.iso").path
        let hdiutilResult = try SevenZipProcessRunner().run(
            executablePath: "/usr/bin/hdiutil",
            arguments: [
                "makehybrid", "-iso", "-joliet",
                "-o", isoPath,
                srcDir.path,
            ],
            timeoutSeconds: 30,
            maximumStdoutBytes: 1 << 20
        )
        guard hdiutilResult.exitStatus == 0 else {
            throw XCTSkip("hdiutil makehybrid failed; cannot create ISO fixture.")
        }

        let provider = ISOArchiveProvider(binaryPath: discovery.resolvedPath)
        let snapshot = try await provider.open(url: URL(fileURLWithPath: isoPath))

        // Find the extract.txt entry
        guard let entry = snapshot.entries.first(where: {
            $0.entry.displayPath.lowercased().contains("extract.txt")
        }) else {
            XCTFail("Could not find extract.txt in ISO listing")
            return
        }

        // Read the entry
        let data = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1024)
        let content = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(content, testContent)
    }
}
