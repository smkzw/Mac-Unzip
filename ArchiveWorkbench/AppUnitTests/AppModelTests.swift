import ArchiveDomain
import XCTest

final class AppModelTests: XCTestCase {
    func testMediaRecommendationRequiresSeventyPercentAndFourSafeFiles() {
        let policy = MediaRecommendationPolicy()

        XCTAssertTrue(policy.shouldRecommend(totalFiles: 10, safeMediaFiles: 7, userSelectedMode: false))
        XCTAssertFalse(policy.shouldRecommend(totalFiles: 10, safeMediaFiles: 6, userSelectedMode: false))
        XCTAssertFalse(policy.shouldRecommend(totalFiles: 4, safeMediaFiles: 4, userSelectedMode: true))
        XCTAssertFalse(policy.shouldRecommend(totalFiles: 0, safeMediaFiles: 0, userSelectedMode: false))
    }

    @MainActor
    func testChangingViewModePreservesDocumentState() {
        let model = AppModel.mediaFixture()
        let selectedEntryID = model.selectedEntryID
        let currentDirectory = model.currentDirectory
        let scrollAnchor = model.scrollAnchor
        let searchText = "品牌"
        let pendingChanges = [PendingChange.remove(entryPath: "待处理修改.txt")]
        model.searchText = searchText
        model.pendingChanges = pendingChanges

        model.viewMode = .list

        XCTAssertEqual(model.selectedEntryID, selectedEntryID)
        XCTAssertEqual(model.currentDirectory, currentDirectory)
        XCTAssertEqual(model.scrollAnchor, scrollAnchor)
        XCTAssertEqual(model.searchText, searchText)
        XCTAssertEqual(model.pendingChanges, pendingChanges)
    }

    @MainActor
    func testSelectedEntryDerivesStatusFromPDFMetadata() {
        let model = AppModel.mediaFixture()
        model.selectedEntryID = model.entries.first(where: { $0.displayPath == "品牌指南.pdf" })?.id

        XCTAssertEqual(model.statusMessage, "已选择 1 项 · 6.3 MB")
    }

    func testWindowsCreationDraftKeepsCompatibilityFactsVisible() {
        let folder = URL(fileURLWithPath: "/tmp/品牌资料", isDirectory: true)
        var single = ArchiveCreationDraft(inputs: [folder])

        XCTAssertEqual(single.suggestedFilename, "品牌资料.zip")
        XCTAssertEqual(single.purpose, "发给 Windows 用户")
        XCTAssertEqual(single.format, "ZIP")
        XCTAssertEqual(single.compression, "标准压缩")
        XCTAssertEqual(single.encryption, "不加密")
        XCTAssertEqual(single.compatibility, "Windows 11 可直接打开")
        XCTAssertFalse(single.canCreate)

        single.outputURL = URL(fileURLWithPath: "/tmp/品牌资料.zip")
        XCTAssertTrue(single.canCreate)

        let multiple = ArchiveCreationDraft(inputs: [
            folder,
            URL(fileURLWithPath: "/tmp/说明.txt"),
        ])
        XCTAssertEqual(multiple.suggestedFilename, "归档.zip")
    }

    func testWindowsCreationDraftUsesEnglishCatalogWhenEnglishIsSelected() {
        let draft = ArchiveCreationDraft(
            inputs: [URL(fileURLWithPath: "/tmp/Brand Assets", isDirectory: true)],
            localization: AppLocalization(
                bundle: Bundle(for: Self.self),
                locale: Locale(identifier: "en")
            )
        )

        XCTAssertEqual(draft.purpose, "Send to Windows users")
        XCTAssertEqual(draft.compression, "Standard compression")
        XCTAssertEqual(draft.encryption, "No encryption")
        XCTAssertEqual(draft.compatibility, "Opens directly in Windows 11")
    }

