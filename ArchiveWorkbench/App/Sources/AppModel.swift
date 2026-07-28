import AppKit
import ArchiveDomain
import ArchiveOperations
import ArchiveProviders
import Foundation
import Observation
import SwiftUI

extension Notification.Name {
    /// Posted when unfinished crash-recovery journals are found at launch.
    /// The `object` is `[(journalURL: URL, journal: CrashRecoveryJournal)]`.
    static let crashRecoveryJournalsFound = Notification.Name("AWBCrashRecoveryJournalsFound")
}

enum AppearanceMode: String, CaseIterable, Sendable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ArchiveViewMode: String, CaseIterable, Sendable {
    case list
    case media
}

struct ArchiveEntryMetadata: Equatable, Sendable {
    let type: String
    let size: String
    let compressedSize: String
    let modifiedDate: String
    let path: String

    var statusMessage: String {
        statusMessage(localization: AppLocalization())
    }

    func statusMessage(localization: AppLocalization) -> String {
        let summarySize = size.split(separator: " ").prefix(2).joined(separator: " ")
        return localization.format("已选择 1 项 · %@", summarySize)
    }
}

struct ArchiveFolderSummary: Equatable, Sendable, Identifiable {
    let name: String
    let itemCount: Int
    var id: String { name }
    var countText: String { countText(localization: AppLocalization()) }

    func countText(localization: AppLocalization) -> String {
        localization.format("%ld 项", itemCount)
    }
}

// MARK: - Creation Options

enum CreationFormat: String, CaseIterable, Sendable {
    case zip
    case sevenZip
    case rar
    case tarGz
    case tarXz
    case tarZst

    var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7z"
        case .rar: return "RAR"
        case .tarGz: return "TAR.GZ"
        case .tarXz: return "TAR.XZ"
        case .tarZst: return "TAR.ZST"
        }
    }

    var capabilityText: String {
        switch self {
        case .zip: return "支持加密"
        case .sevenZip: return "支持 AES-256 加密"
        case .rar: return "支持加密（需安装 RARLAB rar）"
        case .tarGz, .tarXz, .tarZst: return "支持压缩级别"
        }
    }

    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .sevenZip: return "7z"
        case .rar: return "rar"
        case .tarGz: return "tar.gz"
        case .tarXz: return "tar.xz"
        case .tarZst: return "tar.zst"
        }
    }

    var supportsEncryption: Bool {
        switch self {
        case .zip, .sevenZip, .rar: return true
        case .tarGz, .tarXz, .tarZst: return false
        }
    }

    var supportsSplit: Bool {
        switch self {
        case .zip, .sevenZip: return true
        case .rar, .tarGz, .tarXz, .tarZst: return false
        }
    }
}

enum EncryptionMethod: String, CaseIterable, Sendable {
    case aes256
    case zipCrypto

    var displayName: String {
        switch self {
        case .aes256: return "AES-256（推荐）"
        case .zipCrypto: return "ZipCrypto（旧版兼容）"
        }
    }
}

enum ZIPCompressionLevel: String, CaseIterable, Sendable {
    case store
    case deflate
    case maximum

    var displayName: String {
        switch self {
        case .store: return "最快（Store）"
        case .deflate: return "默认（Deflate）"
        case .maximum: return "最小（Maximum）"
        }
    }
}

enum SplitVolumeSize: Int, CaseIterable, Sendable {
    case mb4 = 4
    case mb10 = 10
    case mb100 = 100
    case gb1 = 1024

    var displayName: String {
        switch self {
        case .mb4: return "4 MB"
        case .mb10: return "10 MB"
        case .mb100: return "100 MB"
        case .gb1: return "1 GB"
        }
    }

    var bytes: Int64 {
        Int64(rawValue) * 1024 * 1024
    }
}

struct PreflightIssue: Identifiable, Equatable, Sendable {
    let id = UUID()
    let filename: String
    let issue: String
    let suggestion: String
}

struct ArchiveCreationDraft: Equatable, Sendable {
    var inputs: [URL]
    var outputURL: URL?

    init(inputs: [URL], outputURL: URL? = nil) {
        self.inputs = inputs
        self.outputURL = outputURL
    }

    var suggestedFilename: String {
        suggestedFilename(for: .zip)
    }

    func suggestedFilename(for format: CreationFormat) -> String {
        guard inputs.count == 1, !inputs[0].lastPathComponent.isEmpty else {
            return defaultFilename(for: format)
        }
        let name = inputs[0].lastPathComponent
        let compoundExtensions = [".tar.gz", ".tar.xz", ".tar.zst", ".tar.bz2", ".tar.z", ".tar.lz4"]
        let lower = name.lowercased()
        for ext in compoundExtensions {
            if lower.hasSuffix(ext) {
                return String(name.dropLast(ext.count)) + "." + format.fileExtension
            }
        }
        return inputs[0].deletingPathExtension().lastPathComponent + "." + format.fileExtension
    }

    private func defaultFilename(for format: CreationFormat) -> String {
        "Archive." + format.fileExtension
    }

    var canCreate: Bool { !inputs.isEmpty && outputURL != nil }
}

struct AppLocalization {
    let bundle: Bundle
    let locale: Locale

    init(bundle: Bundle = .main, locale: Locale? = nil) {
        self.bundle = bundle
        self.locale = locale ?? Locale(
            identifier: bundle.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
        )
    }

    func string(_ key: String) -> String {
        let languageCode = locale.language.languageCode?.identifier
        for localization in [locale.identifier, languageCode].compactMap({ $0 }) {
            guard let path = bundle.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: nil,
                forLocalization: localization
            ), let languageBundle = Bundle(path: URL(fileURLWithPath: path).deletingLastPathComponent().path)
            else { continue }
            return languageBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}

enum ArchiveCreationCopy {
    static func subtitle(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("选择格式与文件，创建跨平台兼容的压缩包")
    }

    static func verificationNote(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("保存前会重新打开并核对全部文件。")
    }

    static func inputPanelTitle(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("选择要归档的项目")
    }

    static func inputPanelPrompt(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("继续")
    }

    static func inputPanelMessage(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("可以选择多个文件和文件夹；创建前会检查 Windows 文件名兼容性。")
    }

    static func savePanelTitle(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("保存压缩包")
    }

    static func savePanelPrompt(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("选择")
    }

    static func savePanelMessage(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("选择保存位置和文件名；已有文件不会被静默覆盖。")
    }

    static func inputCount(
        _ count: Int,
        localization: AppLocalization = AppLocalization()
    ) -> String {
        localization.format("待归档项目 · %ld 项", count)
    }

    static func purposeLabel(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("用途")
    }

    static func formatLabel(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("格式")
    }

    static func compressionLabel(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("压缩方式")
    }

    static func encryptionLabel(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("加密")
    }

    static func noSelection(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("尚未选择")
    }
}

enum ArchiveShellCopy {
    static func openPanelTitle(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("打开压缩包")
    }

    static func openPanelPrompt(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("打开")
    }

    static func openPanelMessage(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("选择一个压缩包文件")
    }

    static func extractionPanelTitle(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("选择解压位置")
    }

    static func extractionPanelPrompt(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("解压缩到此处")
    }

    static func extractionPanelMessage(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("应用会在所选位置创建一个新文件夹，不会覆盖已有文件。")
    }

    static func addPanelTitle(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("添加文件")
    }

    static func addPanelPrompt(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("添加")
    }

    static func addPanelMessage(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("可以选择多个文件或文件夹；所选内容会添加到压缩包根目录。")
    }

    static func readyToAdd(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("已就绪，可添加文件")
    }

    static func changeStaged(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("修改已暂存，尚未保存")
    }

    static func changeUndone(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("已撤销上一步修改")
    }

    static func archiveSaved(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("已保存修改")
    }

    static func unsavedChanges(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("尚未保存")
    }

    static func readyToChooseExtractionLocation(
        localization: AppLocalization = AppLocalization()
    ) -> String {
        localization.string("已就绪，可选择解压位置")
    }
}

enum ArchiveExtractionCopy {
    static func defaultFolderName(localization: AppLocalization = AppLocalization()) -> String {
        localization.string("解压内容")
    }
}

struct MediaRecommendationPolicy: Sendable {
    func shouldRecommend(totalFiles: Int, safeMediaFiles: Int, userSelectedMode: Bool) -> Bool {
        guard !userSelectedMode, totalFiles > 0, safeMediaFiles >= 4 else { return false }
        return Double(safeMediaFiles) / Double(totalFiles) >= 0.70
    }
}

/// A prebuilt search index for large archives (>1000 entries).
/// Maps lowercased path components and file names to entry IDs for fast lookup.
struct ArchiveSearchIndex: Sendable {
    /// Precomputed lowercased full paths keyed by entry ID.
    private let lowercasedPaths: [ArchiveEntryID: String]
    /// Precomputed lowercased file names (last path component) keyed by entry ID.
    private let lowercasedNames: [ArchiveEntryID: String]
    /// All entry IDs in insertion order.
    let entryIDs: [ArchiveEntryID]

    init(entries: [ArchiveEntry]) {
        var paths: [ArchiveEntryID: String] = [:]
        var names: [ArchiveEntryID: String] = [:]
        var ids: [ArchiveEntryID] = []
        ids.reserveCapacity(entries.count)
        for entry in entries {
            ids.append(entry.id)
            paths[entry.id] = entry.displayPath.lowercased()
            let name = entry.displayPath.split(separator: "/").last.map(String.init) ?? entry.displayPath
            names[entry.id] = name.lowercased()
        }
        lowercasedPaths = paths
        lowercasedNames = names
        entryIDs = ids
    }

