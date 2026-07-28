import ArchiveDomain
import ArchiveProviders
import ArchiveSecurity
import Foundation

protocol ArchiveDocumentLoading: Actor {
    var lastDetectionResult: FormatDetectionResult? { get }
    var capabilityRegistry: ArchiveCapabilityRegistry { get }
    func open(url: URL) async throws -> ArchiveDocumentSnapshot
    /// Opens an archive that requires a password. Only ZIP is supported today;
    /// other formats throw `ArchiveError.passwordRequired` via the default
    /// implementation below.
    func openWithPassword(url: URL, password: String) async throws -> ArchiveDocumentSnapshot
    func materializePreview(entryID: ArchiveEntryID) async throws -> URL
    func materializeEntryForExtraction(entryID: ArchiveEntryID, under rootURL: URL) async throws -> URL
    func extractAll(
        to destinationDirectoryURL: URL,
        progress: @Sendable (ZIPExtractionProgress) -> Void
    ) async throws -> URL
    func createWindowsZIP(
        at outputURL: URL,
        inputs: [URL],
        compressLevel: Int32,
        password: String?,
        encryptMethod: Int32,
        progress: @Sendable (WindowsZIPCreationProgress) -> Void
    ) async throws -> ArchiveDocumentSnapshot
    /// Creates a TAR archive (optionally compressed) at outputURL from inputs.
    /// Compression is inferred from the output file name when nil.
    func createTARArchive(
        at outputURL: URL,
        inputs: [URL],
        compression: TARCompression?
    ) async throws -> ArchiveDocumentSnapshot
    func createSevenZip(
        at outputURL: URL,
        inputs: [URL],
        password: String?
    ) async throws -> ArchiveDocumentSnapshot
    func createRAR(
        at outputURL: URL,
        inputs: [URL],
        password: String?
    ) async throws -> ArchiveDocumentSnapshot
    func stageChange(_ change: PendingChange) async throws
    func undoChange(id: String) async -> Bool
    func currentPendingChanges() async -> [PendingChange]
    func saveArchive() async throws -> ArchiveDocumentSnapshot
    func saveArchiveAs(to targetURL: URL) async throws -> ArchiveDocumentSnapshot
}

extension ArchiveDocumentLoading {
    var lastDetectionResult: FormatDetectionResult? { nil }

    var capabilityRegistry: ArchiveCapabilityRegistry { .productionBaseline }

    func openWithPassword(url: URL, password: String) async throws -> ArchiveDocumentSnapshot {
        throw ArchiveError.passwordRequired
    }

    func createWindowsZIP(
        at outputURL: URL,
        inputs: [URL],
        compressLevel: Int32,
        password: String?,
        encryptMethod: Int32,
        progress: @Sendable (WindowsZIPCreationProgress) -> Void
    ) async throws -> ArchiveDocumentSnapshot {
        throw ArchiveError.helperFailed
    }

    func createTARArchive(
        at outputURL: URL,
        inputs: [URL],
        compression: TARCompression?
    ) async throws -> ArchiveDocumentSnapshot {
        throw ArchiveError.helperFailed
    }

    func stageChange(_ change: PendingChange) async throws {
        throw ArchiveError.helperFailed
    }

    func undoChange(id: String) async -> Bool { false }

    func currentPendingChanges() async -> [PendingChange] { [] }

    func saveArchive() async throws -> ArchiveDocumentSnapshot {
        throw ArchiveError.helperFailed
    }

    func saveArchiveAs(to targetURL: URL) async throws -> ArchiveDocumentSnapshot {
        throw ArchiveError.helperFailed
    }
}

