import ArchiveProviders
import Foundation
import XCTest

final class ExternalCreateNameStagingTests: XCTestCase {
    func testCrossVolumeLinkFailureFallsBackToCopyAndCleansUp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtCreate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("original.txt")
        try Data("payload".utf8).write(to: source)
        let input = ArchiveCreationInput(sourceURL: source, archiveRootName: "renamed.txt")

        let prepared = try ExternalCreateNameStaging.prepare(
            inputs: [input],
            linker: { _, _ in
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV), userInfo: [
                    NSLocalizedDescriptionKey: "cross-device link"
                ])
            }
        )
        XCTAssertEqual(prepared.urls.count, 1)
        XCTAssertEqual(prepared.urls[0].lastPathComponent, "renamed.txt")
        XCTAssertEqual(try String(contentsOf: prepared.urls[0], encoding: .utf8), "payload")
        XCTAssertTrue(prepared.urls[0].path.contains("MacUnzip_create_names_"))

        prepared.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.urls[0].path))
    }

    func testLinkAndCopyFailureRemovesStagingDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtCreateFail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("original.txt")
        try Data("payload".utf8).write(to: source)
        let input = ArchiveCreationInput(sourceURL: source, archiveRootName: "renamed.txt")

        final class StagingBox: @unchecked Sendable {
            var url: URL?
        }
        let observed = StagingBox()
        XCTAssertThrowsError(
            try ExternalCreateNameStaging.prepare(
                inputs: [input],
                linker: { _, destination in
                    observed.url = destination.deletingLastPathComponent()
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EXDEV))
                },
                copier: { _, _ in
                    throw NSError(domain: "test", code: 99, userInfo: [
                        NSLocalizedDescriptionKey: "forced copy failure"
                    ])
                }
            )
        )

        let staging = try XCTUnwrap(observed.url)
        XCTAssertTrue(staging.lastPathComponent.hasPrefix("MacUnzip_create_names_"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staging.path),
            "Failed create must remove MacUnzip_create_names_*"
        )
    }

    func testStageTreeIncludesNestedAndBundleContentsAcrossPathPrefixForms() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtTree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("nested/deep.txt")
        try FileManager.default.createDirectory(
            at: nested.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("deep-bytes".utf8).write(to: nested)

        let appResource = root
            .appendingPathComponent("Demo.app/Contents/Resources/info.txt")
        try FileManager.default.createDirectory(
            at: appResource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("bundle-bytes".utf8).write(to: appResource)

        let bundleResource = root
            .appendingPathComponent("Plug.bundle/Contents/resource.dat")
        try FileManager.default.createDirectory(
            at: bundleResource.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("plug-bytes".utf8).write(to: bundleResource)

        // Cover both /var and /private/var path spellings for the same directory.
        let resolvedPath = root.resolvingSymlinksInPath().path
        let varPath = resolvedPath.hasPrefix("/private/var/")
            ? String(resolvedPath.dropFirst("/private".count))
            : (resolvedPath.hasPrefix("/var/") ? resolvedPath : root.path)
        let privatePath = varPath.hasPrefix("/var/") ? "/private" + varPath : resolvedPath
        let varForm = URL(fileURLWithPath: varPath)
        let privateForm = URL(fileURLWithPath: privatePath)
        XCTAssertNotEqual(varForm.path, privateForm.path)

        for source in [varForm, privateForm] {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("staged-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: destination) }
            try ExternalCreateNameStaging.stageTree(
                from: source,
                to: destination,
                linker: ExternalCreateNameStaging.defaultLinkItem,
                copier: ExternalCreateNameStaging.defaultCopyItem
            )
            XCTAssertEqual(
                try String(contentsOf: destination.appendingPathComponent("nested/deep.txt"), encoding: .utf8),
                "deep-bytes"
            )
            XCTAssertEqual(
                try String(
                    contentsOf: destination.appendingPathComponent("Demo.app/Contents/Resources/info.txt"),
                    encoding: .utf8
                ),
                "bundle-bytes"
            )
            XCTAssertEqual(
                try String(
                    contentsOf: destination.appendingPathComponent("Plug.bundle/Contents/resource.dat"),
                    encoding: .utf8
                ),
                "plug-bytes"
            )
        }
    }

    func testStageTreeRejectsSymlinkInsteadOfSkipping() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtSym-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("real.txt")
        try Data("x".utf8).write(to: target)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("staged-sym-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        XCTAssertThrowsError(
            try ExternalCreateNameStaging.stageTree(
                from: root,
                to: destination,
                linker: ExternalCreateNameStaging.defaultLinkItem,
                copier: ExternalCreateNameStaging.defaultCopyItem
            )
        ) { error in
            guard case ExternalCreateNameStagingError.symlinkRejected = error else {
                return XCTFail("expected symlinkRejected, got \(error)")
            }
        }
    }
}
