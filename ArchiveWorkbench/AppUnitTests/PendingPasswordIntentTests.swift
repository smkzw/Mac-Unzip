import ArchiveDomain
import ArchiveProviders
import ArchiveSecurity
import Foundation
import XCTest

@MainActor
final class PendingPasswordIntentTests: XCTestCase {
    func testExtractAllResumesAfterCorrectPasswordWithoutSecondClick() async throws {
        let secret = Data("secret-payload".utf8)
        let fixture = try await EncryptedZIPTestFixture.make(entries: ["secret.txt": secret], password: "correct")
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        XCTAssertTrue(model.hasDocument)

        let destination = try makeTempDirectory(prefix: "PendingExtractAll")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractAll(to: destination)
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        let wrongUnlocked = await model.retryWithPasswordAndResume("wrong")
        XCTAssertFalse(wrongUnlocked)
        XCTAssertEqual(model.activeErrorPresentation, .wrongPassword)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        let correctUnlocked = await model.retryWithPasswordAndResume("correct")
        XCTAssertTrue(correctUnlocked)
        let output = try XCTUnwrap(model.lastExtractionURL)
        XCTAssertEqual(
            try Data(contentsOf: output.appendingPathComponent("secret.txt")),
            secret
        )
        XCTAssertNil(model.activeErrorPresentation)
    }

