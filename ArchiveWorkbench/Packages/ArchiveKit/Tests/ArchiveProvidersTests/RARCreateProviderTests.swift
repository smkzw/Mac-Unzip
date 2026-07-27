import ArchiveDomain
@testable import ArchiveProviders
import Foundation
import XCTest

/// Tests for the external RARLAB rar creation provider.
///
/// Since RARLAB rar is NOT installed on this machine, fixture-based creation
/// tests skip gracefully. Binary-validation, license-confirmation, version
/// parsing, and capability-gating tests are deterministic and always run.
final class RARCreateProviderTests: XCTestCase {
    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "RARCreateProviderTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Returns a validated rar discovery or skips the test when rar is missing.
    private func requireValidatedBinary() throws -> RARBinaryDiscovery {
        guard let discovery = RARBinaryDiscovery.discover() else {
            throw XCTSkip("RARLAB rar is not installed; skipping fixture test.")
        }
        return discovery
    }

    // MARK: - Binary discovery & validation (deterministic, no rar needed)

    func testDiscoverReturnsNilForMissingCandidates() {
        XCTAssertNil(RARBinaryDiscovery.discover(candidatePaths: [
            "/opt/homebrew/bin/definitely-not-rar-\(UUID().uuidString)",
            "/usr/local/bin/definitely-not-rar-\(UUID().uuidString)",
        ]))
    }

