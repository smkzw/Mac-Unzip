# Mature Archive and File-Manager Product Design Synthesis

Date: 2026-07-11
Purpose: design evidence for the native macOS archive app; current claims were checked against official product documentation, current upstream repositories, live installed app resources, and Apple/Microsoft specifications where available

## Products and evidence strength

| Product | Evidence used | Frontend lessons | Backend/workflow lessons | Evidence quality |
|---|---|---|---|---|
| BetterZip 5.4.2 | Official current website/manual/version history | Archive table, favorite sidebar, info/preview, navigation bar, status bar, presets, operations queue, Finder extension | Staged modifications, external-editor round trip, integrity test, repair offers, Mac-metadata cleaning, external RAR helper | High: first-party docs, current 2026 version |
| Bandizip for macOS | Official product/help/screenshots | Tree + table + preview, visible columns, code-page control, image/document/music preview, repair workflow | ZIP mutation, archive test, parallel operations, filename normalization, external compatibility, repair-to-copy | High: first-party docs/screenshots |
| Keka | Official site/changelog/GitHub wiki/repository | Drag-to-window/Dock, minimal create surface, Finder contextual actions, password/split controls | Multi-format helper-oriented backend; format detection for unknown extensions; encrypted 7z/ZIP workflows | High for UX/features; source repo is mainly issues/wiki, not reusable app source |
| PeaZip 11.1 | Official GitHub/current help PDF | Powerful file/archive manager, bookmarks, history, filters, viewers, detailed operation forms | Backend dispatch across multiple tools, conversion, split/join, encryption, task-to-CLI representation | High for features/source; low native-macOS visual relevance |
| The Unarchiver 3.0.9 (installed) | Local signed app bundle, entitlements, Info.plist, Simplified-Chinese resources | Focused extraction, explicit destination/encoding/password/error sheets | Sandboxed user-selected/downloads access, security-scoped bookmarks, extensive document-type registration, split-part associations | High for current local binary behavior/configuration; extraction-only scope |
| MacZip | Official site | Finder service and archive Quick Look as primary lightweight entry points | Encrypted-format read paths and service integration | Medium: first-party marketing, limited technical detail |
| Commander One | Official site/manual/App Store | Dual-pane file transfer, archives presented like folders, built-in viewer | Archive editing integrated into a broader file-manager abstraction | Medium-high; useful contrast, not chosen shell |
| ForkLift 4 | Official site/manual/changelog | Activity view, preview pane, favorites, logs, resumable work context | Ordered background operations and clear activity surface | High for file-management patterns; archive editing is not its core |
| QSpace | Official guide/changelog/App Store | Finder habits, multipane workspaces, interactive breadcrumb, local filter + Spotlight, state restoration | Per-window workspace restoration and explicit drag/drop policies | Medium-high; not an archive engine reference |
| Finder/Quick Look | Apple Support/Developer docs | Native list/column/gallery behavior, sidebar, customizable toolbar, Space preview, drag/drop and contextual commands | File coordination, document association, Quick Look extensions | Highest for macOS conventions |

## BetterZip: strongest archive-editor reference

First-party sources:

- https://macitbetter.com/
- https://macitbetter.com/library/
- https://macitbetter.com/library/betterzip/docs/preferences/
- https://macitbetter.com/library/betterzip/docs/extract/
- https://macitbetter.com/library/betterzip/docs/extract-presets/
- https://macitbetter.com/library/betterzip/docs/queue/
- https://macitbetter.com/library/betterzip/docs/test/

### Adopt or adapt

- Contents table plus info/preview and a stable status bar.
- Navigation path as both context and valid drop target.
- Add/remove/rename/external-edit workflows that remain visible as archive changes.
- Integrity testing as a first-class operation and repair as a separately produced artifact.
- Extraction and creation presets that reveal their settings.
- Favorite destinations and recent destinations for fast repeated extraction.
- Operations queue with explicit concurrency control and notification on completion.
- Windows-clean output that removes Mac-specific files.
- Editing a file through an external app followed by a detected, explicit update decision.
- Favorite folders and archive discovery without turning the app into a full Finder replacement.

### Do not copy