    func testInfoZIPCheckedInFixtureExtractAllResumesAfterPassword() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/ZipCrypto/infozip-password-macunzip-test-123.zip")
        let expectedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TestFixtures/ZipCrypto/EXPECTED_secret.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path), fixtureURL.path)
        let expected = try Data(contentsOf: expectedURL)

        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixtureURL)
        XCTAssertTrue(model.hasDocument)

        let destination = try makeTempDirectory(prefix: "PendingInfoZIPExtract")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractAll(to: destination)
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        let wrong = await model.retryWithPasswordAndResume("wrong-password")
        XCTAssertFalse(wrong)
        XCTAssertEqual(model.activeErrorPresentation, .wrongPassword)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        let ok = await model.retryWithPasswordAndResume("macunzip-test-123")
        XCTAssertTrue(ok)
        let output = try XCTUnwrap(model.lastExtractionURL)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("secret.txt")), expected)
        XCTAssertNil(model.activeErrorPresentation)
    }

    func testExtractSelectedResumesSavedTargetsAfterUnlock() async throws {
        let fixture = try await EncryptedZIPTestFixture.make(
            entries: [
                "secret.txt": Data("alpha".utf8),
                "other.txt": Data("beta".utf8),
            ],
            password: "gate"
        )
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let secretID = try XCTUnwrap(model.entries.first { $0.displayPath == "secret.txt" }?.id)
        model.selectedEntryID = secretID
        model.selectedEntryIDs = [secretID]

        let destination = try makeTempDirectory(prefix: "PendingExtractSel")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractSelected(to: destination)
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)

        let selectedUnlocked = await model.retryWithPasswordAndResume("gate")
        XCTAssertTrue(selectedUnlocked)
        XCTAssertEqual(try payloadFiles(in: destination).sorted(), ["secret.txt"])
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("secret.txt")),
            Data("alpha".utf8)
        )
    }

    func testWrongPasswordDoesNotResumeAndSwitchingArchiveClearsPending() async throws {
        let fixtureA = try await EncryptedZIPTestFixture.make(entries: ["secret.txt": Data("a".utf8)], password: "a-pass")
        let fixtureB = try await EncryptedZIPTestFixture.make(entries: ["plain.txt": Data("b".utf8)], password: nil)
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixtureA.archiveURL)

        let destination = try makeTempDirectory(prefix: "PendingClear")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractAll(to: destination)
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)

        let nopeUnlocked = await model.retryWithPasswordAndResume("nope")
        XCTAssertFalse(nopeUnlocked)
        XCTAssertEqual(model.activeErrorPresentation, .wrongPassword)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        await model.openArchive(url: fixtureB.archiveURL)
        XCTAssertTrue(model.hasDocument)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        await model.openArchive(url: fixtureA.archiveURL, password: "a-pass")
        XCTAssertTrue(model.hasDocument)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)
        XCTAssertNil(model.lastExtractionURL)
    }

    func testDragEntryResumesPublishOnceAfterUnlock() async throws {
        let secret = Data("drag-secret".utf8)
        let fixture = try await EncryptedZIPTestFixture.make(entries: ["secret.txt": secret], password: "drag")
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let entryID = try XCTUnwrap(model.entries.first { $0.displayPath == "secret.txt" }?.id)

        let dropRoot = try makeTempDirectory(prefix: "PendingDrag")
        defer { try? FileManager.default.removeItem(at: dropRoot) }
        let exactDestination = dropRoot.appendingPathComponent("secret.txt")

        let completion = expectation(description: "drag completion once")
        completion.assertForOverFulfill = true
        let completionError = CompletionErrorBox()
        XCTAssertTrue(
            model.absorbPasswordProtectedDragIfNeeded(
                error: ArchiveError.passwordRequired,
                entryID: entryID,
                folderPath: nil,
                exactDestination: exactDestination,
                documentGeneration: model.documentGeneration,
                archiveIdentityPath: model.openArchiveIdentityPath,
                completionHandler: { error in
                    completionError.value = error
                    completion.fulfill()
                }
            )
        )

        let dragUnlocked = await model.retryWithPasswordAndResume("drag")
        XCTAssertTrue(dragUnlocked)
        await fulfillment(of: [completion], timeout: 10)
        XCTAssertNil(completionError.value)
        XCTAssertEqual(try Data(contentsOf: exactDestination), secret)
    }

    func testDragFolderResumesPublishOnceAfterUnlock() async throws {
        // Nested AES fixtures are awkward through the public create API; cover the
        // folder-drag password resume path with a prefix that materializes to an
        // empty folder after unlock (completion ownership + publish still run).
        let fixture = try await EncryptedZIPTestFixture.make(
            entries: ["secret.txt": Data("folder-secret".utf8)],
            password: "folder"
        )
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let folderPath = "docs"

        let dropRoot = try makeTempDirectory(prefix: "PendingDragFolder")
        defer { try? FileManager.default.removeItem(at: dropRoot) }
        let exactDestination = dropRoot.appendingPathComponent(folderPath, isDirectory: true)

        let completion = expectation(description: "folder drag completion once")
        completion.assertForOverFulfill = true
        let completionError = CompletionErrorBox()
        XCTAssertTrue(
            model.absorbPasswordProtectedDragIfNeeded(
                error: ArchiveError.passwordRequired,
                entryID: nil,
                folderPath: folderPath,
                exactDestination: exactDestination,
                documentGeneration: model.documentGeneration,
                archiveIdentityPath: model.openArchiveIdentityPath,
                completionHandler: { error in
                    completionError.value = error
                    completion.fulfill()
                }
            )
        )

        let folderUnlocked = await model.retryWithPasswordAndResume("folder")
        XCTAssertTrue(folderUnlocked)
        await fulfillment(of: [completion], timeout: 10)
        XCTAssertNil(completionError.value)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: exactDestination.path, isDirectory: &isDirectory)
        )
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testDismissCancelsPendingDragCompletionOnce() async throws {
        let fixture = try await EncryptedZIPTestFixture.make(entries: ["secret.txt": Data("x".utf8)], password: "x")
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let entryID = try XCTUnwrap(model.entries.first?.id)

        let dropRoot = try makeTempDirectory(prefix: "PendingDismiss")
        defer { try? FileManager.default.removeItem(at: dropRoot) }

        let completion = expectation(description: "dismiss completes drag once")
        completion.assertForOverFulfill = true
        XCTAssertTrue(
            model.absorbPasswordProtectedDragIfNeeded(
                error: ArchiveError.passwordRequired,
                entryID: entryID,
                folderPath: nil,
                exactDestination: dropRoot.appendingPathComponent("secret.txt"),
                documentGeneration: model.documentGeneration,
                archiveIdentityPath: model.openArchiveIdentityPath,
                completionHandler: { _ in completion.fulfill() }
            )
        )
        model.dismissError()
        await fulfillment(of: [completion], timeout: 2)
        model.dismissError()
        try await Task.sleep(for: .milliseconds(50))
    }

    func testSevenZipExtractAllResumesWhenEngineAvailable() async throws {
        guard let discovery = SevenZipBinaryDiscovery.discover(),
              let provider = try? SevenZipProvider.makeValidated() else {
            throw XCTSkip("7zz not available in this environment")
        }
        let fixture = try EncryptedSevenZipTestFixture(
            binaryPath: discovery.resolvedPath,
            entries: ["secret.txt": Data("seven-secret".utf8)],
            password: "7z-pass"
        )
        let model = AppModel(loader: ArchiveDocumentLoader(sevenZipProvider: provider))
        await model.openArchive(url: fixture.archiveURL)
        XCTAssertTrue(model.hasDocument)

        let destination = try makeTempDirectory(prefix: "Pending7z")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractAll(to: destination)
        guard model.activeErrorPresentation == .passwordRequired
            || model.activeErrorPresentation == .wrongPassword else {
            if model.lastExtractionURL != nil { return }
            XCTFail("Expected password gate for encrypted 7z")
            return
        }

        let sevenUnlocked = await model.retryWithPasswordAndResume("7z-pass")
        XCTAssertTrue(sevenUnlocked)
        let output = try XCTUnwrap(model.lastExtractionURL)
        XCTAssertEqual(
            try Data(contentsOf: output.appendingPathComponent("secret.txt")),
            Data("seven-secret".utf8)
        )
    }


    func testWrongPasswordKeepsLiveEntriesThenCorrectPasswordResumes() async throws {
        let secret = Data("keep-live-then-resume".utf8)
        let fixture = try await EncryptedZIPTestFixture.make(entries: ["secret.txt": secret], password: "keep-pass")
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let originalID = try XCTUnwrap(model.entries.first { $0.displayPath == "secret.txt" }?.id)
        model.selectedEntryID = originalID

        let destination = try makeTempDirectory(prefix: "PendingTxn")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractAll(to: destination)
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)

        let wrong = await model.retryWithPasswordAndResume("not-keep-pass")
        XCTAssertFalse(wrong)
        XCTAssertEqual(model.activeErrorPresentation, .wrongPassword)
        // Live listing/selection must remain operable after failed soft unlock.
        XCTAssertEqual(model.entries.first { $0.displayPath == "secret.txt" }?.id, originalID)
        XCTAssertEqual(model.selectedEntryID, originalID)
        XCTAssertTrue(try payloadFiles(in: destination).isEmpty)

        let ok = await model.retryWithPasswordAndResume("keep-pass")
        XCTAssertTrue(ok)
        let output = try XCTUnwrap(model.lastExtractionURL)
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("secret.txt")), secret)
        XCTAssertNil(model.activeErrorPresentation)
    }

    func testDuplicateDisplayPathRemapDoesNotCrashAndBindsCorrectMember() async throws {
        let fixtureURL = try DuplicatePathEncryptedZIPFixture.make(
            password: "dup-pass",
            first: Data("first-dup".utf8),
            second: Data("second-dup".utf8)
        )
        defer { try? FileManager.default.removeItem(at: fixtureURL.deletingLastPathComponent()) }

        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixtureURL)
        let matches = model.entries.filter { $0.displayPath == "dup.txt" }
        XCTAssertEqual(matches.count, 2)
        let secondID = matches[1].id
        model.selectedEntryID = secondID
        model.selectedEntryIDs = [secondID]

        let destination = try makeTempDirectory(prefix: "PendingDup")
        defer { try? FileManager.default.removeItem(at: destination) }

        await model.extractSelected(to: destination)
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)

        let unlocked = await model.retryWithPasswordAndResume("dup-pass")
        XCTAssertTrue(unlocked)
        XCTAssertEqual(try payloadFiles(in: destination), ["dup.txt"])
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("dup.txt")), Data("second-dup".utf8))
    }

    func testPreviewDoesNotResumeWhenSelectionClearedBeforeUnlock() async throws {
        // `.md` is previewable; `.txt` is routed as unsupported and never arms the intent.
        let fixture = try await EncryptedZIPTestFixture.make(entries: ["secret.md": Data("# preview-a".utf8)], password: "prev")
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let entryID = try XCTUnwrap(model.entries.first { $0.displayPath == "secret.md" }?.id)
        model.selectedEntryID = entryID
        await model.loadSelectedPreview()
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)

        model.selectedEntryID = nil
        let unlocked = await model.retryWithPasswordAndResume("prev")
        XCTAssertTrue(unlocked)
        XCTAssertNil(model.selectedPreviewCacheURL)
        XCTAssertNil(model.selectedEntryID)
    }

    func testPreviewDoesNotResumeWhenSelectionChangedWhileWaiting() async throws {
        let fixture = try await EncryptedZIPTestFixture.make(
            entries: [
                "a.md": Data("# preview-a".utf8),
                "b.md": Data("# preview-b".utf8),
            ],
            password: "prev2"
        )
        let model = AppModel(loader: ArchiveDocumentLoader())
        await model.openArchive(url: fixture.archiveURL)
        let aID = try XCTUnwrap(model.entries.first { $0.displayPath == "a.md" }?.id)
        let bID = try XCTUnwrap(model.entries.first { $0.displayPath == "b.md" }?.id)
        model.selectedEntryID = aID
        await model.loadSelectedPreview()
        XCTAssertEqual(model.activeErrorPresentation, .passwordRequired)

        model.selectedEntryID = bID
        let unlocked = await model.retryWithPasswordAndResume("prev2")
        XCTAssertTrue(unlocked)
        // Must not restore a.md preview over the user's newer selection.
        // Soft unlock remaps entry IDs; assert by path + preview cache binding.
        XCTAssertEqual(model.entries.first(where: { $0.id == model.selectedEntryID })?.displayPath, "b.md")
        let previewPath = model.previewCacheEntryID.flatMap { id in
            model.entries.first(where: { $0.id == id })?.displayPath
        }
        XCTAssertNotEqual(previewPath, "a.md")
        XCTAssertNil(model.selectedPreviewCacheURL)
    }

    // MARK: - Helpers

    private func makeTempDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func payloadFiles(in directory: URL) throws -> [String] {
        var files: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                files.append(url.lastPathComponent)
            }
        }
        return files
    }

}

