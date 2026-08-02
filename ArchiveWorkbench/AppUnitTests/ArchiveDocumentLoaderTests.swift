import ArchiveDomain
import ArchiveProviders
import AVFoundation
import Foundation
import XCTest

final class ArchiveDocumentLoaderTests: XCTestCase {
    func testRealLoaderMaterializesArchiveBytesInsidePreviewCache() async throws {
        let expected = Data("真实 PDF 字节".utf8)
        let fixture = try LoaderZIPFixture(entries: ["文档/报告.pdf": expected])
        let loader = ArchiveDocumentLoader()

        let snapshot = try await loader.open(url: fixture.archiveURL)
        let entryID = try XCTUnwrap(snapshot.entries.first { !$0.isDirectory }?.entry.id)
        let materializedURL = try await loader.materializePreview(entryID: entryID)
        let validated = try XCTUnwrap(ValidatedPreviewCacheURL(candidateURL: materializedURL))

        XCTAssertEqual(validated.readData(), expected)
        XCTAssertTrue(materializedURL.path.hasPrefix(ValidatedPreviewCacheURL.cacheRoot.path + "/"))
    }

    func testRealLoaderMaterializesImageVideoPDFWordExcelAndPowerPointBytes() async throws {
        let names = ["示例.png", "示例.mp4", "示例.pdf", "示例.docx", "示例.xlsx", "示例.pptx"]
        let expected = try Dictionary(uniqueKeysWithValues: names.map { name in
            let nameURL = URL(fileURLWithPath: name)
            let source = try XCTUnwrap(Bundle(for: Self.self).url(
                forResource: nameURL.deletingPathExtension().lastPathComponent,
                withExtension: nameURL.pathExtension
            ))
            return ("预览/" + name, try Data(contentsOf: source))
        })
        let fixture = try LoaderZIPFixture(entries: expected)
        let loader = ArchiveDocumentLoader()
        let snapshot = try await loader.open(url: fixture.archiveURL)

        for item in snapshot.entries where !item.isDirectory {
            let materializedURL = try await loader.materializePreview(entryID: item.entry.id)
            XCTAssertEqual(
                try Data(contentsOf: materializedURL),
                expected[item.entry.displayPath],
                item.entry.displayPath
            )
        }
    }

