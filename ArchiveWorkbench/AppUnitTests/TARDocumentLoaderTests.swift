import ArchiveDomain
import ArchiveProviders
import Foundation
import XCTest

/// Real loader-boundary coverage for TAR/.tgz/.tar.gz via ArchiveDocumentLoader.open.
final class TARDocumentLoaderTests: XCTestCase {
    func testLoaderOpensTarTgzAndTarGz() async throws {
        let src = FileManager.default.temporaryDirectory
            .appendingPathComponent("tar-loader-src-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: src) }
        try "hello loader".write(
            to: src.appendingPathComponent("hello.txt"),
            atomically: true,
            encoding: .utf8
        )

        let tar = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader-\(UUID().uuidString).tar")
        let tgz = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader-\(UUID().uuidString).tgz")
        let tarGz = FileManager.default.temporaryDirectory
            .appendingPathComponent("loader-\(UUID().uuidString).tar.gz")
        defer {
            try? FileManager.default.removeItem(at: tar)
            try? FileManager.default.removeItem(at: tgz)
            try? FileManager.default.removeItem(at: tarGz)
        }

        try runTar(args: ["-c", "-f", tar.path, "-C", src.path, "."])
        try runTar(args: ["-c", "-z", "-f", tgz.path, "-C", src.path, "."])
        try runTar(args: ["-c", "-z", "-f", tarGz.path, "-C", src.path, "."])

        let loader = ArchiveDocumentLoader()
        let tarSnapshot = try await loader.open(url: tar)
        XCTAssertTrue(tarSnapshot.entries.contains { $0.entry.displayPath.hasSuffix("hello.txt") })

        let tgzSnapshot = try await loader.open(url: tgz)
        XCTAssertTrue(tgzSnapshot.entries.contains { $0.entry.displayPath.hasSuffix("hello.txt") })

        let tarGzSnapshot = try await loader.open(url: tarGz)
        XCTAssertTrue(tarGzSnapshot.entries.contains { $0.entry.displayPath.hasSuffix("hello.txt") })
    }

    func testLoaderRejectsPureGzipAsUnsupportedOrNotTAR() async throws {
        let plain = FileManager.default.temporaryDirectory
            .appendingPathComponent("plain-\(UUID().uuidString).txt")
        let gz = plain.appendingPathExtension("gz")
        defer {
            try? FileManager.default.removeItem(at: plain)
            try? FileManager.default.removeItem(at: gz)
        }
        try Data("not a tar payload".utf8).write(to: plain)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-kf", plain.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let loader = ArchiveDocumentLoader()
        do {
            _ = try await loader.open(url: gz)
            XCTFail("Expected loader to reject pure gzip")
        } catch let error as TARProviderError {
            guard case .notTAR = error else {
                XCTFail("Expected TARProviderError.notTAR, got \(error)")
                return
            }
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .unsupportedFormat, "Unexpected ArchiveError \(error)")
        } catch {
            XCTFail("Unexpected error type \(error)")
        }
    }

    private func runTar(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = args
        let err = Pipe()
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(domain: "TARDocumentLoaderTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
}
