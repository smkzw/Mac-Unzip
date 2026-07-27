import Darwin
import XCTest

final class PreviewRoutingTests: XCTestCase {
    func testOfficePreviewKindsUseEnglishCatalogWhenEnglishIsSelected() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(OfficePreviewKind.word.displayName(localization: localization), "Word Document")
        XCTAssertEqual(OfficePreviewKind.excel.displayName(localization: localization), "Excel Spreadsheet")
        XCTAssertEqual(
            OfficePreviewKind.powerPoint.displayName(localization: localization),
            "PowerPoint Presentation"
        )
        XCTAssertEqual(
            OfficePreviewKind.word.preparingMessage(localization: localization),
            "Preparing Word Document preview"
        )
        XCTAssertEqual(
            OfficePreviewKind.word.accessibilityLabel(localization: localization),
            "Word Document Quick Look preview"
        )
        XCTAssertEqual(
            OfficePreviewKind.word.selectionLabel(
                filename: "Report.docx",
                localization: localization
            ),
            "Preview Report.docx as a Word Document"
        )
    }

    override func setUpWithError() throws {
        try? FileManager.default.removeItem(at: ValidatedPreviewCacheURL.cacheRoot)
        try FileManager.default.createDirectory(
            at: ValidatedPreviewCacheURL.cacheRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ValidatedPreviewCacheURL.cacheRoot)
    }

    func testRoutesSupportedArchiveEntryExtensionsToTypedPreviewKinds() {
        let policy = PreviewRoutingPolicy()
        let cases: [(String, PreviewKind)] = [
            ("hero.png", .image),
            ("photo.heic", .image),
            ("movie.mp4", .video),
            ("guide.pdf", .pdfKit),
            ("legacy.doc", .quickLookOffice(.word)),
            ("document.docx", .quickLookOffice(.word)),
            ("legacy.xls", .quickLookOffice(.excel)),
            ("workbook.xlsx", .quickLookOffice(.excel)),
            ("legacy.ppt", .quickLookOffice(.powerPoint)),
            ("slides.pptx", .quickLookOffice(.powerPoint)),
            ("payload.bin", .unsupported)
        ]

        for (filename, expectedKind) in cases {
            XCTAssertEqual(policy.kind(forFilename: filename), expectedKind, filename)
        }
    }

    func testRoutingIsCaseInsensitiveAndFallsBackWithoutAnExtension() {
        let policy = PreviewRoutingPolicy()

        XCTAssertEqual(policy.kind(forFilename: "REPORT.PDF"), .pdfKit)
        XCTAssertEqual(policy.kind(forFilename: "README"), .unsupported)
    }

    func testValidatedPreviewCacheAcceptsOnlyExistingRegularFilesWithoutSymlinks() throws {
        let root = ValidatedPreviewCacheURL.cacheRoot
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("guide.pdf")
        let expectedData = Data("safe preview".utf8)
        try expectedData.write(to: file)

        let validated = ValidatedPreviewCacheURL(candidateURL: file)

        XCTAssertNotNil(validated)
        XCTAssertEqual(validated?.readData(), expectedData)
        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: directory))
        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: directory.appendingPathComponent("missing.pdf")))
    }

    func testValidatedPreviewCacheRejectsSiblingPrefixAndSymlinkedFileOrParent() throws {
        let root = ValidatedPreviewCacheURL.cacheRoot
        let sibling = root.deletingLastPathComponent()
            .appendingPathComponent("PreviewCache-sibling", isDirectory: true)
        try? FileManager.default.removeItem(at: sibling)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let siblingFile = sibling.appendingPathComponent("outside.pdf")
        try Data("outside".utf8).write(to: siblingFile)
        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: siblingFile))

        let regularDirectory = root.appendingPathComponent("regular", isDirectory: true)
        try FileManager.default.createDirectory(at: regularDirectory, withIntermediateDirectories: true)
        let symlinkedFile = regularDirectory.appendingPathComponent("linked.pdf")
        try FileManager.default.createSymbolicLink(at: symlinkedFile, withDestinationURL: siblingFile)
        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: symlinkedFile))

        let symlinkedParent = root.appendingPathComponent("linked-parent", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkedParent, withDestinationURL: sibling)
        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: symlinkedParent.appendingPathComponent("outside.pdf")))
    }

    func testDescriptorRelativeReadCannotBeRedirectedWhenParentIsReplaced() throws {
        let root = ValidatedPreviewCacheURL.cacheRoot
        let trusted = root.appendingPathComponent("trusted", isDirectory: true)
        let moved = root.appendingPathComponent("trusted-moved", isDirectory: true)
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
        try? FileManager.default.removeItem(at: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: trusted, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let safe = Data("safe parent descriptor".utf8)
        try safe.write(to: trusted.appendingPathComponent("guide.pdf"))
        try Data("outside target".utf8).write(to: outside.appendingPathComponent("guide.pdf"))
        let validated = try XCTUnwrap(
            ValidatedPreviewCacheURL(candidateURL: trusted.appendingPathComponent("guide.pdf"))
        )

        var replacementError: Error?
        var replacementSucceeded = false
        let read = validated.readData(beforeOpeningFinalComponent: {
            do {
                try FileManager.default.moveItem(at: trusted, to: moved)
                try FileManager.default.createSymbolicLink(at: trusted, withDestinationURL: outside)
                replacementSucceeded = true
            } catch {
                replacementError = error
            }
        })

        XCTAssertNil(replacementError)
        XCTAssertTrue(replacementSucceeded)
        XCTAssertTrue(try trusted.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        XCTAssertEqual(read, safe)
        XCTAssertNotEqual(read, Data("outside target".utf8))
    }

    func testBoundedReaderRejectsDenseFileAboveConfiguredLimit() throws {
        XCTAssertEqual(ValidatedPreviewCacheURL.maximumPreviewBytes, 256 * 1_024 * 1_024)
        let file = ValidatedPreviewCacheURL.cacheRoot.appendingPathComponent("dense.bin")
        try Data(repeating: 0x41, count: 65).write(to: file)
        let validated = try XCTUnwrap(ValidatedPreviewCacheURL(candidateURL: file))

        XCTAssertNil(validated.readData(maximumBytes: 64))
    }

    func testBoundedReaderReturnsAFileExactlyAtTheRequestedLimit() throws {
        let file = ValidatedPreviewCacheURL.cacheRoot.appendingPathComponent("exact.bin")
        let expected = Data(repeating: 0x42, count: 64)
        try expected.write(to: file)
        let validated = try XCTUnwrap(ValidatedPreviewCacheURL(candidateURL: file))

        XCTAssertEqual(validated.readData(maximumBytes: 64), expected)
    }

    func testValidatorRejectsSparseFileAboveFullPreviewLimit() throws {
        let file = ValidatedPreviewCacheURL.cacheRoot.appendingPathComponent("sparse.bin")
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(ftruncate(descriptor, off_t(ValidatedPreviewCacheURL.maximumPreviewBytes + 1)), 0)
        XCTAssertEqual(close(descriptor), 0)

        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: file))
    }

    func testValidatorRejectsDotAndDotDotRelativeComponents() throws {
        let root = ValidatedPreviewCacheURL.cacheRoot
        let file = root.appendingPathComponent("guide.pdf")
        try Data("safe".utf8).write(to: file)

        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: URL(fileURLWithPath: root.path + "/./guide.pdf")))
        XCTAssertNil(ValidatedPreviewCacheURL(candidateURL: URL(fileURLWithPath: root.path + "/nested/../guide.pdf")))
    }
}