- Press-and-hold dual-action toolbar buttons: primary behavior and menu behavior must be visually explicit.
- “Direct Mode” that increases source-mutation risk: all edits use the transaction layer.
- Post-extraction arbitrary script execution: conflicts with the product’s no-auto-execute invariant.
- User-selectable arbitrary temporary folder for mutations: same-volume sibling staging is mandatory for safe commit.
- Too many always-visible sidebars/filter bars: progressive disclosure protects the content surface.

## Bandizip: strongest compatibility and repair reference

First-party sources:

- https://www.bandisoft.com/bandizip.mac/
- https://en.bandisoft.com/bandizip.mac/help/
- https://en.bandisoft.com/bandizip.mac/help/how-to-modify-an-archive-without-decompression/
- https://en.bandisoft.com/bandizip.mac/help/how-to-preview-image-document-and-music-files-in-an-archive/
- https://en.bandisoft.com/bandizip.mac/help/explain-unicode-normalization/
- https://en.bandisoft.com/bandizip.mac/help/repair-archive/

### Adopt or adapt

- Folder tree, detailed table and optional preview are proven archive-browser surfaces.
- Show compressed and original sizes together.
- Code-page auto-detection with a visible override.
- NFC/NFD compatibility is a user-facing, testable policy rather than a hidden implementation detail.
- Archive comments and integrity-test results belong in information/diagnostic surfaces.
- Repair writes `(filename).repair.zip`-style output instead of overwriting the source; capability is ZIP-specific and never guaranteed.
- Filename encryption distinctions: 7z can hide names; encrypted ZIP generally leaves names visible.
- Finder right-click services and smart “extract here” behavior.

### Do not copy

- Bandizip’s documented password manager stores passwords locally without encryption and may sync them; this product uses macOS Keychain only.
- Password recovery/brute-force is outside scope and creates security/support ambiguity.
- Immediate mutation without an explicit staged-save model is not adopted.

## Keka: strongest low-friction create/extract reference

First-party sources:

- https://www.keka.io/en/
- https://changelog.keka.io/
- https://github.com/aonez/Keka/wiki/Compressing-with-Keka
- https://github.com/aonez/Keka

### Adopt or adapt

- Drag ordinary files/folders to the window/Dock/Finder action to begin creation.
- A compact creation surface centered on format, method/level, password and split size.
- Finder contextual actions for compression, extraction and password prompt.
- Detect format signatures when extensions are missing or unrecognized.
- Clear difference between AES-256 7z and legacy ZIP encryption.

### Do not copy

- Keka’s minimal single-task window is insufficient for the requested archive content editor; use it only as inspiration for the create sheet and Finder workflows.
- The public Keka repository is mainly issue/wiki collaboration, so it is not treated as reusable implementation source.

## PeaZip: strongest backend-dispatch and advanced-operation reference

Primary sources:

- https://github.com/peazip/PeaZip/
- https://peazip.github.io/peazip_help.pdf

### Adopt or adapt

- Treat each GUI action as a serializable, reviewable operation contract before execution.
- Conversion, split/join, integrity test, hashing and task history share an operation model.
- Bookmarked/recent output destinations reduce repetitive navigation.
- Built-in viewers are bounded fallbacks when platform preview is unavailable.
- Broad engine dispatch proves the value of a capability registry and provider adapters.

### Do not copy

- Dense cross-platform forms, toolbar proliferation and exposed CLI syntax do not fit a native macOS product.
- Two-factor/keyfile, secure deletion and general filesystem utilities are outside the requested scope.

## File-manager references: Finder familiarity without scope creep

### Finder and Quick Look

- List/column/gallery semantics, Return rename, Space preview, sidebar, sorting, toolbar customization and path navigation are the default behavior model.
- The application should look adjacent to Finder, not clone Finder’s entire filesystem responsibilities.

### QSpace

- Preserve window/workspace state and interactive breadcrumb behavior.
- Apply explicit drag/drop policy and visible destination rather than guessing.
- Multipane layouts are powerful but unnecessary for the default archive workflow.

### ForkLift

- A dedicated activity view and log provide confidence for long operations.
- Preview is useful when it updates deterministically with selection.
- Dual panes are optimized for transfers between locations; they would reduce space for archive preview/editing, so they are not the default here.

### Commander One and Path Finder

- Archives-as-folders validate Finder-like navigation and file commands.
- Power-user panes/modules show the risk of accumulating permanent chrome. Advanced capabilities should live in inspector, menus, settings and operation records rather than many fixed panels.

## Installed The Unarchiver evidence