    /// Returns entry IDs whose full path or file name contains the query (case-insensitive).
    func search(query: String) -> Set<ArchiveEntryID> {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return [] }
        var results = Set<ArchiveEntryID>()
        for id in entryIDs {
            if let path = lowercasedPaths[id], path.contains(normalizedQuery) {
                results.insert(id)
                continue
            }
            if let name = lowercasedNames[id], name.contains(normalizedQuery) {
                results.insert(id)
            }
        }
        return results
    }
}

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let loader: any ArchiveDocumentLoading
    @ObservationIgnored private let localization: AppLocalization
    /// Runtime-discovered capabilities; 7z is gated on a validated 7zz binary.
    @ObservationIgnored private var activeRegistry = ArchiveCapabilityRegistry.productionBaseline
    var hasDocument = false
    var isLoading = false
    var presentedError: String?
    var formatMismatchWarning: String?
    var documentTitle = ""
    var documentItemCount = 0
    var archiveFormatName = "—"
    var canAdd = false
    var canRemoveSelectedEntry: Bool { hasDocument && selectedEntryID != nil && !isNestedSession && canAdd }
    var canRenameSelectedEntry: Bool { hasDocument && selectedEntryID != nil && !isNestedSession && canAdd }
    var canReplaceSelectedEntry: Bool { hasDocument && selectedEntryID != nil && !isNestedSession && canAdd }
    var canExtract = false
    var canTestIntegrity = false
    var viewMode: ArchiveViewMode = .list
    var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }
    var inspectorVisible = true
    /// Sidebar column visibility, driven by Cmd+0 and the View menu.
    var sidebarVisible = true
    var compactToolbar = true
    var searchText = "" {
        didSet { scheduleSearchDebounce() }
    }
    /// The debounced search query actually used for filtering.
    var activeSearchText = ""
    /// Number of results from the last search (nil when search is empty).
    var searchResultCount: Int?
    var selectedEntryID: ArchiveEntryID? {
        didSet { transientStatusMessage = nil }
    }
    var entries: [ArchiveEntry] = [] {
        didSet { cachedHasHierarchy = entries.contains { $0.displayPath.contains("/") } }
    }
    @ObservationIgnored private var cachedHasHierarchy = false
    var currentDirectory = ""
    var folderSummaries: [ArchiveFolderSummary] = []
    var scrollAnchor: ArchiveEntryID?
    var pendingChanges: [PendingChange] = []
    var hasUnsavedChanges: Bool { !pendingChanges.isEmpty }
    var transientStatusMessage: String?
    var metadataByEntryID: [ArchiveEntryID: ArchiveEntryMetadata] = [:]
    var selectedMetadata: ArchiveEntryMetadata? {
        selectedEntryID.flatMap { metadataByEntryID[$0] }
    }
    var statusMessage: String {
        get {
            if !activeSearchText.isEmpty {
                return localization.format("找到 %ld 个项目", visibleEntries.count)
            }
            return transientStatusMessage
                ?? selectedMetadata?.statusMessage(localization: localization)
                ?? localization.string("未选择项目")
        }
        set { transientStatusMessage = newValue }
    }
    var visibleEntries: [ArchiveEntry] {
        guard activeSearchText.isEmpty else {
            if let index = searchIndex {
                let matchedIDs = index.search(query: activeSearchText)
                return entries.filter { matchedIDs.contains($0.id) }
            }
            return entries.filter {
                $0.displayPath.localizedStandardContains(activeSearchText)
            }
        }
        if !cachedHasHierarchy || currentDirectory.isEmpty {
            return entries
        } else if currentDirectory == localization.string("压缩包根目录") {
            return entries.filter { !$0.displayPath.contains("/") }
        } else {
            let prefix = currentDirectory + "/"
            return entries.filter {
                $0.displayPath.hasPrefix(prefix) && $0.displayPath != prefix
            }
        }
    }
    var operationMessage = "当前没有进行中的操作"
    var isCreating = false
    var creationProgress = 0.0
    var lastCreatedURL: URL?
    var creationErrorMessage: String?
    // MARK: - Creation Panel Options
    var creationFormat: CreationFormat = .zip
    var creationEncryptionEnabled = false {
        didSet {
            if creationEncryptionEnabled && !oldValue && !LicenseGate.isProLicensed {
                creationEncryptionEnabled = false
                DispatchQueue.main.async {
                    _ = LicenseGate.requirePro(for: .encrypt)
                }
            }
        }
    }
    var creationPassword = ""
    var creationPasswordConfirm = ""
    var creationEncryptionMethod: EncryptionMethod = .aes256
    var creationSplitEnabled = false
    var creationVolumeSize: SplitVolumeSize = .mb4
    var creationCompressionLevel: ZIPCompressionLevel = .deflate
    var creationTARCompressionLevel: Double = 6
    var preflightIssues: [PreflightIssue] = []
    var isExtracting = false
    var extractionProgress = 0.0
    var lastExtractionURL: URL?
    var extractionErrorMessage: String?
    /// Structured error presentation for the inline banner.
    var activeErrorPresentation: ArchiveErrorPresentation?
    /// Password retry state for wrong-password errors.
    var passwordRetryText = ""
    var passwordAttemptCount = 0
    /// Conflict resolution state during extraction.
    var activeConflict: ExtractionConflictInfo?
    /// Whether "extract selected" is available (requires a selection).
    var canExtractSelected: Bool { hasDocument && selectedEntryID != nil && canExtract && !isExtracting }
    @ObservationIgnored private var conflictContinuation: CheckedContinuation<ExtractionConflictResolution, Never>?
    @ObservationIgnored private var conflictBatchResolution: ExtractionConflictResolution?
    @ObservationIgnored private var errorAutoDismissTask: Task<Void, Never>?
    var previewCacheURL: ValidatedPreviewCacheURL?
    var previewCacheEntryID: ArchiveEntryID?
    var isPreviewLoading = false
    var previewErrorMessage: String?
    @ObservationIgnored private var usesFixturePreview = false
    @ObservationIgnored private var previewRequestID = UUID()
    @ObservationIgnored private var encryptedEntryIDs: Set<ArchiveEntryID> = []
    @ObservationIgnored private var extractionTask: Task<Void, Never>?
    @ObservationIgnored private var creationTask: Task<Void, Never>?
    /// Tracks the asynchronous parent-archive re-open started by navigateBack so
    /// rapid back navigation or a new top-level open can cancel a stale re-open.
    @ObservationIgnored private var navigationReopenTask: Task<Void, Never>?
    @ObservationIgnored private var heldAddSourceScopes: [URL] = []
    /// Search index for large archives; nil for <1000 entries.
    @ObservationIgnored private var searchIndex: ArchiveSearchIndex?
    /// Debounce task for search input.
    @ObservationIgnored private var searchDebounceTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var crashRecoveryObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var preflightStagingDir: URL?
    var selectedPreviewCacheURL: ValidatedPreviewCacheURL? {
        previewCacheEntryID == selectedEntryID ? previewCacheURL : nil
    }
    var capabilitySnapshot = ArchiveCapabilitySnapshot(
        actions: [],
        primaryProvider: nil,
        unavailableReasons: [:]
    )
    var canCancelExtraction: Bool { extractionTask != nil && isExtracting }
    var canCancelCreation: Bool { creationTask != nil && isCreating }

    // MARK: - Nested Archive Sub-Sessions

    /// Stack of parent session snapshots. The last element is the immediate parent.
    @ObservationIgnored private var sessionStack: [ArchiveSessionSnapshot] = []
    /// Materialized URLs for nested sessions that need cleanup on pop.
    @ObservationIgnored private var nestedMaterializedURLs: [URL] = []
    /// Whether the current session is a nested sub-session (read-only).
    var isNestedSession = false
    /// Current nesting depth (0 = root archive).
    var nestedDepth: Int { sessionStack.count }
    /// Whether back navigation is available.
    var canNavigateBack: Bool { !sessionStack.isEmpty }
    /// Entry IDs that are themselves archives (for badge display).
    var nestedArchiveEntryIDs: Set<ArchiveEntryID> = []

    /// Breadcrumb path for UI display: root archive > inner.zip > deep.7z
    var breadcrumbSegments: [BreadcrumbSegment] {
        var segments: [BreadcrumbSegment] = []
        for (index, snapshot) in sessionStack.enumerated() {
            segments.append(BreadcrumbSegment(id: index, title: snapshot.documentTitle))
        }
        segments.append(BreadcrumbSegment(id: sessionStack.count, title: documentTitle))
        return segments
    }

    // MARK: - Crash Recovery

    /// Journals found at launch that need user decision (recover or discard).
    var pendingRecoveryJournals: [CrashRecoveryJournal] = []
    /// Whether the recovery alert should be presented.
    var isRecoveryAlertPresented = false

    init(
        loader: any ArchiveDocumentLoading = ArchiveDocumentLoader(),
        localization: AppLocalization = AppLocalization()
    ) {
        self.loader = loader
        self.localization = localization
        operationMessage = localization.string("当前没有进行中的操作")
        observeCrashRecoveryJournals()
    }

    deinit {
        if let observer = crashRecoveryObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func openArchive(url: URL, password: String? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        presentedError = nil
        defer { isLoading = false }
        if let creationTask {
            creationTask.cancel()
            await creationTask.value
            self.creationTask = nil
        }
        resetCreationState()
        if let extractionTask {
            conflictContinuation?.resume(returning: .skip)
            conflictContinuation = nil
            activeConflict = nil
            extractionTask.cancel()
            await extractionTask.value
            self.extractionTask = nil
        }
        resetExtractionState()
        // Reset nested session stack when opening a new top-level archive
        navigationReopenTask?.cancel()
        navigationReopenTask = nil
        sessionStack.removeAll()
        for nestedURL in nestedMaterializedURLs {
            try? FileManager.default.removeItem(at: nestedURL)
        }
        nestedMaterializedURLs.removeAll()
        isNestedSession = false
        do {
            try Task.checkCancellation()
            let snapshot: ArchiveDocumentSnapshot
            if let password, !password.isEmpty {
                snapshot = try await loader.openWithPassword(url: url, password: password)
            } else {
                snapshot = try await loader.open(url: url)
            }
            try Task.checkCancellation()
            activeRegistry = await loader.capabilityRegistry
            apply(snapshot)
            // Surface format mismatch warning
            let detection = await loader.lastDetectionResult
            if let detection, detection.hasMismatch,
               let detected = detection.detectedFormat, let ext = detection.extensionFormat {
                let warning = localization.format(
                    "文件内容实际为 %@ 格式，但扩展名为 .%@。已按实际格式打开。",
                    detected.rawValue.uppercased(),
                    ext.rawValue
                )
                formatMismatchWarning = warning
                transientStatusMessage = warning
            } else {
                formatMismatchWarning = nil
            }
        } catch is CancellationError {
            return
        } catch {
            clearDocument()
            if let archiveError = error as? ArchiveError,
               archiveError == .passwordRequired || archiveError == .wrongPassword {
                currentSourceURL = url
                passwordAttemptCount = 0
                presentError(.wrongPassword)
            } else {
                presentedError = userMessage(for: error)
            }
        }
    }

    func stageChange(_ change: PendingChange) async {
        guard LicenseGate.requirePro(for: .edit) else { return }
        presentedError = nil
        do {
            try await loader.stageChange(change)
            pendingChanges = await loader.currentPendingChanges()
            transientStatusMessage = ArchiveShellCopy.changeStaged()
        } catch {
            presentedError = userMessage(for: error)
        }
    }

    /// Stages files and folders chosen through the "添加" file picker.
    ///
    /// Each chosen file becomes a single `PendingChange.add` at the archive
    /// root. Each chosen folder is expanded recursively so that every regular
    /// file beneath it is added at a path relative to the archive root
    /// (`<folderName>/<subpath>`). Security-scoped access for every chosen
    /// source URL is held until the next save so the editor can still read the
    /// bytes when it publishes the archive.
    func stageAdditions(from urls: [URL]) async {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard hasDocument, canAdd, !urls.isEmpty else { return }
        presentedError = nil
        var changes: [PendingChange] = []
        var scopesToHold: [URL] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            if accessed { scopesToHold.append(url) }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            guard exists else { continue }
            if isDirectory.boolValue {
                appendFolderAdditions(for: url, to: &changes)
            } else {
                changes.append(.add(sourceURL: url, destinationPath: url.lastPathComponent))
            }
        }
        guard !changes.isEmpty else {
            for url in scopesToHold { url.stopAccessingSecurityScopedResource() }
            transientStatusMessage = localization.string("没有可添加的文件。")
            return
        }
        heldAddSourceScopes.append(contentsOf: scopesToHold)
        await stageChanges(changes)
    }

    /// Stages a removal for the currently selected entry.
    func removeSelectedEntry() async {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard hasDocument, !isNestedSession, let selectedEntryID,
              let entry = entries.first(where: { $0.id == selectedEntryID }) else { return }
        let entryPath = entry.displayPath.hasSuffix("/")
            ? String(entry.displayPath.dropLast())
            : entry.displayPath
        await stageChange(.remove(entryPath: entryPath))
    }

    /// Validates and stages a rename for the currently selected entry.
    func renameSelectedEntry(to newName: String) async {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard hasDocument, !isNestedSession, let selectedEntryID,
              let entry = entries.first(where: { $0.id == selectedEntryID }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let invalidCharacters = CharacterSet(charactersIn: "/:\\<>|?*\"")
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: invalidCharacters) == nil else {
            transientStatusMessage = localization.string("名称无效，不能包含路径分隔符或特殊字符。")
            return
        }
        let currentPath = entry.displayPath.hasSuffix("/")
            ? String(entry.displayPath.dropLast())
            : entry.displayPath
        let parentPrefix: String
        if let lastSlash = currentPath.lastIndex(of: "/") {
            parentPrefix = String(currentPath[currentPath.startIndex...lastSlash])
        } else {
            parentPrefix = ""
        }
        let newPath = parentPrefix + trimmed
        guard newPath != currentPath else { return }
        let collides = entries.contains { other in
            let otherPath = other.displayPath.hasSuffix("/")
                ? String(other.displayPath.dropLast())
                : other.displayPath
            return otherPath.caseInsensitiveCompare(newPath) == .orderedSame
        }
        guard !collides else {
            transientStatusMessage = localization.string("已存在同名项目，无法重命名。")
            return
        }
        await stageChange(.rename(from: currentPath, to: newPath))
    }

    /// Validates and stages a replacement for the currently selected entry.
    func replaceSelectedEntry(with sourceURL: URL) async {
        guard LicenseGate.requirePro(for: .edit) else { return }
        guard hasDocument, let selectedEntryID,
              let entry = entries.first(where: { $0.id == selectedEntryID }) else { return }
        let entryPath = entry.displayPath.hasSuffix("/")
            ? String(entry.displayPath.dropLast())
            : entry.displayPath
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        if accessed { heldAddSourceScopes.append(sourceURL) }
        await stageChange(.replace(entryPath: entryPath, sourceURL: sourceURL))
    }

    /// Returns the current file name (last path component) of the selected entry.
    var selectedEntryFileName: String? {
        guard let selectedEntryID,
              let entry = entries.first(where: { $0.id == selectedEntryID }) else { return nil }
        let path = entry.displayPath.hasSuffix("/")
            ? String(entry.displayPath.dropLast())
            : entry.displayPath
        return path.split(separator: "/").last.map(String.init) ?? path
    }

    private func stageChanges(_ changes: [PendingChange]) async {
        guard !changes.isEmpty else { return }
        presentedError = nil
        do {
            for change in changes {
                try await loader.stageChange(change)
            }
            pendingChanges = await loader.currentPendingChanges()
            transientStatusMessage = ArchiveShellCopy.changeStaged()
        } catch {
            pendingChanges = await loader.currentPendingChanges()
            presentedError = userMessage(for: error)
        }
    }

    private func appendFolderAdditions(for folderURL: URL, to changes: inout [PendingChange]) {
        let folderName = folderURL.lastPathComponent
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let baseComponentCount = folderURL.pathComponents.count
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            let relativeComponents = fileURL.pathComponents.dropFirst(baseComponentCount)
            guard !relativeComponents.isEmpty else { continue }
            let destinationPath = (folderName + "/" + relativeComponents.joined(separator: "/"))
            changes.append(.add(sourceURL: fileURL, destinationPath: destinationPath))
        }
    }

    private func releaseHeldAddSourceScopes() {
        for url in heldAddSourceScopes { url.stopAccessingSecurityScopedResource() }
        heldAddSourceScopes.removeAll()
    }

    func undoLastChange() async {
        guard let last = pendingChanges.last else { return }
        let undone = await loader.undoChange(id: last.id)
        pendingChanges = await loader.currentPendingChanges()
        if undone {
            transientStatusMessage = ArchiveShellCopy.changeUndone()
        } else {
            transientStatusMessage = localization.string("撤销失败，修改仍然存在。")
        }
    }

    @discardableResult
    func saveArchive() async -> Bool {
        presentedError = nil
        guard hasUnsavedChanges else { return true }
        do {
            let snapshot = try await loader.saveArchive()
            apply(snapshot)
            transientStatusMessage = ArchiveShellCopy.archiveSaved()
            return true
        } catch {
            presentedError = userMessage(for: error)
            return false
        }
    }

    func saveArchiveAs(to targetURL: URL) async {
        presentedError = nil
        guard hasDocument, let sourceURL = currentSourceURL else { return }
        do {
            if hasUnsavedChanges {
                let snapshot = try await loader.saveArchiveAs(to: targetURL)
                apply(snapshot)
            } else {
                let directory = targetURL.deletingLastPathComponent()
                let tempURL = directory.appending(
                    path: "." + targetURL.lastPathComponent + ".copy-" + UUID().uuidString
                )
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                let syncFD = tempURL.withUnsafeFileSystemRepresentation { path -> Int32 in
                    guard let path else { return -1 }
                    return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                }
                if syncFD >= 0 {
                    Darwin.fsync(syncFD)
                    Darwin.close(syncFD)
                }
                let renameResult = tempURL.withUnsafeFileSystemRepresentation { tempPath in
                    targetURL.withUnsafeFileSystemRepresentation { targetPath in
                        guard let tempPath, let targetPath else { return Int32(-1) }
                        return Darwin.rename(tempPath, targetPath)
                    }
                }
                guard renameResult == 0 else {
                    try? FileManager.default.removeItem(at: tempURL)
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                let dirFD = directory.withUnsafeFileSystemRepresentation { path -> Int32 in
                    guard let path else { return -1 }
                    return Darwin.open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                if dirFD >= 0 {
                    Darwin.fsync(dirFD)
                    Darwin.close(dirFD)
                }
            }
            transientStatusMessage = ArchiveShellCopy.archiveSaved()
        } catch {
            presentedError = userMessage(for: error)
        }
    }

    func loadSelectedPreview() async {
        guard !usesFixturePreview else { return }
        let requestID = UUID()
        previewRequestID = requestID
        previewCacheURL = nil
        previewCacheEntryID = nil
        previewErrorMessage = nil
        guard let selectedEntryID,
              let entry = entries.first(where: { $0.id == selectedEntryID }),
              PreviewRoutingPolicy().kind(forFilename: entry.displayPath) != .unsupported else {
            isPreviewLoading = false
            return
        }
        if encryptedEntryIDs.contains(selectedEntryID) {
            previewErrorMessage = localization.string("这个文件需要压缩包密码才能预览。")
            isPreviewLoading = false
            return
        }
        isPreviewLoading = true
        defer {
            if previewRequestID == requestID { isPreviewLoading = false }
        }
        do {
            try Task.checkCancellation()
            let materializedURL = try await loader.materializePreview(entryID: selectedEntryID)
            try Task.checkCancellation()
            guard previewRequestID == requestID, self.selectedEntryID == selectedEntryID else { return }
            guard let validated = ValidatedPreviewCacheURL(candidateURL: materializedURL) else {
                previewErrorMessage = localization.string("无法安全预览这个文件。")
                return
            }
            previewCacheURL = validated
            previewCacheEntryID = selectedEntryID
        } catch is CancellationError {
            return
        } catch {
            guard previewRequestID == requestID, self.selectedEntryID == selectedEntryID else { return }
            previewErrorMessage = previewMessage(for: error)
        }
    }

    func extractAll(to destinationDirectoryURL: URL) async {
        guard hasDocument, !isExtracting else { return }
        isExtracting = true
        extractionProgress = 0
        extractionErrorMessage = nil
        lastExtractionURL = nil
        operationMessage = localization.string("正在准备解压缩…")
        defer { isExtracting = false }
        do {
            let outputURL = try await loader.extractAll(to: destinationDirectoryURL) { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.extractionProgress < 1 else { return }
                    self.extractionProgress = self.extractionFraction(progress)
                    self.operationMessage = self.localization.format(
                        "正在解压缩 · %ld/%ld 项",
                        progress.completedEntries,
                        progress.totalEntries
                    )
                }
            }
            try Task.checkCancellation()
            extractionProgress = 1
            lastExtractionURL = outputURL
            Self.setQuarantineRecursively(on: outputURL)
            statusMessage = localization.format("解压缩完成：%@", outputURL.lastPathComponent)
            operationMessage = localization.string("解压缩完成")
        } catch is CancellationError {
            presentError(.cancelled)
            statusMessage = localization.string("已取消解压缩")
            operationMessage = localization.string("当前没有进行中的操作")
        } catch {
            let presentation = errorPresentation(for: error)
            presentError(presentation)
            operationMessage = localization.string("解压缩失败")
        }
    }

    func startExtraction(to destinationDirectoryURL: URL) {
        guard LicenseGate.requirePro(for: .extract) else { return }
        guard extractionTask == nil, hasDocument else { return }
        extractionTask = Task { [weak self] in
            guard let self else { return }
            await self.extractAll(to: destinationDirectoryURL)
            self.extractionTask = nil
        }
    }

    func awaitExtractionCompletion() async {
        guard let task = extractionTask else { return }
        await task.value
    }

    func cancelExtraction() {
        if let continuation = conflictContinuation {
            continuation.resume(returning: .skip)
            conflictContinuation = nil
            activeConflict = nil
        }
        extractionTask?.cancel()
    }

    // MARK: - Error Presentation

    /// Presents a structured error in the inline banner.
    func presentError(_ presentation: ArchiveErrorPresentation) {
        errorAutoDismissTask?.cancel()
        activeErrorPresentation = presentation
        if presentation.autoDismisses {
            errorAutoDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.activeErrorPresentation = nil
            }
        }
    }

    /// Dismisses the active error banner.
    func dismissError() {
        errorAutoDismissTask?.cancel()
        activeErrorPresentation = nil
    }

    /// Handles the recovery action for the current error presentation.
    func performErrorRecoveryAction() {
        guard let presentation = activeErrorPresentation else { return }
        switch presentation {
        case .missingVolume:
            // Open Finder to the archive's directory so user can locate volumes
            if let sourceURL = currentSourceURL {
                NSWorkspace.shared.activateFileViewerSelecting([sourceURL])
            }
        default:
            break
        }
    }

    /// Retries opening the archive with a new password after wrong-password error.
    func retryWithPassword(_ password: String) {
        passwordAttemptCount += 1
        let attempt = passwordAttemptCount
        guard attempt < 3 else {
            // After 3 failures, the banner shows "密码错误次数过多"
            return
        }
        guard let sourceURL = currentSourceURL else { return }
        dismissError()
        Task {
            await openArchive(url: sourceURL, password: password)
            // openArchive resets passwordAttemptCount via resetExtractionState().
            // On a successful open that is correct (fresh start); on a failed
            // password attempt restore the count so the 3-attempt lockout works.
            if !hasDocument {
                passwordAttemptCount = attempt
            }
        }
    }

    // MARK: - Conflict Resolution

    /// Reads the user's conflict strategy from Settings.
    var conflictStrategy: String {
        UserDefaults.standard.string(forKey: "settings.extraction.conflictStrategy") ?? "ask"
    }

    /// Resolves a file conflict. Called by the conflict dialog UI.
    func resolveConflict(_ resolution: ExtractionConflictResolution) {
        activeConflict = nil
        switch resolution {
        case .replaceAll:
            conflictBatchResolution = .replace
        case .skipAll:
            conflictBatchResolution = .skip
        default:
            break
        }
        conflictContinuation?.resume(returning: resolution)
        conflictContinuation = nil
    }

    /// Checks whether a file at the destination conflicts and handles according to strategy.
    /// Returns true if the file should be written (replaced), false if skipped.
    func shouldOverwriteFile(at destinationURL: URL, entryPath: String) async -> Bool {
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            return true
        }
        // If a batch resolution is active, use it
        if let batch = conflictBatchResolution {
            return batch == .replace
        }
        switch conflictStrategy {
        case "overwrite":
            return true
        case "skip":
            return false
        default:
            // "ask" - pause and show conflict dialog
            activeConflict = ExtractionConflictInfo(filePath: entryPath)
            let resolution: ExtractionConflictResolution = await withCheckedContinuation { continuation in
                conflictContinuation = continuation
            }
            switch resolution {
            case .replace, .replaceAll:
                return true
            case .skip, .skipAll:
                return false
            }
        }
    }

    // MARK: - Extract Selected

    /// Extracts only the currently selected entry (file or folder) to a destination.
    func extractSelected(to destinationDirectoryURL: URL) async {
        guard hasDocument, let selectedEntryID,
              entries.contains(where: { $0.id == selectedEntryID }),
              !isExtracting else { return }
        isExtracting = true
        extractionProgress = 0
        extractionErrorMessage = nil
        activeErrorPresentation = nil
        lastExtractionURL = nil
        operationMessage = localization.string("正在准备解压缩…")
        defer { isExtracting = false }
        do {
            let stagingDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacUnzip_extract_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stagingDir) }

            operationMessage = localization.string("正在解压缩…")
            let materializedURL = try await loader.materializeEntryForExtraction(
                entryID: selectedEntryID,
                under: stagingDir
            )
            try Task.checkCancellation()

            var destURL = destinationDirectoryURL.appending(path: materializedURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destURL.path) {
                let baseName = destURL.deletingPathExtension().lastPathComponent
                let ext = destURL.pathExtension
                var counter = 2
                while FileManager.default.fileExists(atPath: destURL.path) {
                    let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
                    destURL = destinationDirectoryURL.appending(path: newName)
                    counter += 1
                }
            }
            try FileManager.default.copyItem(at: materializedURL, to: destURL)
            Self.setQuarantineRecursively(on: destURL)

            extractionProgress = 1
            lastExtractionURL = destURL
            statusMessage = localization.format("解压缩完成：%@", destURL.lastPathComponent)
            operationMessage = localization.string("解压缩完成")
        } catch is CancellationError {
            presentError(.cancelled)
            statusMessage = localization.string("已取消解压缩")
            operationMessage = localization.string("当前没有进行中的操作")
        } catch {
            let presentation = errorPresentation(for: error)
            presentError(presentation)
            operationMessage = localization.string("解压缩失败")
        }
    }

    /// Starts extraction of the selected entry in a background task.
    func startExtractSelected(to destinationDirectoryURL: URL) {
        guard LicenseGate.requirePro(for: .extract) else { return }
        guard extractionTask == nil, hasDocument, selectedEntryID != nil else { return }
        extractionTask = Task { [weak self] in
            guard let self else { return }
            await self.extractSelected(to: destinationDirectoryURL)
            self.extractionTask = nil
        }
    }

    /// Maps an error to a structured ArchiveErrorPresentation.
    private func errorPresentation(for error: Error) -> ArchiveErrorPresentation {
        guard let archiveError = error as? ArchiveError else {
            return .generic(localization.string("无法完成解压缩，未生成任何文件。"))
        }
        switch archiveError {
        case .missingVolume:
            return .missingVolume(needed: localization.string("其他分卷"))
        case .wrongPassword, .passwordRequired:
            return .wrongPassword
        case .unsupportedEncryption:
            return .unsupportedEncryption
        case .corruptedArchive:
            return .corruptedArchive
        default:
            return .generic(extractionMessage(for: error))
        }
    }

    func createWindowsZIP(at outputURL: URL, inputs: [URL]) async {
        guard LicenseGate.requirePro(for: .create) else { return }
        guard !inputs.isEmpty, !isCreating, !isExtracting else { return }
        isCreating = true
        creationProgress = 0
        creationErrorMessage = nil
        lastCreatedURL = nil
        operationMessage = localization.string("正在准备创建归档…")
        let (stream, continuation) = AsyncStream.makeStream(
            of: WindowsZIPCreationProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let progressTask = Task { @MainActor [weak self] in
            for await progress in stream {
                guard let self else { return }
                let fraction: Double
                if progress.totalBytes > 0 {
                    fraction = Double(progress.completedBytes) / Double(progress.totalBytes)
                } else if progress.totalEntries > 0 {
                    fraction = Double(progress.completedEntries) / Double(progress.totalEntries)
                } else {
                    fraction = 0
                }
                self.creationProgress = min(max(fraction, 0), 1)
                self.operationMessage = self.localization.format(
                    "正在创建 · %ld/%ld 项",
                    progress.completedEntries,
                    progress.totalEntries
                )
            }
        }
        defer { isCreating = false }
        do {
            let snapshot = try await loader.createWindowsZIP(
                at: outputURL,
                inputs: inputs,
                compressLevel: 6,
                password: nil,
                encryptMethod: 0
            ) { progress in
                continuation.yield(progress)
            }
            continuation.finish()
            await progressTask.value
            try Task.checkCancellation()
            apply(snapshot)
            creationProgress = 1
            lastCreatedURL = outputURL
            statusMessage = localization.format("创建完成：%@", outputURL.lastPathComponent)
            operationMessage = localization.string("创建完成")
        } catch is CancellationError {
            continuation.finish()
            progressTask.cancel()
            await progressTask.value
            statusMessage = localization.string("已取消创建归档")
            operationMessage = localization.string("当前没有进行中的操作")
        } catch {
            continuation.finish()
            progressTask.cancel()
            await progressTask.value
            creationErrorMessage = creationMessage(for: error)
            operationMessage = localization.string("创建失败")
        }
    }

    func startCreation(at outputURL: URL, inputs: [URL]) {
        guard LicenseGate.requirePro(for: .create) else { return }
        guard creationTask == nil, !inputs.isEmpty else { return }
        let format = creationFormat
        let password = (creationEncryptionEnabled && format.supportsEncryption) ? creationPassword : nil
        let encryptionMethod = (creationEncryptionEnabled && format.supportsEncryption) ? creationEncryptionMethod : nil
        let splitEnabled = creationSplitEnabled && format.supportsSplit
        let volumeSize = splitEnabled ? creationVolumeSize : nil
        let zipLevel = creationCompressionLevel
        let tarLevel = Int(creationTARCompressionLevel)
        creationPassword = ""
        creationPasswordConfirm = ""
        creationTask = Task { [weak self] in
            guard let self else { return }
            await self.createArchiveWithOptions(
                at: outputURL,
                inputs: inputs,
                format: format,
                password: password,
                encryptionMethod: encryptionMethod,
                splitVolumeSize: volumeSize,
                zipCompressionLevel: zipLevel,
                tarCompressionLevel: tarLevel
            )
            self.creationTask = nil
        }
    }

    /// Computes total size of all input files/folders for split estimation.
    func totalInputSize(for inputs: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in inputs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let fileURL as URL in enumerator {
                    let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if values?.isRegularFile == true {
                        total += Int64(values?.fileSize ?? 0)
                    }
                }
            } else {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Runs Windows filename preflight checks and populates preflightIssues.
    func runPreflight(inputs: [URL]) async {
        // Collect all relative paths on MainActor (DirectoryEnumerator is not Sendable)
        var pathsToCheck: [String] = []
        for url in inputs {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                pathsToCheck.append(url.lastPathComponent)
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                let prefix = url.standardizedFileURL.path + "/"
                for item in enumerator.allObjects {
                    guard let fileURL = item as? URL else { continue }
                    pathsToCheck.append(String(fileURL.standardizedFileURL.path.dropFirst(prefix.count)))
                }
            } else {
                pathsToCheck.append(url.lastPathComponent)
            }
        }
        let issues: [PreflightIssue] = await Task.detached(priority: .userInitiated) {
            var found: [PreflightIssue] = []
            let forbidden = CharacterSet(charactersIn: "<>:\"|?*")
            let reserved = Set(["CON", "PRN", "AUX", "NUL"])
            let reservedDevicePrefixes = ["COM", "LPT"]

            for path in pathsToCheck {
                let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
                for component in components {
                    let upperStem = component.split(separator: ".", maxSplits: 1).first
                        .map(String.init)?.uppercased() ?? ""
                    if reserved.contains(upperStem) {
                        found.append(PreflightIssue(filename: component, issue: "Windows 保留名称", suggestion: "重命名为其他名称"))
                        continue
                    }
                    let isNumberedDevice = reservedDevicePrefixes.contains { prefix in
                        upperStem.hasPrefix(prefix) && upperStem.count == 4
                            && upperStem.last?.isNumber == true
                    }
                    if isNumberedDevice {
                        found.append(PreflightIssue(filename: component, issue: "Windows 设备名称", suggestion: "重命名为其他名称"))
                        continue
                    }
                    if component.unicodeScalars.contains(where: { forbidden.contains($0) || $0.value < 0x20 }) {
                        found.append(PreflightIssue(filename: component, issue: "包含非法字符", suggestion: "移除 < > : \" | ? * 等字符"))
                        continue
                    }
                    if component.hasSuffix(".") || component.hasSuffix(" ") {
                        found.append(PreflightIssue(filename: component, issue: "不能以点或空格结尾", suggestion: "移除末尾的点或空格"))
                        continue
                    }
                    if component.utf16.count > 255 {
                        found.append(PreflightIssue(filename: String(component.prefix(30)) + "…", issue: "文件名过长", suggestion: "缩短文件名至 255 字符以内"))
                    }
                }
            }
            return found
        }.value
        preflightIssues = issues
    }

    func fixPreflightIssues(inputs: [URL]) async -> [URL] {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacUnzip_preflight_\(UUID().uuidString)", isDirectory: true)
        let sanitizedURLs: [URL] = await Task.detached(priority: .userInitiated) {
            let forbidden = CharacterSet(charactersIn: "<>:\"|?*")
            let reserved = Set(["CON", "PRN", "AUX", "NUL"])
            let reservedDevicePrefixes = ["COM", "LPT"]

            func sanitize(_ name: String) -> String? {
                var result = String(name.unicodeScalars.filter {
                    !forbidden.contains($0) && $0.value >= 0x20
                })
                while result.hasSuffix(".") || result.hasSuffix(" ") {
                    result = String(result.dropLast())
                }
                let stem = result.split(separator: ".", maxSplits: 1).first.map(String.init)?.uppercased() ?? ""
                if reserved.contains(stem) || reservedDevicePrefixes.contains(where: { stem.hasPrefix($0) && stem.count == 4 }) {
                    result = "_" + result
                }
                if result.utf16.count > 255 {
                    let ext = URL(fileURLWithPath: result).pathExtension
                    let base = String(result.prefix(255 - ext.count - 1))
                    result = ext.isEmpty ? base : "\(base).\(ext)"
                }
                return result == name ? nil : result
            }

            func fixDirectoryNames(_ dirURL: URL) {
                guard let enumerator = FileManager.default.enumerator(
                    at: dirURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { return }
                var renames: [(URL, URL)] = []
                for item in enumerator.allObjects {
                    guard let fileURL = item as? URL else { continue }
                    let name = fileURL.lastPathComponent
                    guard let fixed = sanitize(name) else { continue }
                    let dest = fileURL.deletingLastPathComponent().appendingPathComponent(fixed)
                    renames.append((fileURL, dest))
                }
                for (src, dst) in renames.reversed() {
                    try? FileManager.default.moveItem(at: src, to: dst)
                }
            }

            try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: stagingDir.path) else {
                return inputs
            }
            var results: [URL] = []

            for url in inputs {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    results.append(url)
                    continue
                }
                if isDirectory.boolValue {
                    let dirName = sanitize(url.lastPathComponent) ?? url.lastPathComponent
                    let destDir = stagingDir.appendingPathComponent(dirName, isDirectory: true)
                    do {
                        try FileManager.default.copyItem(at: url, to: destDir)
                        fixDirectoryNames(destDir)
                        results.append(destDir)
                    } catch {
                        results.append(url)
                    }
                } else if let fixed = sanitize(url.lastPathComponent) {
                    let dest = stagingDir.appendingPathComponent(fixed)
                    do {
                        try FileManager.default.copyItem(at: url, to: dest)
                        results.append(dest)
                    } catch {
                        results.append(url)
                    }
                } else {
                    results.append(url)
                }
            }
            return results
        }.value
        preflightStagingDir = stagingDir
        preflightIssues = []
        return sanitizedURLs
    }

    private func createArchiveWithOptions(
        at outputURL: URL,
        inputs: [URL],
        format: CreationFormat,
        password: String?,
        encryptionMethod: EncryptionMethod?,
        splitVolumeSize: SplitVolumeSize?,
        zipCompressionLevel: ZIPCompressionLevel,
        tarCompressionLevel: Int
    ) async {
        guard LicenseGate.requirePro(for: .create) else { return }
        guard !inputs.isEmpty, !isCreating, !isExtracting else { return }

        // SECURITY: Never silently ignore options the backend cannot honor.
        if splitVolumeSize != nil {
            creationErrorMessage = localization.string(
                "分卷创建暂不可用。为避免生成未分卷的压缩包，已停止创建。"
            )
            operationMessage = localization.string("创建失败")
            return
        }

        let registry = await loader.capabilityRegistry
        switch format {
        case .sevenZip:
            if !registry.snapshot(format: .sevenZip).actions.contains(.create) {
                creationErrorMessage = localization.string("7z 创建需要安装 7zz。请运行 brew install 7zip 后重试。")
                operationMessage = localization.string("创建失败")
                return
            }
        case .rar:
            if !registry.snapshot(format: .rar).actions.contains(.create) {
                creationErrorMessage = localization.string("RAR 创建需要安装 rar 工具。请从 RARLAB 官网下载后重试。")
                operationMessage = localization.string("创建失败")
                return
            }
        default:
            break
        }

        isCreating = true
        creationProgress = 0
        creationErrorMessage = nil
        lastCreatedURL = nil
        operationMessage = localization.string("正在准备创建归档…")
        let (stream, continuation) = AsyncStream.makeStream(
            of: WindowsZIPCreationProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let progressTask = Task { @MainActor [weak self] in
            for await progress in stream {
                guard let self else { return }
                let fraction: Double
                if progress.totalBytes > 0 {
                    fraction = Double(progress.completedBytes) / Double(progress.totalBytes)
                } else if progress.totalEntries > 0 {
                    fraction = Double(progress.completedEntries) / Double(progress.totalEntries)
                } else {
                    fraction = 0
                }
                self.creationProgress = min(max(fraction, 0), 1)
                self.operationMessage = self.localization.format(
                    "正在创建 · %ld/%ld 项",
                    progress.completedEntries,
                    progress.totalEntries
                )
            }
        }
        defer { isCreating = false }
        do {
            let snapshot: ArchiveDocumentSnapshot
            switch format {
            case .zip:
                let level: Int32
                switch zipCompressionLevel {
                case .store: level = 0
                case .deflate: level = 6
                case .maximum: level = 9
                }
                let encrypt: Int32
                if let encryptionMethod {
                    switch encryptionMethod {
                    case .aes256: encrypt = 1
                    case .zipCrypto: encrypt = 2
                    }
                } else {
                    encrypt = 0
                }
                snapshot = try await loader.createWindowsZIP(
                    at: outputURL,
                    inputs: inputs,
                    compressLevel: level,
                    password: password,
                    encryptMethod: encrypt
                ) { progress in
                    continuation.yield(progress)
                }
            case .tarGz, .tarXz, .tarZst:
                continuation.yield(WindowsZIPCreationProgress(
                    completedEntries: 0,
                    totalEntries: 0,
                    completedBytes: 0,
                    totalBytes: 0
                ))
                let tarCompression: TARCompression
                switch format {
                case .tarGz: tarCompression = .gzip
                case .tarXz: tarCompression = .xz
                case .tarZst: tarCompression = .zstd
                default: tarCompression = .gzip
                }
                snapshot = try await loader.createTARArchive(
                    at: outputURL,
                    inputs: inputs,
                    compression: tarCompression
                )
            case .sevenZip:
                continuation.yield(WindowsZIPCreationProgress(
                    completedEntries: 0,
                    totalEntries: 0,
                    completedBytes: 0,
                    totalBytes: 0
                ))
                snapshot = try await loader.createSevenZip(
                    at: outputURL,
                    inputs: inputs,
                    password: password
                )
            case .rar:
                continuation.yield(WindowsZIPCreationProgress(
                    completedEntries: 0,
                    totalEntries: 0,
                    completedBytes: 0,
                    totalBytes: 0
                ))
                snapshot = try await loader.createRAR(
                    at: outputURL,
                    inputs: inputs,
                    password: password
                )
            }
            continuation.finish()
            await progressTask.value
            try Task.checkCancellation()
            apply(snapshot)
            creationProgress = 1
            lastCreatedURL = outputURL
            statusMessage = localization.format("创建完成：%@", outputURL.lastPathComponent)
            operationMessage = localization.string("创建完成")
        } catch is CancellationError {
            continuation.finish()
            progressTask.cancel()
            await progressTask.value
            statusMessage = localization.string("已取消创建归档")
            operationMessage = localization.string("当前没有进行中的操作")
        } catch {
            continuation.finish()
            progressTask.cancel()
            await progressTask.value
            creationErrorMessage = creationMessage(for: error)
            operationMessage = localization.string("创建失败")
        }
    }

    func cancelCreation() {
        creationTask?.cancel()
    }

    // MARK: - Open File Externally

    func openFileExternally(entryID: ArchiveEntryID) async {
        guard LicenseGate.requirePro(for: .extract) else { return }
        guard hasDocument else { return }
        do {
            let url = try await loader.materializePreview(entryID: entryID)
            guard Self.setQuarantineAttribute(on: url) else {
                presentedError = AppLocalization().string("无法设置安全隔离属性，已阻止打开。")
                return
            }
            if !NSWorkspace.shared.open(url) {
                presentedError = AppLocalization().string("没有可用的应用程序打开此文件。")
            }
        } catch {
            presentedError = AppLocalization().format("无法打开文件：%@", error.localizedDescription)
        }
    }

    @discardableResult
    private static func setQuarantineAttribute(on url: URL) -> Bool {
        let uuid = UUID().uuidString
        let timestamp = String(UInt64(Date().timeIntervalSinceReferenceDate), radix: 16)
        let value = Data("0081;\(timestamp);com.smkzw.MacUnzip;\(uuid)".utf8)
        return value.withUnsafeBytes { buffer in
            setxattr(url.path, "com.apple.quarantine", buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW) == 0
        }
    }

    private static func setQuarantineRecursively(on url: URL) {
        setQuarantineAttribute(on: url)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return }
        for case let fileURL as URL in enumerator {
            setQuarantineAttribute(on: fileURL)
        }
    }

    // MARK: - Nested Archive Navigation

    /// Opens a nested archive entry as a sub-session. Materializes the entry
    /// through the secure preview cache, then opens it as a new read-only session.
    /// Requires explicit user action (double-click or Cmd+O). Never auto-recurses.
    func openNestedArchive(entryID: ArchiveEntryID) async {
        guard hasDocument, !isLoading else { return }
        guard nestedDepth < maximumNestedArchiveDepth else {
            transientStatusMessage = localization.string("已达到最大嵌套深度限制。")
            return
        }
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        let filename = entry.displayPath.split(separator: "/").last.map(String.init) ?? entry.displayPath
        guard ArchiveFileTypes.isNestedArchive(filename) else { return }

        isLoading = true
        presentedError = nil
        defer { isLoading = false }

        var nestedDir: URL?
        do {
            // Materialize the nested archive entry to preview cache (secure, budgeted)
            try Task.checkCancellation()
            let previewURL = try await loader.materializePreview(entryID: entryID)
            try Task.checkCancellation()

            // Move to a stable location outside the preview session, because
            // loader.open() calls resetPreviewSession() which deletes the
            // entire preview cache tree.
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MacUnzip_nested_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            nestedDir = dir
            let materializedURL = dir.appendingPathComponent(previewURL.lastPathComponent)
            try FileManager.default.moveItem(at: previewURL, to: materializedURL)

            // Build the parent session snapshot, but do NOT push it until the
            // nested archive actually opens. Otherwise a failed open (corrupt
            // or password-protected nested archive) would leave a phantom
            // parent session on the stack and corrupt back-navigation.
            let snapshot = ArchiveSessionSnapshot(
                sourceURL: currentSourceURL ?? materializedURL,
                documentTitle: documentTitle,
                entries: entries,
                metadataByEntryID: metadataByEntryID,
                folderSummaries: folderSummaries,
                selectedEntryID: selectedEntryID,
                currentDirectory: currentDirectory,
                viewMode: viewMode,
                documentItemCount: documentItemCount,
                canAdd: canAdd,
                canExtract: canExtract,
                canTestIntegrity: canTestIntegrity,
                pendingChanges: pendingChanges,
                archiveFormatName: archiveFormatName,
                encryptedEntryIDs: encryptedEntryIDs,
                materializedURL: isNestedSession ? currentSourceURL : nil
            )

            // Open the materialized archive as a new session.
            let nestedSnapshot = try await loader.open(url: materializedURL)
            try Task.checkCancellation()
            activeRegistry = await loader.capabilityRegistry

            // Success: now commit the navigation state.
            sessionStack.append(snapshot)
            nestedMaterializedURLs.append(dir)
            apply(nestedSnapshot)

            // Nested sessions are read-only
            isNestedSession = true
            canAdd = false
            pendingChanges = []
            transientStatusMessage = localization.format(
                "已打开嵌套压缩包 %@（第 %ld 层）",
                filename,
                nestedDepth
            )
        } catch is CancellationError {
            if let nestedDir { try? FileManager.default.removeItem(at: nestedDir) }
            return
        } catch let error as ArchiveError where error == .passwordRequired || error == .wrongPassword {
            if let nestedDir { try? FileManager.default.removeItem(at: nestedDir) }
            presentedError = localization.string("此嵌套压缩包需要密码，请先解压后再单独打开。")
        } catch {
            if let nestedDir { try? FileManager.default.removeItem(at: nestedDir) }
            presentedError = userMessage(for: error)
        }
    }

    /// Navigates back to the parent session, restoring its state.
    func navigateBack() {
        guard !isLoading, sessionStack.count > 0 else { return }
        restoreSession()
        reopenLoaderForCurrentSession()
    }

    /// Navigates to a specific breadcrumb level (0-indexed).
    func navigateToBreadcrumb(index: Int) {
        guard !isLoading, index >= 0, index < sessionStack.count else { return }
        while sessionStack.count > index {
            restoreSession()
        }
        reopenLoaderForCurrentSession()
    }

    private func restoreSession() {
        guard let parentSnapshot = sessionStack.popLast() else { return }

        // Clean up the materialized file for the session we're leaving
        if let materializedURL = nestedMaterializedURLs.popLast() {
            try? FileManager.default.removeItem(at: materializedURL)
        }

        // Restore parent session state
        currentSourceURL = parentSnapshot.sourceURL
        entries = parentSnapshot.entries
        metadataByEntryID = parentSnapshot.metadataByEntryID
        folderSummaries = parentSnapshot.folderSummaries
        selectedEntryID = parentSnapshot.selectedEntryID
        currentDirectory = parentSnapshot.currentDirectory
        viewMode = parentSnapshot.viewMode
        documentTitle = parentSnapshot.documentTitle
        documentItemCount = parentSnapshot.documentItemCount
        canAdd = parentSnapshot.canAdd
        canExtract = parentSnapshot.canExtract
        canTestIntegrity = parentSnapshot.canTestIntegrity
        pendingChanges = parentSnapshot.pendingChanges
        archiveFormatName = parentSnapshot.archiveFormatName
        encryptedEntryIDs = parentSnapshot.encryptedEntryIDs
        scrollAnchor = selectedEntryID
        previewCacheURL = nil
        previewCacheEntryID = nil
        previewErrorMessage = nil
        isPreviewLoading = false
        isNestedSession = !sessionStack.isEmpty
        clearSearch()
        computeNestedArchiveEntryIDs()
        buildSearchIndex(for: entries)
    }

    private func reopenLoaderForCurrentSession() {
        navigationReopenTask?.cancel()
        guard let parentURL = currentSourceURL else { return }
        isLoading = true
        let changesToRestore = pendingChanges
        navigationReopenTask = Task { [weak self] in
            guard let self else { return }
            defer { isLoading = false }
            do {
                try Task.checkCancellation()
                _ = try await loader.open(url: parentURL)
                try Task.checkCancellation()
                for change in changesToRestore {
                    try await loader.stageChange(change)
                }
                activeRegistry = await loader.capabilityRegistry
            } catch is CancellationError {
                // Superseded by newer navigation; ignore.
            } catch {
                self.operationMessage = localization.string("无法重新打开上级压缩包，请重新打开文件。")
            }
        }
    }

    /// Computes which visible entries are themselves archives (for badge display).
    func computeNestedArchiveEntryIDs() {
        var ids = Set<ArchiveEntryID>()
        for entry in entries {
            let path = entry.displayPath
            guard !path.hasSuffix("/") else { continue }
            let filename = path.split(separator: "/").last.map(String.init) ?? path
            if ArchiveFileTypes.isNestedArchive(filename) {
                ids.insert(entry.id)
            }
        }
        nestedArchiveEntryIDs = ids
    }

    /// The source URL of the currently open archive (for session snapshots).
    @ObservationIgnored private(set) var currentSourceURL: URL?

    static func mediaFixture(
        includeLongFilename: Bool = false,
        localization: AppLocalization = AppLocalization()
    ) -> AppModel {
        let model = AppModel(localization: localization)
        var names = ["首页主视觉.png", "深色标志.svg", "产品截图.heic", "演示视频.mp4", "品牌指南.pdf"]
        if includeLongFilename {
            names.append("季度Campaign_国际化视觉资产_最终批准版本_v12.heic")
        }
        model.entries = names.enumerated().map { index, name in
            let id = ArchiveEntryID(UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!)
            return ArchiveEntry(
                id: id,
                rawPath: ArchivePathBytes(Array("图片素材/\(name)".utf8)),
                displayPath: name
            )
        }
        func bytes(_ summary: String, _ count: String) -> String {
            localization.format("%@ (%@ 字节)", summary, count)
        }
        let details: [String: ArchiveEntryMetadata] = [
            "首页主视觉.png": ArchiveEntryMetadata(type: localization.string("PNG 图像"), size: bytes("8.4 MB", "8,796,293"), compressedSize: bytes("7.2 MB", "7,522,311"), modifiedDate: "2025/5/20 10:42", path: "图片素材/首页主视觉.png"),
            "深色标志.svg": ArchiveEntryMetadata(type: localization.string("SVG 图像"), size: bytes("1.2 MB", "1,258,291"), compressedSize: bytes("924 KB", "946,176"), modifiedDate: "2025/5/20 10:35", path: "图片素材/深色标志.svg"),
            "产品截图.heic": ArchiveEntryMetadata(type: localization.string("HEIC 图像"), size: bytes("12.7 MB", "13,316,915"), compressedSize: bytes("11.8 MB", "12,373,197"), modifiedDate: "2025/5/20 10:38", path: "图片素材/产品截图.heic"),
            "演示视频.mp4": ArchiveEntryMetadata(type: localization.string("MPEG-4 视频"), size: bytes("102.3 MB", "107,269,325"), compressedSize: bytes("98.1 MB", "102,865,306"), modifiedDate: "2025/5/20 10:40", path: "图片素材/演示视频.mp4"),
            "品牌指南.pdf": ArchiveEntryMetadata(type: localization.string("PDF 文档"), size: bytes("6.3 MB", "6,606,028"), compressedSize: bytes("5.7 MB", "5,976,883"), modifiedDate: "2025/5/20 10:41", path: "图片素材/品牌指南.pdf"),
            "季度Campaign_国际化视觉资产_最终批准版本_v12.heic": ArchiveEntryMetadata(type: localization.string("HEIC 图像"), size: bytes("14.8 MB", "15,519,949"), compressedSize: bytes("13.9 MB", "14,575,616"), modifiedDate: "2025/5/20 10:44", path: "图片素材/季度Campaign_国际化视觉资产_最终批准版本_v12.heic")
        ]
        model.metadataByEntryID = Dictionary(uniqueKeysWithValues: model.entries.compactMap { entry in
            details[entry.displayPath].map { (entry.id, $0) }
        })
        model.encryptedEntryIDs = []
        model.hasDocument = true
        model.usesFixturePreview = true
        model.documentTitle = "品牌素材与文档.zip"
        model.documentItemCount = 84
        model.canAdd = true
        model.canExtract = true
        model.canTestIntegrity = false
        model.viewMode = .media
        model.currentDirectory = "图片素材"
        model.folderSummaries = [
            ArchiveFolderSummary(name: "图片素材", itemCount: 48),
            ArchiveFolderSummary(name: "品牌规范", itemCount: 12),
            ArchiveFolderSummary(name: "演示文稿", itemCount: 15),
            ArchiveFolderSummary(name: "合同文档", itemCount: 9),
        ]
        model.selectedEntryID = model.entries.first?.id
        model.scrollAnchor = model.entries.first?.id
        return model
    }

    // MARK: - Debounced Search

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        let query = searchText
        if query.isEmpty {
            activeSearchText = ""
            searchResultCount = nil
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.activeSearchText = query
            self.searchResultCount = self.visibleEntries.count
        }
    }

    /// Clears search state (called by Escape key or programmatic clear).
    func clearSearch() {
        searchDebounceTask?.cancel()
        searchText = ""
        activeSearchText = ""
        searchResultCount = nil
    }

    /// Builds the search index in background for large archives.
    private func buildSearchIndex(for entries: [ArchiveEntry]) {
        guard entries.count > 1000 else {
            searchIndex = nil
            return
        }
        let snapshot = entries
        let fingerprint = "\(snapshot.count)-\(snapshot.first?.displayPath ?? "")-\(snapshot.last?.displayPath ?? "")"
        Task { [weak self] in
            let index = await Task.detached(priority: .utility) {
                ArchiveSearchIndex(entries: snapshot)
            }.value
            guard let self else { return }
            let currentFingerprint = "\(self.entries.count)-\(self.entries.first?.displayPath ?? "")-\(self.entries.last?.displayPath ?? "")"
            guard currentFingerprint == fingerprint else { return }
            self.searchIndex = index
        }
    }

    // MARK: - Crash Recovery Actions

    /// Registers a listener for crash-recovery journals discovered at launch.
    func observeCrashRecoveryJournals() {
        let pending = ArchiveWorkbenchAppDelegate.pendingRecoveryJournals
        if !pending.isEmpty {
            pendingRecoveryJournals = pending.map(\.journal)
            isRecoveryAlertPresented = true
            ArchiveWorkbenchAppDelegate.pendingRecoveryJournals = []
        }
        crashRecoveryObserver = NotificationCenter.default.addObserver(
            forName: .crashRecoveryJournalsFound,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let journals = notification.object
                as? [(journalURL: URL, journal: CrashRecoveryJournal)]
            else { return }
            MainActor.assumeIsolated {
                self?.pendingRecoveryJournals = journals.map(\.journal)
                self?.isRecoveryAlertPresented = !journals.isEmpty
            }
        }
    }

    /// Completes the interrupted save for the given journal (user chose 恢复).
    func recoverJournal(_ journal: CrashRecoveryJournal) {
        do {
            try CrashRecoveryJournalStore.recover(journal)
            pendingRecoveryJournals.removeAll { $0.stagingFile == journal.stagingFile }
        } catch {
            presentedError = userMessage(for: error)
        }
        isRecoveryAlertPresented = !pendingRecoveryJournals.isEmpty
    }

    /// Discards the staging file for the given journal (user chose 删除).
    func discardJournal(_ journal: CrashRecoveryJournal) {
        CrashRecoveryJournalStore.discard(journal)
        pendingRecoveryJournals.removeAll { $0.stagingFile == journal.stagingFile }
        isRecoveryAlertPresented = !pendingRecoveryJournals.isEmpty
    }

    private func apply(_ snapshot: ArchiveDocumentSnapshot) {
        releaseHeldAddSourceScopes()
        usesFixturePreview = false
        entries = snapshot.entries.map(\.entry)
        encryptedEntryIDs = Set(snapshot.entries.lazy.filter(\.isEncrypted).map { $0.entry.id })
        metadataByEntryID = Dictionary(uniqueKeysWithValues: snapshot.entries.map { item in
            let path = item.entry.displayPath
            let type = typeDescription(path: path, isDirectory: item.isDirectory)
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(clamping: item.uncompressedSize),
                countStyle: .file
            )
            let compressedSize = ByteCountFormatter.string(
                fromByteCount: Int64(clamping: item.compressedSize),
                countStyle: .file
            )
            let modifiedDate = item.modifiedAt.map(Self.dateFormatter.string(from:)) ?? "—"
            return (item.entry.id, ArchiveEntryMetadata(
                type: type,
                size: size,
                compressedSize: compressedSize,
                modifiedDate: modifiedDate,
                path: path
            ))
        })
        documentTitle = snapshot.sourceURL.lastPathComponent
        documentItemCount = snapshot.entries.count
        archiveFormatName = snapshot.format.rawValue.uppercased()
        selectedEntryID = snapshot.entries.first(where: { !$0.isDirectory })?.entry.id
            ?? snapshot.entries.first?.entry.id
        scrollAnchor = selectedEntryID
        folderSummaries = folderSummaries(from: snapshot.entries)
        let selectedPath = snapshot.entries.first { $0.entry.id == selectedEntryID }?
            .entry.displayPath
        currentDirectory = selectedPath.map(topLevelCategory(for:))
            ?? folderSummaries.first?.name
            ?? ""
        let mediaExtensions = Set(["png", "jpg", "jpeg", "heic", "gif", "webp", "svg", "mp4", "mov", "m4v"])
        let safeMediaCount = snapshot.entries.filter { item in
            !item.isDirectory && !item.isSymbolicLink
                && mediaExtensions.contains(item.entry.displayPath.split(separator: ".").last?.lowercased() ?? "")
        }.count
        viewMode = MediaRecommendationPolicy().shouldRecommend(
            totalFiles: snapshot.entries.filter { !$0.isDirectory }.count,
            safeMediaFiles: safeMediaCount,
            userSelectedMode: false
        ) ? .media : .list
        capabilitySnapshot = activeRegistry.snapshot(format: snapshot.format)
        pendingChanges = []
        canAdd = capabilitySnapshot.actions.contains(.update)
        canExtract = capabilitySnapshot.actions.contains(.read)
        canTestIntegrity = false
        previewCacheURL = nil
        previewCacheEntryID = nil
        previewErrorMessage = nil
        isPreviewLoading = false
        resetCreationState()
        resetExtractionState()
        hasDocument = true
        currentSourceURL = snapshot.sourceURL
        computeNestedArchiveEntryIDs()
        buildSearchIndex(for: entries)
    }

    private func clearDocument() {
        releaseHeldAddSourceScopes()
        sessionStack.removeAll()
        for url in nestedMaterializedURLs {
            try? FileManager.default.removeItem(at: url)
        }
        nestedMaterializedURLs.removeAll()
        isNestedSession = false
        nestedArchiveEntryIDs = []
        currentSourceURL = nil
        usesFixturePreview = false
        formatMismatchWarning = nil
        searchDebounceTask?.cancel()
        searchIndex = nil
        activeSearchText = ""
        searchResultCount = nil
        hasDocument = false
        entries = []
        encryptedEntryIDs = []
        metadataByEntryID = [:]
        selectedEntryID = nil
        documentTitle = ""
        documentItemCount = 0
        currentDirectory = ""
        folderSummaries = []
        scrollAnchor = nil
        pendingChanges = []
        canAdd = false
        canExtract = false
        canTestIntegrity = false
        previewCacheURL = nil
        previewCacheEntryID = nil
        previewErrorMessage = nil
        isPreviewLoading = false
        resetCreationState()
        resetExtractionState()
    }

    private func resetExtractionState() {
        isExtracting = false
        extractionProgress = 0
        lastExtractionURL = nil
        extractionErrorMessage = nil
        activeErrorPresentation = nil
        conflictContinuation?.resume(returning: .skip)
        conflictContinuation = nil
        activeConflict = nil
        passwordRetryText = ""
        passwordAttemptCount = 0
        conflictBatchResolution = nil
        errorAutoDismissTask?.cancel()
        operationMessage = localization.string("当前没有进行中的操作")
    }

    func resetCreationState() {
        isCreating = false
        creationProgress = 0
        lastCreatedURL = nil
        creationErrorMessage = nil
        creationPassword = ""
        creationPasswordConfirm = ""
        if let stagingDir = preflightStagingDir {
            try? FileManager.default.removeItem(at: stagingDir)
            preflightStagingDir = nil
        }
        operationMessage = localization.string("当前没有进行中的操作")
    }

    private func typeDescription(path: String, isDirectory: Bool) -> String {
        if isDirectory { return localization.string("文件夹") }
        guard let suffix = path.split(separator: ".").last, suffix != Substring(path) else {
            return localization.string("文件")
        }
        return localization.format("%@ 文件", String(suffix).uppercased())
    }

    private func folderSummaries(
        from entries: [ArchiveEntrySnapshot]
    ) -> [ArchiveFolderSummary] {
        var counts: [String: Int] = [:]
        for item in entries where !item.isDirectory {
            let components = item.entry.displayPath.split(separator: "/", omittingEmptySubsequences: true)
            let name = components.count > 1
                ? String(components[0])
                : localization.string("压缩包根目录")
            counts[name, default: 0] += 1
        }
        return counts.map { ArchiveFolderSummary(name: $0.key, itemCount: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func topLevelCategory(for path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.count > 1
            ? String(components[0])
            : localization.string("压缩包根目录")
    }

    private func userMessage(for error: Error) -> String {
        guard let archiveError = error as? ArchiveError else {
            return localization.string("无法打开这个压缩包。请确认文件仍然可访问后再试。")
        }
        switch archiveError {
        case .passwordRequired:
            return localization.string("这个压缩包需要密码才能打开。")
        case .wrongPassword:
            return localization.string("密码不正确，请重新输入。")
        case .unsupportedEncryption:
            return localization.string("这个压缩包使用了当前版本尚不支持的加密方式。")
        case .unsupportedMethod:
            return localization.string("压缩包包含当前版本尚不支持的压缩方式。")
        case .missingVolume:
            return localization.string("找不到分卷压缩包的其他部分。请将所有分卷放在同一文件夹后再试。")
        case .unsafePath:
            return localization.string("压缩包包含不安全的文件路径，已停止打开。")
        case .resourceLimit:
            return localization.string("压缩包内容超出安全限制，已停止打开。")
        case .sourceChanged:
            return localization.string("压缩包在读取期间发生了变化，请重新打开。")
        case .helperFailed:
            return localization.string("无法读取压缩包。请稍后再试。")
        case .unsupportedFormat:
            return localization.string("此格式不支持该操作。")
        case .corruptedArchive:
            return localization.string("无法打开这个压缩包。文件可能已损坏或不是受支持的格式。")
        case .providerNotInstalled:
            return localization.string("此格式需要 7zz 命令行工具，但未找到。请在设置中检查工具路径。")
        }
    }

    private func extractionFraction(_ progress: ZIPExtractionProgress) -> Double {
        let fraction: Double
        if progress.totalBytes > 0 {
            fraction = Double(progress.completedBytes) / Double(progress.totalBytes)
        } else if progress.totalEntries > 0 {
            fraction = Double(progress.completedEntries) / Double(progress.totalEntries)
        } else {
            fraction = 1
        }
        return min(max(fraction, 0), 1)
    }

    private func extractionMessage(for error: Error) -> String {
        guard let archiveError = error as? ArchiveError else {
            return localization.string("无法完成解压缩，未生成任何文件。")
        }
        switch archiveError {
        case .passwordRequired, .wrongPassword:
            return localization.string("这个压缩包需要正确的密码才能解压缩。")
        case .unsafePath:
            return localization.string("压缩包包含不安全的文件路径，已停止解压缩，未生成任何文件。")
        case .resourceLimit:
            return localization.string("压缩包内容超出安全解压限制，未生成任何文件。")
        case .unsupportedEncryption:
            return localization.string("当前版本暂不支持这种加密方式，未生成任何文件。")
        case .unsupportedMethod:
            return localization.string("当前版本暂不支持这种压缩方式，未生成任何文件。")
        case .corruptedArchive:
            return localization.string("压缩包可能已损坏，解压缩未完成，也未生成任何文件。")
        default:
            return localization.string("无法完成解压缩，未生成任何文件。")
        }
    }

    private func creationMessage(for error: Error) -> String {
        if let profileError = error as? WindowsZIPProfileError {
            switch profileError {
            case .noInputs:
                return localization.string("没有可归档的文件。")
            case .invalidName(let name):
                return localization.format("“%@”不符合 Windows 文件名规则，请重命名后再试。", name)
            case .collision(let first, let second):
                return localization.format("“%@”与“%@”在 Windows 中会发生名称冲突。", first, second)
            case .unsupportedItem(let name):
                return localization.format("“%@”是特殊文件类型，无法归档。", name)
            case .outputExists:
                return localization.string("目标位置已存在同名压缩包，未覆盖原文件。")
            case .io:
                return localization.string("无法写入目标位置，未生成压缩包。")
            }
        }
        if error is ArchiveError {
            return localization.string("创建后的校验未通过，未生成压缩包。")
        }
        return localization.string("无法创建压缩包，未生成任何文件。")
    }

    private func previewMessage(for error: Error) -> String {
        guard let archiveError = error as? ArchiveError else {
            return localization.string("无法生成这个文件的安全预览。")
        }
        switch archiveError {
        case .passwordRequired, .wrongPassword:
            return localization.string("这个文件需要正确的压缩包密码才能预览。")
        case .resourceLimit:
            return localization.string("这个文件过大，已停止生成预览。")
        case .unsupportedMethod, .unsupportedEncryption:
            return localization.string("当前版本无法预览这种压缩或加密方式。")
        case .unsafePath:
            return localization.string("这个文件的路径不安全，已停止预览。")
        case .sourceChanged:
            return localization.string("压缩包已发生变化，请重新打开后再预览。")
        default:
            return localization.string("无法生成这个文件的安全预览。")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
