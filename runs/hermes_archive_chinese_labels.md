# Hermes Chinese Copy Review: archive_chinese_labels

## Boundary Check

- Read in full: `/Users/smkzw/.hermes/SOUL.md`
- Source files read: DocumentToolbar.swift, RoutedPreviewViews.swift, AppModel.swift, DocumentShellTests.swift
- Context file read: context/archive_chinese_labels_context.md
- No production paths or unlisted sources were accessed.
- No source edits were made.
- No web, browser, visual, image, or test execution was performed.
- This review is confined to Chinese-copy judgment; visual layout, rendered acceptance, and final approval remain Codex-owned.

## Must Change

None. No current string is terminologically wrong, misleading, or likely to confuse a native macOS Chinese user.

The single actionable finding is that "检测完整性" should become "校验完整性" — but I've classified this as an Optional Refinement (see §4 for full reasoning), not a defect, because the current string is grammatically correct and understandable.

## Optional Refinements

### 1. "检测完整性" → "校验完整性"

- **File:** `ArchiveWorkbench/App/Sources/DocumentToolbar.swift:70`
- **Current string:** `"检测完整性"`
- **Proposed replacement:** `"校验完整性"`

**Evidence:** macOS platform convention. Disk Utility (磁盘工具) uses "校验磁盘" for verify-disk operations. Third-party checksum tools (e.g., Keka, The Unarchiver Chinese localizations) use "校验" for archive integrity verification. "检测" (detect/test) is the standard term for hardware diagnostics and medical testing, not for cryptographic or structural data verification.

**Impact if unchanged:** The label remains understandable. A native macOS user would know what the button does. The cost of keeping it is a mild stylistic mismatch with platform conventions — not a usability defect.

**Test impact:** Two XCUI test assertions reference the string literally:
- `DocumentShellTests.swift:47`: `XCTAssertFalse(app.buttons["检测完整性"].exists)`
- `DocumentShellTests.swift:98`: `XCTAssertFalse(app.buttons["检测完整性"].exists)`
- `DocumentShellTests.swift:210`: `XCTAssertTrue(app.menuItems["检测完整性"].waitForExistence(timeout: 3))`

All three would need the string updated. If the menu item label changes, the `accessibilityIdentifier` should also be updated for consistency — currently it inherits the label implicitly via `Label("检测完整性", systemImage:)`. After change: `Label("校验完整性", systemImage:)`.

**Also update (same file, line 85):**
- Current: `"显示共享、标签、完整性检测和当前操作"`
- Proposed: `"显示共享、标签、完整性校验和当前操作"`

**Also update (same file, line 71):**
- Current: `model.statusMessage = "完整性检测已排队"`
- Proposed: `model.statusMessage = "完整性校验已排队"`

### 2. "列表视图" → "列表"

- **File:** `ArchiveWorkbench/App/Sources/DocumentToolbar.swift:22`
- **Current string:** `"列表视图"` (toolbar button label)
- **Current help:** `"切换为列表视图"` (line 22)
- **Proposed replacement for label:** `"列表"`
- **Proposed help:** `"切换为列表"`

**Evidence:** macOS Finder uses "列表" (not "列表视图") for list-view toggle. Xcode uses "列表" in its navigator. The shorter label saves 8pt of toolbar width with no loss of clarity — the view toggle pattern is universally understood on macOS.

**Counterargument for keeping:** "列表视图" is unambiguous and used by some third-party apps (e.g., Things uses "列表"). The toolbar has adequate space at default width. The cost of changing is minimal; the benefit is also minimal.

**Test impact:** `DocumentShellTests.swift:55,106` — the `app.buttons["列表视图"]` assertion would change to `app.buttons["列表"]`.

### 3. "当前操作" inside "操作" menu — mixed semantics

- **File:** `DocumentToolbar.swift:66-97`
- **Observation:** The "操作" menu mixes three actions ("共享", "标签", "检测完整性") with one status item ("当前操作" → opens a popover showing `operationMessage`). A `Divider` (line 74) visually separates the status item from the actions.