actor ArchiveDocumentLoader: ArchiveDocumentLoading {
    private let provider: ZIPArchiveProvider
    private let editor: ArchiveEditor
    /// Read-only 7z provider, present only when a trusted 7zz binary was
    /// discovered and validated at runtime. Nil means 7z is unavailable.
    private let sevenZipProvider: SevenZipProvider?
    /// Read-only RAR provider, present only when a trusted 7zz binary was
    /// discovered and validated at runtime. Nil means RAR is unavailable.
    private let rarProvider: RARArchiveProvider?
    /// TAR provider backed by libarchive. Supports .tar, .tar.gz, .tgz,
    /// .tar.bz2, .tar.xz, .tar.zst with list/read/preview/create capabilities.
    private let tarProvider: TARArchiveProvider
    /// Read-only DMG provider backed by 7zz. Never mounts the disk image;
    /// strictly read-only browsing/extraction without auto-execution risk.
    private let dmgProvider: DMGArchiveProvider?
    /// Read-only ISO provider backed by 7zz. Supports ISO9660/UDF/Joliet/Rock Ridge.
    private let isoProvider: ISOArchiveProvider?
    private var previewSessionURL: URL?
    private var activePreviewRootURL: URL?
    private var currentArchiveURL: URL?
    private var currentFormat: ArchiveFormat?

    init(
        provider: ZIPArchiveProvider = ZIPArchiveProvider(),
        editor: ArchiveEditor = ArchiveEditor(),
        sevenZipProvider: SevenZipProvider? = try? SevenZipProvider.makeValidated(),
        rarProvider: RARArchiveProvider? = try? RARArchiveProvider.makeValidated(),
        tarProvider: TARArchiveProvider = TARArchiveProvider(),
        dmgProvider: DMGArchiveProvider? = try? DMGArchiveProvider.makeValidated(),
        isoProvider: ISOArchiveProvider? = try? ISOArchiveProvider.makeValidated()
    ) {
        self.provider = provider
        self.editor = editor
        self.sevenZipProvider = sevenZipProvider
        self.rarProvider = rarProvider
        self.tarProvider = tarProvider
        self.dmgProvider = dmgProvider
        self.isoProvider = isoProvider
    }

    /// Runtime-discovered capability registry: 7z, RAR, DMG, and ISO capabilities
    /// are exposed only when a validated 7zz binary is present.
    var capabilityRegistry: ArchiveCapabilityRegistry {
        ArchiveCapabilityRegistry.productionBaseline
            .withSevenZipAvailable(sevenZipProvider != nil)
            .withRARAvailable(rarProvider != nil)
            .withRARCreateAvailable(RARBinaryDiscovery.discover() != nil)
            .withDMGAvailable(dmgProvider != nil)
            .withISOAvailable(isoProvider != nil)
    }

    deinit {
        if let previewSessionURL {
            try? FileManager.default.removeItem(at: previewSessionURL)
        }
    }

    /// The last format detection result, available for UI to show mismatch warnings.
    private(set) var lastDetectionResult: FormatDetectionResult?

    func open(url: URL) async throws -> ArchiveDocumentSnapshot {
        try await open(url: url, password: nil)
    }

    func openWithPassword(url: URL, password: String) async throws -> ArchiveDocumentSnapshot {
        try await open(url: url, password: password)
    }

    private func open(url: URL, password: String?) async throws -> ArchiveDocumentSnapshot {
        try resetPreviewSession()
        currentArchiveURL = nil
        currentFormat = nil

        // Detect format by magic bytes before opening
        let detection = try ArchiveFormatDetector.detect(from: url)
        lastDetectionResult = detection
        guard let effectiveFormat = detection.effectiveFormat else {
            throw ArchiveError.unsupportedFormat
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let snapshot: ArchiveDocumentSnapshot
        switch effectiveFormat {
        case .sevenZip:
            // 7z reads go through the isolated, validated 7zz binary only.
            // Never fall back to another engine for this format.
            guard let sevenZipProvider else {
                throw ArchiveError.providerNotInstalled
            }
            if let password, !password.isEmpty {
                snapshot = try await sevenZipProvider.openWithPassword(url: url, password: password)
            } else {
                snapshot = try await sevenZipProvider.open(url: url)
            }
        case .rar:
            // RAR reads go through the isolated, validated 7zz binary only.
            // Supports RAR4/RAR5, solid, multipart, Unicode filenames.
            guard let rarProvider else {
                throw ArchiveError.providerNotInstalled
            }
            if let password, !password.isEmpty {
                snapshot = try await rarProvider.openWithPassword(url: url, password: password)
            } else {
                snapshot = try await rarProvider.open(url: url)
            }
        case .dmg:
            // DMG reads go through 7zz only. Never mount the disk image to avoid
            // auto-execution of embedded code. Strictly read-only.
            guard let dmgProvider else {
                throw ArchiveError.providerNotInstalled
            }
            snapshot = try await dmgProvider.open(url: url)
        case .iso:
            // ISO reads go through 7zz only. Supports ISO9660/UDF/Joliet/Rock Ridge
            // and multi-session ISOs. Strictly read-only.
            guard let isoProvider else {
                throw ArchiveError.providerNotInstalled
            }
            snapshot = try await isoProvider.open(url: url)
        case .tar, .gzip, .bzip2, .xz, .zstandard:
            // TAR and compressed TAR variants go through libarchive.
            snapshot = try await tarProvider.open(url: url)
        case .zip:
            if let password, !password.isEmpty {
                snapshot = try await provider.openWithPassword(
                    url: url,
                    password: SecurePassword(password)
                )
            } else {
                snapshot = try await provider.open(url: url)
            }
            try await editor.open(url: snapshot.sourceURL)
        }
        currentArchiveURL = snapshot.sourceURL
        currentFormat = snapshot.format
        return snapshot
    }

    func materializePreview(entryID: ArchiveEntryID) async throws -> URL {
        try Task.checkCancellation()
        guard let previewSessionURL else { throw ArchiveError.helperFailed }
        let requestRoot = previewSessionURL.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: requestRoot,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let previousRoot = activePreviewRootURL
        activePreviewRootURL = requestRoot
        do {
            try Task.checkCancellation()
            let materializedURL: URL
            if currentFormat == .sevenZip {
                guard let sevenZipProvider else { throw ArchiveError.providerNotInstalled }
                materializedURL = try await sevenZipProvider.materializeEntry(id: entryID, under: requestRoot)
            } else if currentFormat == .rar {
                guard let rarProvider else { throw ArchiveError.providerNotInstalled }
                materializedURL = try await rarProvider.materializeEntry(id: entryID, under: requestRoot)
            } else if currentFormat == .dmg {
                guard let dmgProvider else { throw ArchiveError.providerNotInstalled }
                materializedURL = try await dmgProvider.materializeEntry(id: entryID, under: requestRoot)
            } else if currentFormat == .iso {
                guard let isoProvider else { throw ArchiveError.providerNotInstalled }
                materializedURL = try await isoProvider.materializeEntry(id: entryID, under: requestRoot)
            } else if Self.isTARFormat(currentFormat) {
                materializedURL = try await tarProvider.materializeEntry(id: entryID, under: requestRoot)
            } else {
                materializedURL = try await provider.materializeEntry(id: entryID, under: requestRoot)
            }
            try Task.checkCancellation()
            if let previousRoot, previousRoot != requestRoot {
                try? FileManager.default.removeItem(at: previousRoot)
            }
            return materializedURL
        } catch {
            try? FileManager.default.removeItem(at: requestRoot)
            if let previousRoot, previousRoot != requestRoot {
                try? FileManager.default.removeItem(at: previousRoot)
            }
            if activePreviewRootURL == requestRoot {
                activePreviewRootURL = nil
            }
            throw error
        }
    }

    func materializeEntryForExtraction(entryID: ArchiveEntryID, under rootURL: URL) async throws -> URL {
        try Task.checkCancellation()
        let materializedURL: URL
        if currentFormat == .sevenZip {
            guard let sevenZipProvider else { throw ArchiveError.providerNotInstalled }
            materializedURL = try await sevenZipProvider.materializeEntry(id: entryID, under: rootURL, budget: .extractionDefault)
        } else if currentFormat == .rar {
            guard let rarProvider else { throw ArchiveError.providerNotInstalled }
            materializedURL = try await rarProvider.materializeEntry(id: entryID, under: rootURL, budget: .extractionDefault)
        } else if currentFormat == .dmg {
            guard let dmgProvider else { throw ArchiveError.providerNotInstalled }
            materializedURL = try await dmgProvider.materializeEntry(id: entryID, under: rootURL, budget: .extractionDefault)
        } else if currentFormat == .iso {
            guard let isoProvider else { throw ArchiveError.providerNotInstalled }
            materializedURL = try await isoProvider.materializeEntry(id: entryID, under: rootURL, budget: .extractionDefault)
        } else if Self.isTARFormat(currentFormat) {
            materializedURL = try await tarProvider.materializeEntry(id: entryID, under: rootURL, budget: .extractionDefault)
        } else {
            materializedURL = try await provider.materializeEntry(id: entryID, under: rootURL, budget: .extractionDefault)
        }
        return materializedURL
    }

    func extractAll(
        to destinationDirectoryURL: URL,
        progress: @Sendable (ZIPExtractionProgress) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        guard let currentArchiveURL else { throw ArchiveError.helperFailed }
        let accessed = destinationDirectoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { destinationDirectoryURL.stopAccessingSecurityScopedResource() }
        }

        let baseName = Self.archiveBaseName(from: currentArchiveURL)
        let finalURL = try availableExtractionURL(baseName: baseName, under: destinationDirectoryURL)
        let stagingURL = destinationDirectoryURL.appending(
            path: ".MacUnzip-\(UUID().uuidString).partial",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var published = false
        defer {
            if !published {
                try? FileManager.default.removeItem(at: stagingURL)
                try? FileManager.default.removeItem(at: finalURL)
            }
        }
        if currentFormat == .sevenZip {
            guard let sevenZipProvider else { throw ArchiveError.providerNotInstalled }
            _ = try await sevenZipProvider.extractAll(under: stagingURL) { sevenZipProgress in
                progress(ZIPExtractionProgress(
                    completedEntries: sevenZipProgress.completedEntries,
                    totalEntries: sevenZipProgress.totalEntries,
                    completedBytes: sevenZipProgress.completedBytes,
                    totalBytes: sevenZipProgress.totalBytes
                ))
            }
        } else if currentFormat == .rar {
            guard let rarProvider else { throw ArchiveError.providerNotInstalled }
            _ = try await rarProvider.extractAll(under: stagingURL) { rarProgress in
                progress(ZIPExtractionProgress(
                    completedEntries: rarProgress.completedEntries,
                    totalEntries: rarProgress.totalEntries,
                    completedBytes: rarProgress.completedBytes,
                    totalBytes: rarProgress.totalBytes
                ))
            }
        } else if currentFormat == .dmg {
            guard let dmgProvider else { throw ArchiveError.providerNotInstalled }
            _ = try await dmgProvider.extractAll(under: stagingURL) { dmgProgress in
                progress(ZIPExtractionProgress(
                    completedEntries: dmgProgress.completedEntries,
                    totalEntries: dmgProgress.totalEntries,
                    completedBytes: dmgProgress.completedBytes,
                    totalBytes: dmgProgress.totalBytes
                ))
            }
        } else if currentFormat == .iso {
            guard let isoProvider else { throw ArchiveError.providerNotInstalled }
            _ = try await isoProvider.extractAll(under: stagingURL) { isoProgress in
                progress(ZIPExtractionProgress(
                    completedEntries: isoProgress.completedEntries,
                    totalEntries: isoProgress.totalEntries,
                    completedBytes: isoProgress.completedBytes,
                    totalBytes: isoProgress.totalBytes
                ))
            }
        } else if Self.isTARFormat(currentFormat) {
            _ = try await tarProvider.extractAll(under: stagingURL) { tarProgress in
                progress(ZIPExtractionProgress(
                    completedEntries: tarProgress.completedEntries,
                    totalEntries: tarProgress.totalEntries,
                    completedBytes: tarProgress.completedBytes,
                    totalBytes: tarProgress.totalBytes
                ))
            }
        } else {
            _ = try await provider.extractAll(under: stagingURL, progress: progress)
        }
        try Task.checkCancellation()
        let stagingContents = try FileManager.default.contentsOfDirectory(at: stagingURL, includingPropertiesForKeys: nil)
        for item in stagingContents {
            try FileManager.default.moveItem(at: item, to: finalURL.appending(path: item.lastPathComponent))
        }
        try FileManager.default.removeItem(at: stagingURL)
        published = true
        return finalURL
    }

    func createWindowsZIP(
        at outputURL: URL,
        inputs: [URL],
        compressLevel: Int32,
        password: String?,
        encryptMethod: Int32,
        progress: @Sendable (WindowsZIPCreationProgress) -> Void
    ) async throws -> ArchiveDocumentSnapshot {
        try Task.checkCancellation()
        let inputAccess = inputs.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let outputAccessed = outputURL.startAccessingSecurityScopedResource()
        defer {
            for (url, accessed) in inputAccess where accessed {
                url.stopAccessingSecurityScopedResource()
            }
            if outputAccessed { outputURL.stopAccessingSecurityScopedResource() }
        }

        try await provider.createWindowsZIP(at: outputURL, inputs: inputs, compressLevel: compressLevel, password: password, encryptMethod: encryptMethod, progress: progress)
        try Task.checkCancellation()
        try resetPreviewSession()
        let snapshot: ArchiveDocumentSnapshot
        if let password, !password.isEmpty {
            snapshot = try await provider.openWithPassword(url: outputURL, password: SecurePassword(password))
        } else {
            snapshot = try await provider.open(url: outputURL)
        }
        try await editor.open(url: snapshot.sourceURL)
        currentArchiveURL = snapshot.sourceURL
        currentFormat = snapshot.format
        return snapshot
    }

    func createTARArchive(
        at outputURL: URL,
        inputs: [URL],
        compression: TARCompression?
    ) async throws -> ArchiveDocumentSnapshot {
        try Task.checkCancellation()
        // Match the ZIP creation contract: never overwrite an existing file.
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw WindowsZIPProfileError.outputExists
        }
        let inputAccess = inputs.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let outputAccessed = outputURL.startAccessingSecurityScopedResource()
        defer {
            for (url, accessed) in inputAccess where accessed {
                url.stopAccessingSecurityScopedResource()
            }
            if outputAccessed { outputURL.stopAccessingSecurityScopedResource() }
        }
        try await tarProvider.createArchive(
            at: outputURL,
            inputs: inputs,
            compression: compression
        )
        try Task.checkCancellation()
        // Reopen through format detection so currentFormat/currentArchiveURL and
        // the returned snapshot stay consistent for the newly created archive.
        return try await open(url: outputURL)
    }

    func createSevenZip(
        at outputURL: URL,
        inputs: [URL],
        password: String?
    ) async throws -> ArchiveDocumentSnapshot {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw WindowsZIPProfileError.outputExists
        }
        guard let sevenZipProvider else {
            throw ArchiveError.providerNotInstalled
        }
        let inputAccess = inputs.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let outputAccessed = outputURL.startAccessingSecurityScopedResource()
        defer {
            for (url, accessed) in inputAccess where accessed {
                url.stopAccessingSecurityScopedResource()
            }
            if outputAccessed { outputURL.stopAccessingSecurityScopedResource() }
        }
        try await sevenZipProvider.createArchive(
            at: outputURL,
            inputs: inputs,
            password: password
        )
        try Task.checkCancellation()
        if let password, !password.isEmpty {
            return try await open(url: outputURL, password: password)
        }
        return try await open(url: outputURL)
    }

    func createRAR(
        at outputURL: URL,
        inputs: [URL],
        password: String?
    ) async throws -> ArchiveDocumentSnapshot {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw WindowsZIPProfileError.outputExists
        }
        guard let discovery = RARBinaryDiscovery.discover() else {
            throw RARCreateProviderError.binaryNotFound
        }
        let license = RARLicenseConfirmation()
        guard license.isConfirmed else {
            throw RARCreateProviderError.licenseNotConfirmed
        }
        let inputAccess = inputs.map { ($0, $0.startAccessingSecurityScopedResource()) }
        let outputAccessed = outputURL.startAccessingSecurityScopedResource()
        defer {
            for (url, accessed) in inputAccess where accessed {
                url.stopAccessingSecurityScopedResource()
            }
            if outputAccessed { outputURL.stopAccessingSecurityScopedResource() }
        }
        let rarProvider = RARCreateProvider(binaryPath: discovery.resolvedPath, binarySHA256: discovery.sha256)
        var options = RARCreateOptions()
        options.password = password
        try await rarProvider.create(
            archiveURL: outputURL,
            sources: inputs.map(\.path),
            options: options
        )
        try Task.checkCancellation()
        if let password, !password.isEmpty {
            return try await open(url: outputURL, password: password)
        }
        return try await open(url: outputURL)
    }

    func stageChange(_ change: PendingChange) async throws {
        try Task.checkCancellation()
        // 7z, RAR, DMG, ISO, and TAR are read-only; mutations must not silently fall back.
        guard currentFormat != .sevenZip, currentFormat != .rar,
              currentFormat != .dmg, currentFormat != .iso,
              !Self.isTARFormat(currentFormat) else { throw ArchiveError.unsupportedFormat }
        try await editor.stage(change)
    }

    func undoChange(id: String) async -> Bool {
        await editor.undo(id: id)
    }

    func currentPendingChanges() async -> [PendingChange] {
        await editor.pendingChanges
    }

    func saveArchive() async throws -> ArchiveDocumentSnapshot {
        try Task.checkCancellation()
        guard currentFormat != .sevenZip, currentFormat != .rar,
              currentFormat != .dmg, currentFormat != .iso,
              !Self.isTARFormat(currentFormat) else { throw ArchiveError.unsupportedFormat }
        guard let currentArchiveURL else { throw ArchiveError.helperFailed }
        let accessed = currentArchiveURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { currentArchiveURL.stopAccessingSecurityScopedResource() }
        }
        let publishedURL = try await editor.save()
        return try await reopenAfterSave(at: publishedURL)
    }

    func saveArchiveAs(to targetURL: URL) async throws -> ArchiveDocumentSnapshot {
        try Task.checkCancellation()
        guard currentFormat != .sevenZip, currentFormat != .rar,
              currentFormat != .dmg, currentFormat != .iso,
              !Self.isTARFormat(currentFormat) else { throw ArchiveError.unsupportedFormat }
        let accessed = targetURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { targetURL.stopAccessingSecurityScopedResource() }
        }
        let publishedURL = try await editor.saveAs(to: targetURL)
        return try await reopenAfterSave(at: publishedURL)
    }

    private func reopenAfterSave(at publishedURL: URL) async throws -> ArchiveDocumentSnapshot {
        try resetPreviewSession()
        let accessed = publishedURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { publishedURL.stopAccessingSecurityScopedResource() }
        }
        let snapshot = try await provider.open(url: publishedURL)
        currentArchiveURL = snapshot.sourceURL
        return snapshot
    }

    private func availableExtractionURL(baseName: String, under destinationDirectoryURL: URL) throws -> URL {
        var suffix = 1
        var candidate = destinationDirectoryURL.appending(path: baseName, directoryHint: .isDirectory)
        while true {
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            } catch let error as NSError where error.code == NSFileWriteFileExistsError {
                suffix += 1
                candidate = destinationDirectoryURL.appending(
                    path: "\(baseName) \(suffix)",
                    directoryHint: .isDirectory
                )
            }
        }
    }

    private static func isTARFormat(_ format: ArchiveFormat?) -> Bool {
        switch format {
        case .tar, .gzip, .bzip2, .xz, .zstandard: return true
        default: return false
        }
    }

    private static let compoundExtensions = [
        ".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.z", ".tar.lz4",
    ]

    static func archiveBaseName(from url: URL) -> String {
        let name = url.lastPathComponent
        let lowered = name.lowercased()
        for ext in compoundExtensions where lowered.hasSuffix(ext) {
            let base = String(name.dropLast(ext.count))
            if !base.isEmpty { return base }
        }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? ArchiveExtractionCopy.defaultFolderName() : base
    }

    private func resetPreviewSession() throws {
        let root = ValidatedPreviewCacheURL.cacheRoot
        if let previewSessionURL {
            try? FileManager.default.removeItem(at: previewSessionURL)
        }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let session = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: session,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        previewSessionURL = session
        activePreviewRootURL = nil
    }
}