    func testRealLoaderPublishesCompleteExtractionFolder() async throws {
        let fixture = try LoaderZIPFixture(entries: [
            "文档/说明.txt": Data("安全解压".utf8),
            "根目录.txt": Data("root".utf8),
        ])
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipDestination-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let loader = ArchiveDocumentLoader()
        _ = try await loader.open(url: fixture.archiveURL)

        let output = try await loader.extractAll(to: destination) { _ in }

        XCTAssertEqual(output.lastPathComponent, "fixture")
        XCTAssertEqual(
            try Data(contentsOf: output.appending(path: "文档/说明.txt")),
            Data("安全解压".utf8)
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: destination.path)
                .contains { $0.hasSuffix(".partial") }
        )
    }

    func testRealLoaderCreatesVerifiedWindowsZIPAndReturnsOpenedSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipCreateLoader-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        let input = root.appending(path: "输入资料", directoryHint: .isDirectory)
        let output = root.appending(path: "Windows兼容资料.zip")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try Data("跨平台内容".utf8).write(to: input.appending(path: "说明.txt"))
        defer { try? FileManager.default.removeItem(at: root) }
        let loader = ArchiveDocumentLoader()
        let progressRecorder = CreationProgressRecorder()

        let snapshot = try await loader.createWindowsZIP(
            at: output,
            inputs: [input],
            compressLevel: 6,
            password: nil,
            encryptMethod: 0
        ) { progress in
            progressRecorder.record(progress)
        }

        XCTAssertEqual(snapshot.sourceURL, output)
        XCTAssertEqual(snapshot.entries.map(\.entry.displayPath), ["说明.txt"])
        XCTAssertEqual(progressRecorder.latest?.completedEntries, 1)
        XCTAssertEqual(progressRecorder.latest?.completedBytes, UInt64(Data("跨平台内容".utf8).count))
        let id = try XCTUnwrap(snapshot.entries.first?.entry.id)
        let previewURL = try await loader.materializePreview(entryID: id)
        XCTAssertEqual(try Data(contentsOf: previewURL), Data("跨平台内容".utf8))
    }

    func testRealLoaderStagesEditsAndSavesThemBackToArchive() async throws {
        let fixture = try LoaderZIPFixture(entries: ["说明.txt": Data("original".utf8)])
        let loader = ArchiveDocumentLoader()
        _ = try await loader.open(url: fixture.archiveURL)

        let sidecarRoot = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipEditSidecar-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: sidecarRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sidecarRoot) }
        let addedFile = sidecarRoot.appending(path: "新增.txt")
        try Data("added-content".utf8).write(to: addedFile)

        try await loader.stageChange(.add(sourceURL: addedFile, destinationPath: "新增.txt"))
        let pending = await loader.currentPendingChanges()
        XCTAssertEqual(pending.count, 1)

        let snapshot = try await loader.saveArchive()
        XCTAssertEqual(snapshot.sourceURL, fixture.archiveURL)
        let paths = Set(snapshot.entries.map(\.entry.displayPath))
        XCTAssertTrue(paths.contains("说明.txt"))
        XCTAssertTrue(paths.contains("新增.txt"))

        let pendingAfterSave = await loader.currentPendingChanges()
        XCTAssertTrue(pendingAfterSave.isEmpty)

        let addedID = try XCTUnwrap(snapshot.entries.first { $0.entry.displayPath == "新增.txt" }?.entry.id)
        let materialized = try await loader.materializePreview(entryID: addedID)
        XCTAssertEqual(try Data(contentsOf: materialized), Data("added-content".utf8))
    }

    func testRealLoaderUndoRemovesStagedChangeBeforeSave() async throws {
        let fixture = try LoaderZIPFixture(entries: ["说明.txt": Data("original".utf8)])
        let loader = ArchiveDocumentLoader()
        _ = try await loader.open(url: fixture.archiveURL)

        try await loader.stageChange(.remove(entryPath: "说明.txt"))
        let pending = await loader.currentPendingChanges()
        let changeID = try XCTUnwrap(pending.first?.id)

        let removed = await loader.undoChange(id: changeID)
        XCTAssertTrue(removed)
        let pendingAfterUndo = await loader.currentPendingChanges()
        XCTAssertTrue(pendingAfterUndo.isEmpty)

        let snapshot = try await loader.saveArchive()
        XCTAssertEqual(snapshot.entries.map(\.entry.displayPath), ["说明.txt"])
    }

    func testExtractionNeverOverwritesAndUsesFinderStyleNumericSuffix() async throws {
        let fixture = try LoaderZIPFixture(entries: ["说明.txt": Data("new".utf8)])
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipCollision-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        let existing = destination.appending(path: "fixture", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: existing.appending(path: "原文件.txt"))
        defer { try? FileManager.default.removeItem(at: destination) }
        let loader = ArchiveDocumentLoader()
        _ = try await loader.open(url: fixture.archiveURL)

        let output = try await loader.extractAll(to: destination) { _ in }

        XCTAssertEqual(output.lastPathComponent, "fixture 2")
        XCTAssertEqual(try String(contentsOf: existing.appending(path: "原文件.txt"), encoding: .utf8), "keep")
        XCTAssertEqual(try String(contentsOf: output.appending(path: "说明.txt"), encoding: .utf8), "new")
    }

    func testCancelledExtractionRemovesPartialFolderAndPublishesNothing() async throws {
        let fixture = try LoaderZIPFixture(entries: [
            "大文件.bin": loaderPseudoRandomData(count: 2_000_000),
        ])
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipCancel-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let loader = ArchiveDocumentLoader()
        _ = try await loader.open(url: fixture.archiveURL)

        do {
            _ = try await loader.extractAll(to: destination) { progress in
                if progress.completedBytes > 0 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
    }

    func testBundledVideoFixtureIsPlayableByAVFoundation() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "示例",
            withExtension: "mp4"
        ))
        let asset = AVURLAsset(url: source)
        let isPlayable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration).seconds

        XCTAssertTrue(isPlayable)
        XCTAssertGreaterThan(duration, 0)
    }

    @MainActor
    func testOpenArchiveReplacesWelcomeWithProviderSnapshot() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/真实文档.zip")
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("文档/说明.txt".utf8)),
            displayPath: "文档/说明.txt"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: sourceURL,
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 8,
                uncompressedSize: 12,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: false,
                usesUTF8FileName: true
            )]
        )
        let model = AppModel(loader: StubArchiveDocumentLoader(snapshot: snapshot))

        await model.openArchive(url: sourceURL)

        XCTAssertTrue(model.hasDocument)
        XCTAssertEqual(model.entries, [entry])
        XCTAssertEqual(model.documentTitle, "真实文档.zip")
        XCTAssertEqual(model.documentItemCount, 1)
        XCTAssertEqual(model.selectedEntryID, entry.id)
        XCTAssertEqual(model.currentDirectory, "")
        XCTAssertEqual(
            model.folderSummaries,
            [ArchiveFolderSummary(name: "文档", itemCount: 1)]
        )
        XCTAssertEqual(model.visibleEntries, [entry])
        XCTAssertNil(model.presentedError)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testOpenMalformedArchiveKeepsWelcomeAndShowsChineseError() async {
        let model = AppModel(loader: StubArchiveDocumentLoader(error: .corruptedArchive))

        await model.openArchive(url: URL(fileURLWithPath: "/tmp/损坏.zip"))

        XCTAssertFalse(model.hasDocument)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertEqual(
            model.presentedError,
            "无法打开这个压缩包。文件可能已损坏或不是受支持的 ZIP 格式。"
        )
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testPasswordErrorUsesSpecificChineseCopy() async {
        let model = AppModel(loader: StubArchiveDocumentLoader(error: .wrongPassword))

        await model.openArchive(url: URL(fileURLWithPath: "/tmp/加密.zip"))

        XCTAssertEqual(model.presentedError, "密码不正确，请重新输入。")
    }

    @MainActor
    func testOpenErrorsUseEnglishCatalogWhenEnglishIsSelected() async {
        let cases: [(ArchiveError, String)] = [
            (.passwordRequired, "This archive requires a password to open."),
            (.wrongPassword, "The password is incorrect. Try again."),
            (.unsupportedEncryption, "This archive uses an encryption method that is not supported yet."),
            (.unsupportedMethod, "This archive uses a compression method that is not supported yet."),
            (.missingVolume, "Other parts of this split archive are missing. Place all parts in the same folder and try again."),
            (.unsafePath, "The archive contains an unsafe file path and was not opened."),
            (.resourceLimit, "The archive exceeds the safety limits and was not opened."),
            (.sourceChanged, "The archive changed while it was being read. Open it again."),
            (.helperFailed, "The archive could not be read. Try again later."),
            (.unsupportedFormat, "This file could not be opened because it is not a supported archive format."),
            (.corruptedArchive, "This archive could not be opened. It may be damaged or not a supported ZIP file."),
        ]
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        for (error, expectedMessage) in cases {
            let model = AppModel(
                loader: StubArchiveDocumentLoader(error: error),
                localization: localization
            )

            await model.openArchive(url: URL(fileURLWithPath: "/tmp/archive.zip"))

            XCTAssertEqual(model.presentedError, expectedMessage)
        }
    }

    @MainActor
    func testRootFileSelectionKeepsRootCategoryVisible() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/混合目录.zip")
        let rootEntry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("根目录.txt".utf8)),
            displayPath: "根目录.txt"
        )
        let nestedEntry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("文档/说明.txt".utf8)),
            displayPath: "文档/说明.txt"
        )
        let snapshots = [rootEntry, nestedEntry].map { entry in
            ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 1,
                uncompressedSize: 1,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: false,
                usesUTF8FileName: true
            )
        }
        let model = AppModel(loader: StubArchiveDocumentLoader(snapshot: ArchiveDocumentSnapshot(
            sourceURL: sourceURL,
            format: .zip,
            entries: snapshots
        )))

        await model.openArchive(url: sourceURL)

        XCTAssertEqual(model.currentDirectory, "")
        XCTAssertEqual(model.visibleEntries, [rootEntry, nestedEntry])
    }

    @MainActor
    func testRootCategoryAndGenericTypeUseEnglishCatalogWhenEnglishIsSelected() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/archive.zip")
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("README".utf8)),
            displayPath: "README"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: sourceURL,
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 1,
                uncompressedSize: 1,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: false,
                usesUTF8FileName: true
            )]
        )
        let model = AppModel(
            loader: StubArchiveDocumentLoader(snapshot: snapshot),
            localization: AppLocalization(
                bundle: Bundle(for: Self.self),
                locale: Locale(identifier: "en")
            )
        )

        await model.openArchive(url: sourceURL)

        XCTAssertEqual(model.currentDirectory, "")
        XCTAssertEqual(model.folderSummaries, [ArchiveFolderSummary(name: "Archive Root", itemCount: 1)])
        XCTAssertEqual(model.selectedMetadata?.type, "File")
    }

    @MainActor
    func testSelectedSupportedEntryMaterializesIntoValidatedPreviewCache() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/预览.zip")
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("文档/报告.pdf".utf8)),
            displayPath: "文档/报告.pdf"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: sourceURL,
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 8,
                uncompressedSize: 12,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: false,
                usesUTF8FileName: true
            )]
        )
        let cacheDirectory = ValidatedPreviewCacheURL.cacheRoot.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let previewURL = cacheDirectory.appending(path: "报告.pdf")
        try Data("preview".utf8).write(to: previewURL)
        let model = AppModel(loader: StubArchiveDocumentLoader(
            snapshot: snapshot,
            previewURL: previewURL
        ))

        await model.openArchive(url: sourceURL)
        await model.loadSelectedPreview()

        XCTAssertEqual(model.previewCacheURL?.url, previewURL.standardizedFileURL)
        XCTAssertFalse(model.isPreviewLoading)
        XCTAssertNil(model.previewErrorMessage)
    }

    @MainActor
    func testEncryptedSelectedEntryShowsPasswordMessageWithoutMaterializing() async throws {
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("机密/方案.pdf".utf8)),
            displayPath: "机密/方案.pdf"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: URL(fileURLWithPath: "/tmp/加密.zip"),
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 8,
                uncompressedSize: 12,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: true,
                usesUTF8FileName: true
            )]
        )
        let loader = StubArchiveDocumentLoader(snapshot: snapshot)
        let model = AppModel(loader: loader)

        await model.openArchive(url: snapshot.sourceURL)
        await model.loadSelectedPreview()

        XCTAssertEqual(model.previewErrorMessage, "这个文件需要压缩包密码才能预览。")
        let materializationCount = await loader.materializationCount
        XCTAssertEqual(materializationCount, 0)
        XCTAssertFalse(model.isPreviewLoading)
    }

    @MainActor
    func testEncryptedPreviewUsesEnglishCatalogWhenEnglishIsSelected() async throws {
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("Confidential/Plan.pdf".utf8)),
            displayPath: "Confidential/Plan.pdf"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: URL(fileURLWithPath: "/tmp/encrypted.zip"),
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 8,
                uncompressedSize: 12,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: true,
                usesUTF8FileName: true
            )]
        )
        let model = AppModel(
            loader: StubArchiveDocumentLoader(snapshot: snapshot),
            localization: AppLocalization(
                bundle: Bundle(for: Self.self),
                locale: Locale(identifier: "en")
            )
        )

        await model.openArchive(url: snapshot.sourceURL)
        await model.loadSelectedPreview()

        XCTAssertEqual(
            model.previewErrorMessage,
            "This file requires the archive password before it can be previewed."
        )
    }

    @MainActor
    func testPreviewErrorsUseEnglishCatalogWhenEnglishIsSelected() async throws {
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("Documents/Report.pdf".utf8)),
            displayPath: "Documents/Report.pdf"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: URL(fileURLWithPath: "/tmp/archive.zip"),
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 8,
                uncompressedSize: 12,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: false,
                usesUTF8FileName: true
            )]
        )
        let cases: [(ArchiveError, String)] = [
            (.passwordRequired, "A correct archive password is required to preview this file."),
            (.wrongPassword, "A correct archive password is required to preview this file."),
            (.resourceLimit, "This file is too large, so preview generation stopped."),
            (.unsupportedMethod, "This compression or encryption method cannot be previewed."),
            (.unsupportedEncryption, "This compression or encryption method cannot be previewed."),
            (.unsafePath, "This file has an unsafe path, so preview generation stopped."),
            (.sourceChanged, "The archive changed. Open it again before previewing."),
            (.corruptedArchive, "A safe preview could not be generated for this file."),
        ]
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        for (error, expectedMessage) in cases {
            let model = AppModel(
                loader: StubArchiveDocumentLoader(snapshot: snapshot, previewError: error),
                localization: localization
            )
            await model.openArchive(url: snapshot.sourceURL)

            await model.loadSelectedPreview()

            XCTAssertEqual(model.previewErrorMessage, expectedMessage)
        }
    }

    @MainActor
    func testCancelledPreviewDoesNotShowAFalseFailure() async throws {
        let entry = ArchiveEntry(
            id: ArchiveEntryID(),
            rawPath: ArchivePathBytes(Array("文档/报告.pdf".utf8)),
            displayPath: "文档/报告.pdf"
        )
        let snapshot = ArchiveDocumentSnapshot(
            sourceURL: URL(fileURLWithPath: "/tmp/预览.zip"),
            format: .zip,
            entries: [ArchiveEntrySnapshot(
                entry: entry,
                compressedSize: 8,
                uncompressedSize: 12,
                modifiedAt: nil,
                isDirectory: false,
                isSymbolicLink: false,
                isEncrypted: false,
                usesUTF8FileName: true
            )]
        )
        let loader = StubArchiveDocumentLoader(snapshot: snapshot, previewDelay: .seconds(5))
        let model = AppModel(loader: loader)
        await model.openArchive(url: snapshot.sourceURL)

        let task = Task { @MainActor in await model.loadSelectedPreview() }
        while await loader.materializationCount == 0 { await Task.yield() }
        task.cancel()
        await task.value

        XCTAssertNil(model.previewErrorMessage)
        XCTAssertNil(model.previewCacheURL)
        XCTAssertFalse(model.isPreviewLoading)
    }

    @MainActor
    func testModelPublishesExtractionProgressAndCompletionState() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/资料包.zip")
        let snapshot = ArchiveDocumentSnapshot(sourceURL: sourceURL, format: .zip, entries: [])
        let outputURL = URL(fileURLWithPath: "/tmp/资料包")
        let loader = StubArchiveDocumentLoader(snapshot: snapshot, extractionURL: outputURL)
        let model = AppModel(loader: loader)
        await model.openArchive(url: sourceURL)

        await model.extractAll(to: URL(fileURLWithPath: "/tmp"))

        XCTAssertFalse(model.isExtracting)
        XCTAssertEqual(model.extractionProgress, 1)
        XCTAssertEqual(model.lastExtractionURL, outputURL)
        XCTAssertEqual(model.statusMessage, "解压缩完成：资料包")
        XCTAssertNil(model.extractionErrorMessage)
    }

    @MainActor
    func testModelCanCancelAnInFlightExtractionTask() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/大资料包.zip")
        let snapshot = ArchiveDocumentSnapshot(sourceURL: sourceURL, format: .zip, entries: [])
        let loader = StubArchiveDocumentLoader(
            snapshot: snapshot,
            extractionURL: URL(fileURLWithPath: "/tmp/大资料包"),
            extractionDelay: .seconds(5)
        )
        let model = AppModel(loader: loader)
        await model.openArchive(url: sourceURL)

        model.startExtraction(to: URL(fileURLWithPath: "/tmp"))
        while !model.isExtracting { await Task.yield() }
        model.cancelExtraction()
        while model.isExtracting { await Task.yield() }

        XCTAssertEqual(model.statusMessage, "已取消解压缩")
        XCTAssertNil(model.lastExtractionURL)
        XCTAssertFalse(model.canCancelExtraction)
    }

    @MainActor
    func testOpeningMalformedArchiveClearsPreviousExtractionState() async {
        let model = AppModel(loader: StubArchiveDocumentLoader(error: .corruptedArchive))
        model.extractionProgress = 1
        model.lastExtractionURL = URL(fileURLWithPath: "/tmp/旧资料包")
        model.extractionErrorMessage = "旧错误"
        model.operationMessage = "解压缩完成"

        await model.openArchive(url: URL(fileURLWithPath: "/tmp/损坏.zip"))

        XCTAssertEqual(model.extractionProgress, 0)
        XCTAssertNil(model.lastExtractionURL)
        XCTAssertNil(model.extractionErrorMessage)
        XCTAssertEqual(model.operationMessage, "当前没有进行中的操作")
    }

    @MainActor
    func testOpeningArchiveCancelsPreviousExtractionBeforeApplyingSnapshot() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/新资料包.zip")
        let snapshot = ArchiveDocumentSnapshot(sourceURL: sourceURL, format: .zip, entries: [])
        let loader = StubArchiveDocumentLoader(
            snapshot: snapshot,
            extractionURL: URL(fileURLWithPath: "/tmp/旧资料包"),
            extractionDelay: .milliseconds(200)
        )
        let model = AppModel(loader: loader)
        await model.openArchive(url: sourceURL)
        model.startExtraction(to: URL(fileURLWithPath: "/tmp"))
        while !model.isExtracting { await Task.yield() }

        await model.openArchive(url: sourceURL)
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(model.isExtracting)
        XCTAssertFalse(model.canCancelExtraction)
        XCTAssertNil(model.lastExtractionURL)
        XCTAssertEqual(model.extractionProgress, 0)
        XCTAssertEqual(model.operationMessage, "当前没有进行中的操作")
    }

    @MainActor
    func testExtractionErrorsUseEnglishCatalogWhenEnglishIsSelected() async {
        let cases: [(ArchiveError, String)] = [
            (.passwordRequired, "A correct password is required to extract this archive."),
            (.unsafePath, "The archive contains an unsafe file path. Extraction stopped and no files were created."),
            (.resourceLimit, "The archive exceeds the safe extraction limits, so no files were created."),
            (.unsupportedEncryption, "This encryption method is not supported yet, so no files were created."),
            (.unsupportedMethod, "This compression method is not supported yet, so no files were created."),
            (.corruptedArchive, "The archive may be damaged. Extraction did not finish and no files were created."),
            (.helperFailed, "Extraction could not be completed and no files were created."),
        ]
        let sourceURL = URL(fileURLWithPath: "/tmp/archive.zip")
        let snapshot = ArchiveDocumentSnapshot(sourceURL: sourceURL, format: .zip, entries: [])
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        for (error, expectedMessage) in cases {
            let model = AppModel(
                loader: StubArchiveDocumentLoader(snapshot: snapshot, extractionError: error),
                localization: localization
            )
            await model.openArchive(url: sourceURL)

            await model.extractAll(to: URL(fileURLWithPath: "/tmp"))

            XCTAssertEqual(model.extractionErrorMessage, expectedMessage)
            XCTAssertEqual(model.operationMessage, "Extraction failed")
        }
    }

    @MainActor
    func testModelPublishesCreationProgressAndOpensCreatedArchive() async throws {
        let outputURL = URL(fileURLWithPath: "/tmp/Windows兼容资料.zip")
        let snapshot = ArchiveDocumentSnapshot(sourceURL: outputURL, format: .zip, entries: [])
        let loader = StubCreationDocumentLoader(snapshot: snapshot)
        let model = AppModel(loader: loader)

        await model.createWindowsZIP(
            at: outputURL,
            inputs: [URL(fileURLWithPath: "/tmp/资料")]
        )

        XCTAssertFalse(model.isCreating)
        XCTAssertEqual(model.creationProgress, 1)
        XCTAssertEqual(model.lastCreatedURL, outputURL)
        XCTAssertNil(model.creationErrorMessage)
        XCTAssertTrue(model.hasDocument)
        XCTAssertEqual(model.documentTitle, "Windows兼容资料.zip")
        XCTAssertEqual(model.statusMessage, "创建完成：Windows兼容资料.zip")
    }

    @MainActor
    func testCreationCompletionUsesEnglishCatalogWhenEnglishIsSelected() async {
        let outputURL = URL(fileURLWithPath: "/tmp/WindowsCompatible.zip")
        let snapshot = ArchiveDocumentSnapshot(sourceURL: outputURL, format: .zip, entries: [])
        let model = AppModel(
            loader: StubCreationDocumentLoader(snapshot: snapshot),
            localization: AppLocalization(
                bundle: Bundle(for: Self.self),
                locale: Locale(identifier: "en")
            )
        )

        await model.createWindowsZIP(
            at: outputURL,
            inputs: [URL(fileURLWithPath: "/tmp/Input")]
        )

        XCTAssertEqual(model.statusMessage, "Created: WindowsCompatible.zip")
        XCTAssertEqual(model.operationMessage, "Creation complete")
    }

    @MainActor
    func testCreationFailuresUseNaturalChineseAndDescribeLocalFileOutcome() async {
        let cases: [(StubCreationDocumentLoader.Failure, String)] = [
            (
                .profile(.invalidName("CON.txt")),
                "“CON.txt”不符合 Windows 文件名规则，请重命名后再试。"
            ),
            (
                .profile(.unsupportedItem("资料链接")),
                "“资料链接”是特殊文件类型，无法归档。"
            ),
            (
                .archive(.corruptedArchive),
                "创建后的校验未通过，未生成压缩包。"
            ),
        ]

        for (failure, expectedMessage) in cases {
            let model = AppModel(loader: StubCreationDocumentLoader(failure: failure))

            await model.createWindowsZIP(
                at: URL(fileURLWithPath: "/tmp/Windows兼容资料.zip"),
                inputs: [URL(fileURLWithPath: "/tmp/资料")]
            )

            XCTAssertEqual(model.creationErrorMessage, expectedMessage)
            XCTAssertEqual(model.operationMessage, "创建失败")
            XCTAssertNil(model.lastCreatedURL)
        }
    }

    @MainActor
    func testCreationFailuresUseEnglishCatalogWhenEnglishIsSelected() async {
        let cases: [(StubCreationDocumentLoader.Failure, String)] = [
            (
                .profile(.noInputs),
                "There are no files to archive."
            ),
            (
                .profile(.invalidName("CON.txt")),
                "“CON.txt” is not valid on Windows. Rename it and try again."
            ),
            (
                .profile(.collision("Readme.txt", "README.TXT")),
                "“Readme.txt” and “README.TXT” conflict on Windows."
            ),
            (
                .profile(.unsupportedItem("资料链接")),
                "“资料链接” is a special file type and cannot be archived."
            ),
            (
                .profile(.outputExists),
                "An archive with the same name already exists at the destination. The existing file was not replaced."
            ),
            (
                .profile(.io(EACCES)),
                "The destination could not be written to, so no archive was created."
            ),
            (
                .archive(.corruptedArchive),
                "Verification failed after creation, so no archive was created."
            ),
        ]
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        for (failure, expectedMessage) in cases {
            let model = AppModel(
                loader: StubCreationDocumentLoader(failure: failure),
                localization: localization
            )

            await model.createWindowsZIP(
                at: URL(fileURLWithPath: "/tmp/WindowsCompatible.zip"),
                inputs: [URL(fileURLWithPath: "/tmp/Input")]
            )

            XCTAssertEqual(model.creationErrorMessage, expectedMessage)
        }
    }
}