Local bundle inspected: `/Applications/The Unarchiver.app` version 3.0.9.

- Universal binary (`x86_64 arm64`), signed with hardened runtime.
- App Sandbox enabled with app-scoped bookmarks, Downloads read/write and user-selected read/write.
- Registers extensive format and multipart extensions; RAR includes `r00`–`r99` and numbered part extensions.
- Simplified-Chinese resources contain explicit encoding selection, confidence threshold, password, missing/incomplete data, checksum, permissions, destination and multipart-search flows.
- Some local Chinese strings are dated or awkward (`偏好设置`, `粉碎文件时出错`), proving that installed-product wording is evidence to critique, not language to copy.

Implications:

- Security-scoped, sandboxed extraction is feasible; external executable-provider access still requires a dedicated Xcode spike before choosing the final sandbox policy.
- Multipart file associations must be modeled deliberately rather than registering only `.rar`/`.7z`/`.zip`.
- Encoding confidence/override is a real mature-product workflow and belongs in the spec.

## Consolidated front-end decisions

1. Keep the approved adaptive Finder-native shell.
2. Ordinary content: outline/table + right preview/inspector.
3. Media-dominant content: same shell + large preview + nearby-items strip.
4. Add a path/breadcrumb surface that supports navigation and safe drop targeting.
5. Keep a persistent, compact status/edit bar; move long-running work to `操作记录`.
6. Add recent/favorite extraction destinations but keep creation/extraction presets transparent.
7. Use explicit primary action plus adjacent menu; no hidden long-press dual action.
8. Search results may use a flat result list with full `路径` column while normal browsing stays hierarchical.
9. Repair always creates a copy; UI states the supported format and lack of guarantee.
10. External editing uses a controlled temporary copy and explicit detected-change decision.

## Consolidated back-end decisions

1. Typed `ArchiveOperation` objects are serializable to local operation history and diagnostics, never to executable shell strings.
2. Provider adapters expose capabilities, phases, progress and structured failure categories.
3. A unified operation scheduler supports ordered work, per-archive mutation exclusivity and bounded external concurrency.
4. Presets are versioned policy objects, not arbitrary shell hooks.
5. Source mutation always goes through `ArchiveTransaction`; no BetterZip-like Direct Mode.
6. Repair, conversion and external-editor return paths always produce staged/copy outputs before any commit.
7. Filename encoding stores original bytes, decoded display value, confidence, user override and comparison key separately.
8. Provider/tool version and identity are attached to each operation record for reproducibility.
9. Component license/provenance remains build-profile-specific.

## Design-spec changes required by this research

- Add path/breadcrumb navigation and safe drop-target semantics.
- Define flat search-results behavior.
- Define favorite/recent destinations and transparent presets.
- Add explicit external-editor round-trip workflow.
- Define repair-to-copy behavior and format limitation.
- Expand multipart association and discovery requirements.
- Add an App Sandbox/external-provider feasibility spike as an implementation-plan gate.
- Preserve a compact operation activity surface without making the main window a dashboard.

## Sources consulted but not used as authority

Third-party reviews and image-search descriptions were used to locate official pages and compare visible patterns. They do not support engine, license or security claims. Current claims above rely on first-party docs, upstream repositories, official platform documentation or inspected local binaries wherever possible.
# 2026-07-11 预览能力补充：PDF 与 Microsoft Office

Apple 当前 Quick Look 文档明确列出 Microsoft Office 文档、图片、文本、PDF、音频和视频为常见可预览类型；macOS 可将 `QLPreviewView` 嵌入应用视图层级。产品实现因此采用分层路线：图片原生显示、PDFKit `PDFView`、视频原生播放器、Word/Excel/PowerPoint 使用 `QLPreviewView`。Quick Look 支持类型可能随系统版本变化，因此仍需用真实 `.doc/.docx/.xls/.xlsx/.ppt/.pptx` 夹具逐类回归，不能只凭扩展名或 API 文档宣称完成。

主要来源：

- Apple Quick Look：https://developer.apple.com/documentation/quicklook
- Apple Quick Look UI：https://developer.apple.com/documentation/quicklookui/
- Apple `QLPreviewView`：https://developer.apple.com/documentation/quicklookui/qlpreviewview
- Apple PDFKit `PDFView`：https://developer.apple.com/documentation/pdfkit/pdfview
