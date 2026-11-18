import Foundation
import XCTest

final class DropRoutingTests: XCTestCase {
    private func tempFile(name: String, data: Data = Data("x".utf8)) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropRoute-\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    private func tempDir(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropRouteDir-\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testWelcomeAllArchivesOpensFirst() throws {
        let a = try tempFile(name: "a.zip")
        let b = try tempFile(name: "b.zip")
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        let decision = DropRouting.decide(
            urls: [a, b],
            context: .welcome,
            isSupportedArchive: { $0.pathExtension.lowercased() == "zip" }
        )
        XCTAssertEqual(decision, .openFirstArchive(a, ignoredCount: 1))
    }

    func testWelcomeMixedAsks() throws {
        let archive = try tempFile(name: "pack.zip")
        let pdf = try tempFile(name: "notes.pdf")
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: pdf)
        }
        let decision = DropRouting.decide(
            urls: [archive, pdf],
            context: .welcome,
            isSupportedArchive: { $0.pathExtension.lowercased() == "zip" }
        )
        guard case .askMixed(let archives, let others) = decision else {
            return XCTFail("Expected askMixed, got \(String(describing: decision))")
        }
        XCTAssertEqual(archives, [archive])
        XCTAssertEqual(others, [pdf])
    }

    func testOpenDocumentNonArchivesAdd() throws {
        let pdf = try tempFile(name: "notes.pdf")
        let folder = try tempDir(name: "assets")
        defer {
            try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: folder)
        }
        let decision = DropRouting.decide(
            urls: [pdf, folder],
            context: .openDocument,
            isSupportedArchive: { _ in false }
        )
        XCTAssertEqual(decision, .addToOpenDocument([pdf, folder]))
    }

    func testCreatePanelTreatsArchivesAsInputs() throws {
        let archive = try tempFile(name: "pack.zip")
        let pdf = try tempFile(name: "notes.pdf")
        defer {
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: pdf)
        }
        let decision = DropRouting.decide(
            urls: [archive, pdf],
            context: .createPanel,
            isSupportedArchive: { $0.pathExtension.lowercased() == "zip" }
        )
        XCTAssertEqual(decision, .createArchiveInputs([archive, pdf]))
    }

    func testCreationMergeDedupesAndReportsRootNameConflict() throws {
        let dir = try tempDir(name: "merge")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appendingPathComponent("a.txt")
        let otherDir = try tempDir(name: "other")
        defer { try? FileManager.default.removeItem(at: otherDir) }
        let second = otherDir.appendingPathComponent("a.txt")
        try Data("1".utf8).write(to: first)
        try Data("2".utf8).write(to: second)

        let duplicate = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: first)],
            incoming: [first]
        )
        XCTAssertEqual(duplicate.skippedDuplicates.map(\.sourceURL), [first.standardizedFileURL])
        XCTAssertTrue(duplicate.added.isEmpty)

        let conflict = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: first)],
            incoming: [second]
        )
        XCTAssertEqual(conflict.pendingConflicts.count, 1)
        XCTAssertTrue(conflict.added.isEmpty)
        XCTAssertEqual(conflict.inputs.count, 1)

        let renamed = CreationInputMerging.merge(
            existing: [CreationInput(sourceURL: first)],
            incoming: [second],
            conflictResolution: .rename
        )
        XCTAssertEqual(renamed.inputs.count, 2)
        XCTAssertNotEqual(renamed.inputs[1].archiveRootName.lowercased(), "a.txt")
        XCTAssertEqual(renamed.inputs[1].sourceURL.path, second.standardizedFileURL.path)
    }
}