private func loaderPseudoRandomData(count: Int) -> Data {
    var state: UInt64 = 0x9e3779b97f4a7c15
    return Data((0..<count).map { _ in
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return UInt8(truncatingIfNeeded: state)
    })
}

private final class CreationProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: WindowsZIPCreationProgress?

    var latest: WindowsZIPCreationProgress? {
        lock.withLock { value }
    }

    func record(_ progress: WindowsZIPCreationProgress) {
        lock.withLock { value = progress }
    }
}

private final class LoaderZIPFixture {
    let archiveURL: URL
    private let rootURL: URL

    init(entries: [String: Data]) throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "MacUnzipLoaderTests-" + UUID().uuidString,
            directoryHint: .isDirectory
        )
        let contentsURL = rootURL.appending(path: "contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        for (path, data) in entries {
            let url = contentsURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        archiveURL = rootURL.appending(path: "fixture.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archiveURL.path, "."]
        process.currentDirectoryURL = contentsURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private actor StubArchiveDocumentLoader: ArchiveDocumentLoading {
    private let snapshot: ArchiveDocumentSnapshot?
    private let error: ArchiveError?
    private let previewURL: URL?
    private let previewDelay: Duration?
    private let extractionURL: URL?
    private let extractionDelay: Duration?
    private var extractionError: ArchiveError? = nil
    private var previewError: ArchiveError? = nil
    private(set) var materializationCount = 0

    init(snapshot: ArchiveDocumentSnapshot) {
        self.snapshot = snapshot
        error = nil
        previewURL = nil
        previewDelay = nil
        extractionURL = nil
        extractionDelay = nil
    }

    init(snapshot: ArchiveDocumentSnapshot, previewURL: URL) {
        self.snapshot = snapshot
        error = nil
        self.previewURL = previewURL
        previewDelay = nil
        extractionURL = nil
        extractionDelay = nil
    }

    init(snapshot: ArchiveDocumentSnapshot, previewDelay: Duration) {
        self.snapshot = snapshot
        error = nil
        previewURL = nil
        self.previewDelay = previewDelay
        extractionURL = nil
        extractionDelay = nil
    }

    init(snapshot: ArchiveDocumentSnapshot, previewError: ArchiveError) {
        self.snapshot = snapshot
        error = nil
        previewURL = nil
        previewDelay = nil
        extractionURL = nil
        extractionDelay = nil
        self.previewError = previewError
    }

    init(error: ArchiveError) {
        snapshot = nil
        self.error = error
        previewURL = nil
        previewDelay = nil
        extractionURL = nil
        extractionDelay = nil
    }

    init(snapshot: ArchiveDocumentSnapshot, extractionURL: URL) {
        self.snapshot = snapshot
        error = nil
        previewURL = nil
        previewDelay = nil
        self.extractionURL = extractionURL
        extractionDelay = nil
    }

    init(snapshot: ArchiveDocumentSnapshot, extractionURL: URL, extractionDelay: Duration) {
        self.snapshot = snapshot
        error = nil
        previewURL = nil
        previewDelay = nil
        self.extractionURL = extractionURL
        self.extractionDelay = extractionDelay
    }

    init(snapshot: ArchiveDocumentSnapshot, extractionError: ArchiveError) {
        self.snapshot = snapshot
        error = nil
        previewURL = nil
        previewDelay = nil
        extractionURL = nil
        extractionDelay = nil
        self.extractionError = extractionError
    }

    func open(url: URL) async throws -> ArchiveDocumentSnapshot {
        if let error { throw error }
        return try XCTUnwrap(snapshot)
    }

    func materializePreview(entryID: ArchiveEntryID) async throws -> URL {
        materializationCount += 1
        if let previewError { throw previewError }
        if let previewDelay { try await Task.sleep(for: previewDelay) }
        return try XCTUnwrap(previewURL)
    }

    func extractAll(
        to destinationDirectoryURL: URL,
        progress: @Sendable (ZIPExtractionProgress) -> Void
    ) async throws -> URL {
        if let extractionError { throw extractionError }
        guard let extractionURL else { throw ArchiveError.helperFailed }
        if let extractionDelay { try await Task.sleep(for: extractionDelay) }
        progress(ZIPExtractionProgress(
            completedEntries: 0,
            totalEntries: 2,
            completedBytes: 0,
            totalBytes: 100
        ))
        progress(ZIPExtractionProgress(
            completedEntries: 2,
            totalEntries: 2,
            completedBytes: 100,
            totalBytes: 100
        ))
        return extractionURL
    }
}

private actor StubCreationDocumentLoader: ArchiveDocumentLoading {
    enum Failure: Sendable {
        case profile(WindowsZIPProfileError)
        case archive(ArchiveError)
    }

    private let snapshot: ArchiveDocumentSnapshot?
    private let failure: Failure?

    init(snapshot: ArchiveDocumentSnapshot) {
        self.snapshot = snapshot
        failure = nil
    }

    init(failure: Failure) {
        snapshot = nil
        self.failure = failure
    }

    func open(url: URL) async throws -> ArchiveDocumentSnapshot {
        try XCTUnwrap(snapshot)
    }

    func materializePreview(entryID: ArchiveEntryID) async throws -> URL {
        throw ArchiveError.helperFailed
    }

    func extractAll(
        to destinationDirectoryURL: URL,
        progress: @Sendable (ZIPExtractionProgress) -> Void
    ) async throws -> URL {
        throw ArchiveError.helperFailed
    }

    func createWindowsZIP(
        at outputURL: URL,
        inputs: [URL],
        progress: @Sendable (WindowsZIPCreationProgress) -> Void
    ) async throws -> ArchiveDocumentSnapshot {
        if let failure {
            switch failure {
            case .profile(let error): throw error
            case .archive(let error): throw error
            }
        }
        progress(WindowsZIPCreationProgress(
            completedEntries: 0,
            totalEntries: 1,
            completedBytes: 0,
            totalBytes: 100
        ))
        progress(WindowsZIPCreationProgress(
            completedEntries: 1,
            totalEntries: 1,
            completedBytes: 100,
            totalBytes: 100
        ))
        return try XCTUnwrap(snapshot)
    }
}