    func testDiscoverReturnsNilWhenRarNotInstalled() {
        // On this machine rar is NOT installed, so default discovery must fail.
        let defaults = UserDefaults(suiteName: "RARCreateProviderTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: "RARCreateProviderTests") }
        // Clear any user-configured path
        defaults.removeObject(forKey: RARBinaryDiscovery.userPathDefaultsKey)
        XCTAssertNil(RARBinaryDiscovery.discover(defaults: defaults))
    }

    func testValidationRejectsRelativePath() {
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: "relative/rar"))
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: "bin/rar"))
    }

    func testValidationRejectsDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: dir.path))
    }

    func testValidationRejectsNonexistentPath() {
        XCTAssertNil(RARBinaryDiscovery.validate(
            candidate: "/usr/local/bin/rar-nonexistent-\(UUID().uuidString)"
        ))
    }

    func testValidationRejectsBinaryOutsideTrustedPrefix() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Create an executable file outside trusted prefixes
        let fake = dir.appending(path: "rar")
        try Data("#!/bin/sh\necho RAR 7.0".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        // /private/var/... is not a trusted prefix
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: fake.path))
    }

    func testValidationRejectsSymlinkToWritableLocation() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Create a target file
        let target = dir.appending(path: "rar-target")
        try Data("fake".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        // Create a symlink pointing to it
        let link = dir.appending(path: "rar-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        // Both resolve outside trusted prefix, so both rejected
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: link.path))
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: target.path))
    }

    func testValidationRejectsWorldWritableBinary() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "rar")
        try Data("x".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: fake.path)
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: fake.path))
    }

    func testValidationRejectsGroupWritableBinary() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "rar")
        try Data("x".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: fake.path)
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: fake.path))
    }

    func testValidationRejectsNonExecutableFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "rar")
        try Data("x".utf8).write(to: fake)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fake.path)
        XCTAssertNil(RARBinaryDiscovery.validate(candidate: fake.path))
    }

    // MARK: - Architecture verification

    func testVerifyArm64RejectsNonMachOFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "rar")
        try Data("This is not a Mach-O binary".utf8).write(to: fake)
        XCTAssertFalse(RARBinaryDiscovery.verifyArm64(path: fake.path))
    }

    func testVerifyArm64RejectsEmptyFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "rar")
        try Data().write(to: fake)
        XCTAssertFalse(RARBinaryDiscovery.verifyArm64(path: fake.path))
    }

    func testVerifyArm64AcceptsRealArm64Binary() throws {
        // /usr/bin/true is a universal or arm64 binary on Apple Silicon
        let path = "/usr/bin/true"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("/usr/bin/true not available")
        }
        // On Apple Silicon this should be arm64 (or universal containing arm64)
        #if arch(arm64)
        XCTAssertTrue(RARBinaryDiscovery.verifyArm64(path: path))
        #endif
    }

    // MARK: - Version parsing

    func testParseVersionStandardOutput() {
        let output = """
        RAR 7.10   (64-bit)
        Copyright (c) 1993-2024 Alexander Roshal
        """
        let probe = RARBinaryDiscovery.parseVersion(output)
        XCTAssertNotNil(probe)
        XCTAssertEqual(probe?.version, "7.10")
        XCTAssertEqual(probe?.architecture, "arm64")
    }

    func testParseVersionWithBeta() {
        let output = "RAR 6.24 beta 1 (32-bit)"
        let probe = RARBinaryDiscovery.parseVersion(output)
        XCTAssertNotNil(probe)
        XCTAssertEqual(probe?.version, "6.24")
        XCTAssertEqual(probe?.architecture, "arm")
    }

    func testParseVersionNoRarString() {
        let output = "7-Zip (z) 24.08 (arm64)"
        let probe = RARBinaryDiscovery.parseVersion(output)
        XCTAssertNil(probe)
    }

    func testParseVersionEmpty() {
        XCTAssertNil(RARBinaryDiscovery.parseVersion(""))
    }

    // MARK: - License confirmation

    func testLicenseConfirmationFlow() {
        let suiteName = "RARCreateProviderTests-license-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let license = RARLicenseConfirmation(defaults: defaults)
        // Initially not confirmed
        XCTAssertFalse(license.isConfirmed)
        // Confirm
        license.confirm()
        XCTAssertTrue(license.isConfirmed)
        // Revoke
        license.revoke()
        XCTAssertFalse(license.isConfirmed)
    }

    func testLicenseConfirmationMessages() {
        XCTAssertFalse(RARLicenseConfirmation.confirmationMessage.isEmpty)
        XCTAssertFalse(RARLicenseConfirmation.confirmButton.isEmpty)
        XCTAssertFalse(RARLicenseConfirmation.cancelButton.isEmpty)
        XCTAssertTrue(RARLicenseConfirmation.confirmationMessage.contains("RARLAB"))
    }

    // MARK: - Provider availability gating

    func testMakeValidatedReturnsNilWhenRarNotInstalled() {
        let suiteName = "RARCreateProviderTests-avail-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removeObject(forKey: RARBinaryDiscovery.userPathDefaultsKey)
        // rar is not installed on this machine
        XCTAssertNil(RARCreateProvider.makeValidated(defaults: defaults))
    }

    func testMakeValidatedReturnsNilWhenLicenseNotConfirmed() throws {
        // Even if we had a binary, without license confirmation the provider
        // must not be available.
        let suiteName = "RARCreateProviderTests-nolic-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removeObject(forKey: RARBinaryDiscovery.licenseConfirmedDefaultsKey)
        XCTAssertNil(RARCreateProvider.makeValidated(defaults: defaults))
    }

    // MARK: - Capability registry gating

    func testRegistryWithRARCreateAvailableTrue() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        let updated = baseline.withRARCreateAvailable(true)
        let snapshot = updated.snapshot(format: .rar)
        XCTAssertTrue(snapshot.actions.contains(.create))
        XCTAssertTrue(snapshot.actions.contains(.test))
        XCTAssertTrue(snapshot.actions.contains(.list))
        XCTAssertEqual(snapshot.primaryProvider, .rarLab)
    }

    func testRegistryWithRARCreateAvailableFalse() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        // First enable RAR read via 7zz
        let withRead = baseline.withRARAvailable(true)
        // Then gate creation off
        let updated = withRead.withRARCreateAvailable(false)
        let snapshot = updated.snapshot(format: .rar)
        // Read capabilities preserved
        XCTAssertTrue(snapshot.actions.contains(.list))
        XCTAssertTrue(snapshot.actions.contains(.read))
        // Creation gated off
        XCTAssertFalse(snapshot.actions.contains(.create))
        XCTAssertEqual(snapshot.unavailableReasons[.create], .externalProviderNotValidated)
    }

    func testRegistryWithValidatedRARLAB() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        let updated = baseline.withValidatedRARLAB()
        let snapshot = updated.snapshot(format: .rar)
        XCTAssertTrue(snapshot.actions.contains(.create))
        XCTAssertTrue(snapshot.actions.contains(.test))
        XCTAssertEqual(snapshot.primaryProvider, .rarLab)
        XCTAssertEqual(snapshot.unavailableReasons[.repair], .unsupportedByProvider)
    }

    func testRegistryProductionBaselineRarCreateUnavailable() {
        let baseline = ArchiveCapabilityRegistry.productionBaseline
        let snapshot = baseline.snapshot(format: .rar)
        // In production baseline, RAR create is marked as externalProviderNotValidated
        XCTAssertFalse(snapshot.actions.contains(.create))
        XCTAssertEqual(snapshot.unavailableReasons[.create], .externalProviderNotValidated)
    }

    // MARK: - Compression method

    func testCompressionMethodArguments() {
        XCTAssertEqual(RARCompressionMethod.store.argument, "-m0")
        XCTAssertEqual(RARCompressionMethod.fastest.argument, "-m1")
        XCTAssertEqual(RARCompressionMethod.fast.argument, "-m2")
        XCTAssertEqual(RARCompressionMethod.normal.argument, "-m3")
        XCTAssertEqual(RARCompressionMethod.good.argument, "-m4")
        XCTAssertEqual(RARCompressionMethod.best.argument, "-m5")
    }

    func testCompressionMethodAllCases() {
        XCTAssertEqual(RARCompressionMethod.allCases.count, 6)
    }

    // MARK: - Create options

    func testCreateOptionsDefaults() {
        let options = RARCreateOptions()
        XCTAssertEqual(options.method, .normal)
        XCTAssertNil(options.password)
        XCTAssertFalse(options.solid)
        XCTAssertFalse(options.storeFullPaths)
    }

    // MARK: - User-configured path

    func testUserConfiguredPathTakesPriority() {
        let suiteName = "RARCreateProviderTests-path-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Set a non-existent user path; discovery should still fail but proves
        // the path is consulted (it won't crash).
        defaults.set("/nonexistent/rar", forKey: RARBinaryDiscovery.userPathDefaultsKey)
        XCTAssertNil(RARBinaryDiscovery.discover(defaults: defaults))
    }

    // MARK: - Fixture tests (require real rar install, skip otherwise)

    func testCreateAndTestArchive() async throws {
        let discovery = try requireValidatedBinary()
        let defaults = UserDefaults(suiteName: "RARCreateProviderTests-fixture")!
        RARLicenseConfirmation(defaults: defaults).confirm()
        defer { defaults.removePersistentDomain(forName: "RARCreateProviderTests-fixture") }

        let provider = RARCreateProvider(binaryPath: discovery.resolvedPath)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create source files
        let sourceFile = dir.appending(path: "hello.txt")
        try Data("Hello RAR World".utf8).write(to: sourceFile)

        let archiveURL = dir.appending(path: "test.rar")
        try await provider.create(
            archiveURL: archiveURL,
            sources: [sourceFile.path],
            options: RARCreateOptions(method: .normal)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        // Test integrity
        let passed = try await provider.test(archiveURL: archiveURL)
        XCTAssertTrue(passed)
    }

    func testCreateWithPassword() async throws {
        let discovery = try requireValidatedBinary()
        let provider = RARCreateProvider(binaryPath: discovery.resolvedPath)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceFile = dir.appending(path: "secret.txt")
        try Data("encrypted content".utf8).write(to: sourceFile)

        let archiveURL = dir.appending(path: "encrypted.rar")
        try await provider.create(
            archiveURL: archiveURL,
            sources: [sourceFile.path],
            options: RARCreateOptions(method: .best, password: "TestPass123")
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testCreateAndExtract() async throws {
        let discovery = try requireValidatedBinary()
        let provider = RARCreateProvider(binaryPath: discovery.resolvedPath)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceFile = dir.appending(path: "data.bin")
        let payload = Data(repeating: 0xAB, count: 4096)
        try payload.write(to: sourceFile)

        let archiveURL = dir.appending(path: "roundtrip.rar")
        try await provider.create(
            archiveURL: archiveURL,
            sources: [sourceFile.path],
            options: RARCreateOptions(method: .store)
        )

        let extractDir = dir.appending(path: "extracted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await provider.extract(archiveURL: archiveURL, to: extractDir)

        let extractedFile = extractDir.appending(path: "data.bin")
        XCTAssertEqual(try Data(contentsOf: extractedFile), payload)
    }
}
