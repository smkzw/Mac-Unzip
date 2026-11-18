import ArchiveDomain
import ArchiveSecurity
import Foundation
import XCTest
@testable import ArchiveProviders

final class InfoZIPZipCryptoTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/infozip-password-macunzip-test-123.zip")
    }

    private var expectedSecret: Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/EXPECTED_secret.txt")
        return (try? Data(contentsOf: url)) ?? Data("MacUnzip encrypted ZIP acceptance\n".utf8)
    }

    private let password = "macunzip-test-123"

    func testCheckedInInfoZIPFixtureOpenReadAndMaterialize() async throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path), fixtureURL.path)

        let listing = ZIPArchiveProvider()
        let listed = try await listing.open(url: fixtureURL)
        let encrypted = try XCTUnwrap(listed.entries.first { !$0.isDirectory })
        XCTAssertTrue(encrypted.isEncrypted)
        XCTAssertEqual(encrypted.entry.displayPath, "secret.txt")

        do {
            _ = try await listing.readEntry(id: encrypted.entry.id, maximumBytes: 1 << 20)
            XCTFail("expected passwordRequired")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .passwordRequired)
        }

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.openWithPassword(
            url: fixtureURL,
            password: SecurePassword(password)
        )
        let entry = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory })
        let bytes = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(bytes, expectedSecret)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfoZIP-mat-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let out = try await provider.materializeEntry(id: entry.entry.id, under: root)
        XCTAssertEqual(try Data(contentsOf: out), expectedSecret)
    }

    func testCheckedInInfoZIPFixtureRejectsWrongPassword() async throws {
        let provider = ZIPArchiveProvider()
        do {
            let snapshot = try await provider.openWithPassword(
                url: fixtureURL,
                password: SecurePassword("definitely-wrong")
            )
            if let entry = snapshot.entries.first(where: { !$0.isDirectory }) {
                _ = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
            }
            XCTFail("expected wrongPassword")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .wrongPassword)
        }
    }

    func testSystemZipCreatesReadableZipCryptoWhenAvailable() async throws {
        let zipURL = URL(fileURLWithPath: "/usr/bin/zip")
        guard FileManager.default.isExecutableFile(atPath: zipURL.path) else {
            throw XCTSkip("/usr/bin/zip not available")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfoZIP-sys-\(UUID().uuidString)", isDirectory: true)
        let contents = root.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let expected = Data("system-zip-crypto-bytes".utf8)
        try expected.write(to: contents.appendingPathComponent("payload.txt"))
        let archive = root.appendingPathComponent("sys.zip")

        let process = Process()
        process.executableURL = zipURL
        process.arguments = ["-q", "-P", "sys-pass-123", archive.path, "payload.txt"]
        process.currentDirectoryURL = contents
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.openWithPassword(
            url: archive,
            password: SecurePassword("sys-pass-123")
        )
        let entry = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory })
        let bytes = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(bytes, expected)
    }

    func testStoreZipCryptoRejectsVerifyCollisionWrongPassword() async throws {
        let storeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/infozip-store-password-macunzip-test-123.zip")
        let wrong = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/STORE_COLLIDING_WRONG_PASSWORD.txt")))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "wrong-87"
        let expected = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/EXPECTED_store_secret.txt"))

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path), storeURL.path)

        let provider = ZIPArchiveProvider()
        do {
            let snapshot = try await provider.openWithPassword(
                url: storeURL,
                password: SecurePassword(wrong)
            )
            let entry = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory })
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("Store-wrong-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try await provider.materializeEntry(id: entry.entry.id, under: root)
            XCTFail("verify-collision wrong password must not materialize")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .wrongPassword)
        }

        let okProvider = ZIPArchiveProvider()
        let snapshot = try await okProvider.openWithPassword(
            url: storeURL,
            password: SecurePassword(password)
        )
        let entry = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory })
        let bytes = try await okProvider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(bytes, expected)
    }

    func testLegacyMacUnzipVerify1LastByteStillOpensWithCRC() async throws {
        let legacyURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/legacy-macunzip-verify1-last-byte.zip")
        let expected = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ZipCrypto/EXPECTED_legacy.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path), legacyURL.path)

        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.openWithPassword(
            url: legacyURL,
            password: SecurePassword("legacy-pass")
        )
        let entry = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory })
        let bytes = try await provider.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
        XCTAssertEqual(bytes, expected)

        do {
            let bad = ZIPArchiveProvider()
            let snap = try await bad.openWithPassword(
                url: legacyURL,
                password: SecurePassword("not-legacy-pass")
            )
            if let entry = snap.entries.first(where: { !$0.isDirectory }) {
                _ = try await bad.readEntry(id: entry.entry.id, maximumBytes: 1 << 20)
            }
            XCTFail("wrong password must fail")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .wrongPassword)
        }
    }
}