    func testWindowsCreationCopyUsesNaturalChineseAndAccurateVerificationTiming() {
        let bundle = Bundle(for: Self.self)
        XCTAssertEqual(
            ArchiveCreationCopy.subtitle(
                localization: AppLocalization(bundle: bundle, locale: Locale(identifier: "zh-Hans"))
            ),
            "创建 Windows 用户可直接打开的 ZIP 压缩包"
        )
        XCTAssertEqual(
            ArchiveCreationCopy.verificationNote(
                localization: AppLocalization(bundle: bundle, locale: Locale(identifier: "zh-Hans"))
            ),
            "保存前会重新打开并核对全部文件。"
        )
        XCTAssertEqual(
            ArchiveCreationCopy.subtitle(
                localization: AppLocalization(bundle: bundle, locale: Locale(identifier: "en"))
            ),
            "Create a ZIP archive that Windows users can open directly"
        )
        XCTAssertEqual(
            ArchiveCreationCopy.verificationNote(
                localization: AppLocalization(bundle: bundle, locale: Locale(identifier: "en"))
            ),
            "The archive will be reopened and verified before it is saved."
        )
        let english = AppLocalization(bundle: bundle, locale: Locale(identifier: "en"))
        XCTAssertEqual(ArchiveCreationCopy.inputPanelTitle(localization: english), "Choose Items to Archive")
        XCTAssertEqual(ArchiveCreationCopy.inputPanelPrompt(localization: english), "Continue")
        XCTAssertEqual(
            ArchiveCreationCopy.inputPanelMessage(localization: english),
            "Select multiple files and folders. Windows filename compatibility will be checked before creation."
        )
        XCTAssertEqual(ArchiveCreationCopy.savePanelTitle(localization: english), "Save Archive")
        XCTAssertEqual(ArchiveCreationCopy.savePanelPrompt(localization: english), "Choose")
        XCTAssertEqual(
            ArchiveCreationCopy.savePanelMessage(localization: english),
            "Choose a save location and filename. Existing files will never be replaced without warning."
        )
        XCTAssertEqual(
            ArchiveCreationCopy.inputCount(2, localization: english),
            "Items to Archive · 2"
        )
        XCTAssertEqual(ArchiveCreationCopy.purposeLabel(localization: english), "Purpose")
        XCTAssertEqual(ArchiveCreationCopy.formatLabel(localization: english), "Format")
        XCTAssertEqual(ArchiveCreationCopy.compressionLabel(localization: english), "Compression")
        XCTAssertEqual(ArchiveCreationCopy.encryptionLabel(localization: english), "Encryption")
        XCTAssertEqual(ArchiveCreationCopy.noSelection(localization: english), "Not Selected")
    }