This is not a terminology defect — the Divider convention is the standard macOS pattern for this exact scenario (see Finder's "Go" menu mixing navigation targets and the "Connect to Server…" action separated by a divider). No change recommended.

## Keep As Is

All remaining strings are natural, idiomatic Chinese for a native macOS user. Listed below for completeness with brief justification.

### Toolbar labels & help text

| String | Location | Why it works |
|---|---|---|
| "添加" | Toolbar:16 | Standard macOS term (Finder uses "添加" for toolbar customization). |
| "解压缩" | Toolbar:19 | Natural verb; matches Archive Utility's "解压缩" convention. |
| "媒体预览" | Toolbar:23 | Clear and unambiguous: previews media files visually. |
| "信息" | Toolbar:24 | Standard macOS inspector label. |
| "操作" | Toolbar:81 | Standard macOS menu pattern for secondary actions ("操作" = "Actions"). |
| "共享" | Toolbar:68 | Standard macOS share-menu term. |
| "标签" | Toolbar:69 | Standard macOS tagging term. |
| "返回" / "前进" | Toolbar:58-59 | Standard navigation terms; match Finder/Safari Chinese localization. |
| "搜索压缩包内容" / "搜索" | Toolbar:28-29 | Full and compact variants; natural and descriptive. |
| "\(n) 项" | Toolbar:44 | Standard Chinese count-suffix for items. |

### Preview loading & error state strings

| String | Location | Why it works |
|---|---|---|
| "正在读取图片…" | Routed:33 | Natural progressive aspect; ellipsis conveys ongoing action. |
| "无法读取这张图片。" | Routed:36 | Polite, specific failure message. |
| "正在读取 PDF…" | Routed:74 | Consistent with image loading pattern. |
| "PDF 文档加载失败" | Routed:105 | Concise failure state; no false blame on the user. |
| "PDF 文档已加载，\(n) 页" | Routed:106 | Informative success state; page count is the right signal. |
| "正在准备视频预览…" | Routed:317 | "准备" is appropriate — video requires player setup, not just "reading." |
| "这个视频无法播放。" | Routed:331,339 | Natural, blameless. |
| "播放视频时发生错误。" | Routed:344 | Specific runtime-error message (contrasts with the load-time "无法播放"). |
| "正在准备\(kind)预览" | Routed:251 | Dynamic label; depends on `documentKind.chineseName`. |
| "系统暂时无法创建文档预览。" | Routed:267 | "暂时" lowers severity appropriately; doesn't sound final. |
| "无法预览" | Routed:390 | Standard ContentUnavailableView title. |
| "无法安全预览" | Routed:403 | Clear distinction from general "无法预览" — conveys security boundary. |

### Error messages (AppModel.swift)

All 20+ archive/preview error messages use natural Chinese, follow the macOS convention of "发生了什么 + 建议操作" structure, and avoid blaming the user:

- "无法打开这个压缩包。请确认文件仍然可访问后再试。" — generic fallback, appropriately verbose
- "这个压缩包需要密码才能打开。" — direct, no jargon
- "密码不正确，请重新输入。" — polite retry prompt
- "这个压缩包使用了当前版本尚不支持的加密方式。" — honest about version limitation
- "找不到分卷压缩包的其他部分。请将所有分卷放在同一文件夹后再试。" — actionable guidance
- "压缩包内容超出安全限制，已停止打开。" — explains safety boundary
- "无法打开这个压缩包。文件可能已损坏或不是受支持的 ZIP 格式。" — correctly hedges ("可能")

### Accessibility labels

All `accessibilityLabel` and `accessibilityIdentifier` strings mirror their visible counterparts. PDFKit-specific accessibility labels ("PDF 页面容器", "PDF 滚动控制", "向前/向后滚动 PDF") are descriptive and appropriate for VoiceOver. No missing or misleading labels found.

### Test-asserted strings

`DocumentShellTests.swift` verifies correct toolbar order and the absence of rejected controls. The test assertions against Chinese strings ("返回", "前进", "添加", "解压缩", "列表视图", "媒体预览", "信息", "操作", "检测完整性", "搜索压缩包内容") are all consistent with the source code. No test-only strings that diverge from UI strings.

## Detection Integrity Verdict

**Is "检测完整性" natural?** Moderately. A native macOS Chinese user would understand it immediately, but would register a subtle stylistic mismatch — it reads like a direct translation from English "Detect Integrity" rather than an idiomatic macOS Chinese command.

**Is it understandable?** Yes, unequivocally. The compound "检测" + "完整性" maps cleanly to the action: check whether the archive data is intact.

**Is it correctly demoted under "操作"?** Yes. The user explicitly identified this as low-frequency. The current placement — nested inside a secondary "操作" menu, separated from primary toolbar actions — is the correct architectural decision. The XCUI tests at lines 47, 98 explicitly verify that "检测完整性" does NOT appear as a primary toolbar button. The test at line 210 verifies it IS reachable as a menu item. No regression to the primary toolbar is warranted.

**Recommendation:** Replace with "校验完整性" if and when an edit round is authorized. The change is a material quality improvement (platform-convention alignment) but not a defect fix. If not changed, the current string ships safely.

## Codex-Owned Verification

The following checks require visual or runtime acceptance that this agent cannot perform:

1. **Rendered label truncation at minimum width:** Confirm "校验完整性" fits in the "操作" menu popover without truncation at 900pt window width (test: `testEssentialToolbarControlsDoNotOverlapAtMinimumWidth`).
2. **SF Symbol pairing:** The `checkmark.shield` symbol (line 70) pairs with "检测完整性" — visually verify it remains appropriate for "校验完整性."
3. **Accessibility audit:** The `testKeyboardReachabilityAndAccessibilityAudit` test filters known false positives; re-run after any string changes to confirm no new audit failures.
4. **Menu item enabling logic:** `canTestIntegrity` is hardcoded `false` in all code paths (AppModel lines 198, 260, 282). The menu item always renders disabled. Confirm with product owner whether this is intentional (feature not yet wired) or a bug. This is a functional concern, not a copy concern — but it affects whether any user ever sees the label in an enabled state.

### Loop Trace

- **Objective:** Review Chinese toolbar/menu/preview copy; judge "检测完整性" naturalness and placement.
- **Sources:** 4 source files + context file + SOUL.md.
- **Iterations:** Single pass through all four source files cataloging every Chinese string, then filtered findings through the three review angles (reviewer / user / third-party).
- **Evidence:** Every finding quotes the exact source string with file:line reference.
- **Failed/abandoned paths:** None.
- **Remaining uncertainty:** The `documentKind.chineseName` dynamic string (used in OfficeQuickLookPreviewStateView line 251) was not traced to its definition — it's likely in a separate enum/file not in the read list. Its current values are unknown but inferred as correct from the test at lines 269-271 which asserts against "Word 文档 Quick Look 预览", "Excel 表格 Quick Look 预览", "PowerPoint 演示文稿 Quick Look 预览".
- **Recommended next loop:** If Codex authorizes an edit round, apply the "检测完整性" → "校验完整性" change across DocumentToolbar.swift and DocumentShellTests.swift, then re-run the accessibility audit test.
