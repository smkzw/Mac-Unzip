import ArchiveSecurity
import Foundation
import XCTest

final class SecureFileMaterializerTests: XCTestCase {
    func testWritesNestedRegularFile() throws {
        let root = try TemporaryDirectory()
        let materializer = SecureFileMaterializer(rootURL: root.url)

        let output = try materializer.write(Data("预览内容".utf8), relativePath: "文档/预览.txt")

        XCTAssertEqual(try Data(contentsOf: output), Data("预览内容".utf8))
    }

    func testStreamsMultipleChunksIntoOneSecureFile() throws {
        let root = try TemporaryDirectory()
        let materializer = SecureFileMaterializer(rootURL: root.url)

        let output = try materializer.write(relativePath: "文档/流式.txt") { writer in
            try writer.write(Data("第一段".utf8))
            try writer.write(Data("＋第二段".utf8))
        }

        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "第一段＋第二段")
    }

    func testCreatesAnEmptyNestedDirectoryWithoutFollowingLinks() throws {
        let root = try TemporaryDirectory()
        let materializer = SecureFileMaterializer(rootURL: root.url)

        let output = try materializer.createDirectory(relativePath: "空文件夹/子目录")

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testSessionKeepsWritingToOriginalRootDescriptorAfterPathReplacement() throws {
        let root = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let moved = root.url.deletingLastPathComponent().appending(
            path: "MacUnzipMoved-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        let session = try SecureMaterializationSession(rootURL: root.url)
        try FileManager.default.moveItem(at: root.url, to: moved)
        try FileManager.default.createSymbolicLink(at: root.url, withDestinationURL: outside.url)
        defer {
            try? FileManager.default.removeItem(at: root.url)
            try? FileManager.default.removeItem(at: moved)
        }

        _ = try session.write(relativePath: "安全.txt") { writer in
            try writer.write(Data("inside".utf8))
        }

        XCTAssertEqual(try String(contentsOf: moved.appending(path: "安全.txt"), encoding: .utf8), "inside")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.url.appending(path: "安全.txt").path))
    }

    func testRejectsTraversalAndDoesNotCreateOutput() throws {
        let root = try TemporaryDirectory()
        let materializer = SecureFileMaterializer(rootURL: root.url)
        let escaped = root.url.deletingLastPathComponent().appending(path: "escape.txt")
        try? FileManager.default.removeItem(at: escaped)

        XCTAssertThrowsError(
            try materializer.write(Data("x".utf8), relativePath: "../escape.txt")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: escaped.path))
    }

    func testRefusesExistingSymlinkLeaf() throws {
        let root = try TemporaryDirectory()
        let outside = root.url.deletingLastPathComponent().appending(path: UUID().uuidString)
        try Data("keep".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "preview.txt"),
            withDestinationURL: outside
        )
        let materializer = SecureFileMaterializer(rootURL: root.url)

        XCTAssertThrowsError(
            try materializer.write(Data("replace".utf8), relativePath: "preview.txt")
        )
        XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
    }

    func testRefusesSymlinkDirectoryComponent() throws {
        let root = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "linked"),
            withDestinationURL: outside.url
        )
        let materializer = SecureFileMaterializer(rootURL: root.url)

        XCTAssertThrowsError(
            try materializer.write(Data("x".utf8), relativePath: "linked/file.txt")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.url.appending(path: "file.txt").path))
    }
}

private final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipMaterializer-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