    func testCreationPanelEnglishCatalogCoversVisibleLabels() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )
        let expected = [
            "创建归档": "Create Archive",
            "创建 Windows 11 可直接打开的 ZIP 压缩包": "Create a ZIP archive that opens directly in Windows 11",
            "无法创建压缩包": "Couldn’t Create Archive",
            "创建归档面板": "Create Archive panel",
            "创建设置": "Creation Settings",
            "用途": "Purpose",
            "格式": "Format",
            "压缩方式": "Compression",
            "加密": "Encryption",
            "使用 UTF-8 文件名，自动排除 macOS 元数据；创建前检查 Windows 保留名、非法字符和名称冲突。": "Uses UTF-8 filenames and excludes macOS metadata. Windows reserved names, invalid characters, and name conflicts are checked before creation.",
            "保存位置": "Save Location",
            "尚未选择": "Not Selected",
            "选择…": "Choose…",
            "取消": "Cancel",
        ]

        for (key, value) in expected {
            XCTAssertEqual(localization.string(key), value, key)
        }
        XCTAssertEqual(
            localization.format("正在创建 · %ld/%ld 项", 1, 3),
            "Creating · 1/3 items"
        )
    }

    func testMetadataAndFolderCountsUseEnglishCatalogWhenEnglishIsSelected() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )
        let metadata = ArchiveEntryMetadata(
            type: "PDF Document",
            size: "6.3 MB (6,606,028 bytes)",
            compressedSize: "5.7 MB",
            modifiedDate: "2025/5/20",
            path: "Documents/Guide.pdf"
        )
        let folder = ArchiveFolderSummary(name: "Documents", itemCount: 2)

        XCTAssertEqual(
            metadata.statusMessage(localization: localization),
            "1 item selected · 6.3 MB"
        )
        XCTAssertEqual(folder.countText(localization: localization), "2 items")
    }

    func testShellEnglishCatalogCoversPrimaryControlsAndPanels() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )
        let expected = [
            "返回": "Back",
            "返回上一个文件夹": "Go back to the previous folder",
            "前进": "Forward",
            "前往下一个文件夹": "Go to the next folder",
            "列表视图": "List View",
            "切换为列表视图": "Switch to List View",
            "媒体预览": "Media Preview",
            "切换为媒体预览": "Switch to Media Preview",
            "信息": "Info",
            "显示或隐藏归档信息检查器": "Show or hide the archive inspector",
            "添加": "Add",
            "向压缩包添加文件": "Add files to the archive",
            "解压缩": "Extract",
            "解压缩所选内容": "Extract the selected items",
            "共享": "Share",
            "标签": "Tags",
            "当前操作": "Current Operation",
            "搜索": "Search",
            "搜索压缩包内容": "Search Archive Contents",
            "打开压缩包": "Open Archive",
            "打开压缩包…": "Open Archive…",
            "设置": "Settings",
            "Mac解霸": "Mac Unzip",
            "打开 ZIP 压缩包，安全查看其中的文件。": "Open ZIP archives and inspect their files safely.",
            "无法打开压缩包": "Couldn’t Open Archive",
            "无法解压缩": "Couldn’t Extract Archive",
            "好": "OK",
            "欢迎": "Welcome",
            "正在读取压缩包…": "Reading archive…",
            "打开": "Open",
            "选择一个 ZIP 压缩包": "Choose a ZIP archive",
            "选择解压位置": "Choose Extraction Location",
            "解压缩到此处": "Extract Here",
            "应用会在所选位置创建一个新文件夹，不会覆盖已有文件。": "A new folder will be created at the selected location. Existing files will not be replaced.",
        ]

        for (key, value) in expected {
            XCTAssertEqual(localization.string(key), value, key)
        }
    }

    func testShellRuntimeCopyUsesEnglishForPanelsAndReadyStates() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(ArchiveShellCopy.openPanelTitle(localization: localization), "Open Archive")
        XCTAssertEqual(ArchiveShellCopy.openPanelPrompt(localization: localization), "Open")
        XCTAssertEqual(ArchiveShellCopy.openPanelMessage(localization: localization), "Choose a ZIP archive")
        XCTAssertEqual(ArchiveShellCopy.extractionPanelTitle(localization: localization), "Choose Extraction Location")
        XCTAssertEqual(ArchiveShellCopy.extractionPanelPrompt(localization: localization), "Extract Here")
        XCTAssertEqual(
            ArchiveShellCopy.extractionPanelMessage(localization: localization),
            "A new folder will be created at the selected location. Existing files will not be replaced."
        )
        XCTAssertEqual(ArchiveShellCopy.readyToAdd(localization: localization), "Ready to add files")
        XCTAssertEqual(
            ArchiveShellCopy.readyToChooseExtractionLocation(localization: localization),
            "Ready to choose an extraction location"
        )
    }

    func testExtractionRuntimeCopyUsesEnglishDefaultFolderName() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )

        XCTAssertEqual(
            ArchiveExtractionCopy.defaultFolderName(localization: localization),
            "Extracted Contents"
        )
    }

    func testContentInspectorAndPreviewEnglishCatalogCoverage() {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )
        let expected = [
            "名称": "Name", "类型": "Type", "大小": "Size", "修改日期": "Date Modified",
            "压缩后大小": "Compressed Size", "路径": "Path", "文件名称": "Filename",
            "文件大小": "File Size", "归档目录": "Archive Directory", "归档信息": "Archive Info",
            "归档内容": "Archive Contents", "归档分栏": "Archive Split View",
            "归档工具栏": "Archive Toolbar", "归档信息检查器": "Archive Inspector",
            "解压缩进度": "Extraction Progress", "取消解压缩": "Cancel Extraction",
            "在 Finder 中显示": "Show in Finder",
            "添加功能将在安全编辑事务接入后启用": "Add will be available after safe editing is enabled",
            "解压缩全部内容": "Extract all contents", "当前压缩包无法解压缩": "This archive cannot be extracted",
            "操作": "Actions", "显示共享、标签和当前操作": "Show sharing, tags, and current operation",
            "当前操作面板": "Current Operation panel", "正在准备预览…": "Preparing preview…",
            "正在读取图片…": "Loading image…", "无法读取这张图片。": "This image could not be loaded.",
            "正在读取 PDF…": "Loading PDF…", "PDF 文档加载失败": "PDF could not be loaded",
            "系统暂时无法创建文档预览。": "A document preview is temporarily unavailable.",
            "Office Quick Look 安全缓存预览": "Secure Office Quick Look preview",
            "正在准备视频预览…": "Preparing video preview…", "这个视频无法播放。": "This video cannot be played.",
            "播放视频时发生错误。": "An error occurred while playing the video.",
            "原生视频预览": "Native video preview", "无法预览": "Preview Unavailable",
            "预览失败": "Preview Failed", "无法安全预览": "Secure Preview Unavailable",
            "图像": "image", "视频": "video", "PDF 文档": "PDF document",
            "向前滚动 PDF": "Scroll PDF forward", "向后滚动 PDF": "Scroll PDF backward",
            "PDF 滚动控制": "PDF scroll controls", "PDF 文档页面内容": "PDF page content",
        ]

        for (key, value) in expected {
            XCTAssertEqual(localization.string(key), value, key)
        }
        XCTAssertEqual(localization.format("%@，当前显示 %ld 项", "Assets.zip", 3), "Assets.zip, 3 items shown")
        XCTAssertEqual(localization.format("选择文件 %@", "Guide.pdf"), "Select file Guide.pdf")
        XCTAssertEqual(localization.format("文件名：%@", "Guide.pdf"), "Filename: Guide.pdf")
        XCTAssertEqual(localization.format("文件大小：%@", "6.3 MB"), "File size: 6.3 MB")
        XCTAssertEqual(localization.format("%@内容", "Archive"), "Archive content")
        XCTAssertEqual(localization.format("PDF 文档已加载，%ld 页", 4), "PDF loaded, 4 pages")
        XCTAssertEqual(localization.format("PDFKit 安全缓存预览，%ld 页", 4), "Secure PDFKit preview, 4 pages")
        XCTAssertEqual(localization.format("PDF 文档页面内容，共 %ld 页", 4), "PDF page content, 4 pages")
        XCTAssertEqual(localization.format("PDF 页面容器，共 %ld 页", 4), "PDF page container, 4 pages")
    }

    @MainActor
    func testEnglishMediaFixtureLocalizesMetadataWithoutRenamingArchiveEntries() throws {
        let localization = AppLocalization(
            bundle: Bundle(for: Self.self),
            locale: Locale(identifier: "en")
        )
        let model = AppModel.mediaFixture(localization: localization)
        let entry = try XCTUnwrap(model.entries.first { $0.displayPath == "首页主视觉.png" })
        let metadata = try XCTUnwrap(model.metadataByEntryID[entry.id])

        XCTAssertEqual(entry.displayPath, "首页主视觉.png")
        XCTAssertEqual(metadata.type, "PNG image")
        XCTAssertEqual(metadata.size, "8.4 MB (8,796,293 bytes)")
        XCTAssertEqual(metadata.compressedSize, "7.2 MB (7,522,311 bytes)")
    }
}