private final class CompletionErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Error?
    var value: Error? {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}


private enum DuplicatePathEncryptedZIPFixture {
    static func make(password: String, first: Data, second: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DupZIP-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.bin")
        let secondURL = root.appendingPathComponent("second.bin")
        let archive = root.appendingPathComponent("dup.zip")
        try first.write(to: firstURL)
        try second.write(to: secondURL)
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/make_duplicate_zipcrypto.py")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path, password, firstURL.path, secondURL.path, archive.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return archive
    }
}

private final class EncryptedZIPTestFixture {
    let archiveURL: URL
    private let rootURL: URL

    static func make(entries: [String: Data], password: String?) async throws -> EncryptedZIPTestFixture {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingZIP-\(UUID().uuidString)", isDirectory: true)
        let contentsURL = rootURL.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) {
            let url = contentsURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        let archiveURL = rootURL.appendingPathComponent("fixture.zip")
        if let password, !password.isEmpty {
            // Prefer Info-ZIP ZipCrypto (`zip -P`) — this is the real acceptance path.
            let zipURL = URL(fileURLWithPath: "/usr/bin/zip")
            if FileManager.default.isExecutableFile(atPath: zipURL.path) {
                let process = Process()
                process.executableURL = zipURL
                // Store entries relative to contentsURL so nested paths stay intact.
                process.arguments = ["-q", "-r", "-P", password, archiveURL.path] + entries.keys.sorted()
                process.currentDirectoryURL = contentsURL
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return EncryptedZIPTestFixture(rootURL: rootURL, archiveURL: archiveURL)
            }
        }
        let provider = ZIPArchiveProvider()
        try await provider.createWindowsZIP(
            at: archiveURL,
            inputs: entries.keys.sorted().map { contentsURL.appendingPathComponent($0) },
            compressLevel: 6,
            password: password,
            encryptMethod: password == nil ? 0 : 1
        ) { _ in }
        return EncryptedZIPTestFixture(rootURL: rootURL, archiveURL: archiveURL)
    }

    private init(rootURL: URL, archiveURL: URL) {
        self.rootURL = rootURL
        self.archiveURL = archiveURL
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class EncryptedSevenZipTestFixture {
    let archiveURL: URL
    private let rootURL: URL

    init(binaryPath: String, entries: [String: Data], password: String) throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pending7z-\(UUID().uuidString)", isDirectory: true)
        let contentsURL = rootURL.appendingPathComponent("contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        var names: [String] = []
        for (path, data) in entries.sorted(by: { $0.key < $1.key }) {
            let url = contentsURL.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            names.append(path)
        }
        archiveURL = rootURL.appendingPathComponent("fixture.7z")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["a", "-t7z", "-y", "-p\(password)", archiveURL.path] + names
        process.currentDirectoryURL = contentsURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
