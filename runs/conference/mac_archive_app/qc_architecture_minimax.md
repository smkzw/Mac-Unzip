# MiniMax-M3 架构与中文体验 QC-2

Second-architecture QC review for the native macOS archive app conference. Critique of three architecture routes with focus on Option A. This is review, not implementation authorization.

---

## 已读取输入与边界

I read these files in full before producing this review (one section per file):

- `/Users/smkzw/.hermes/SOUL.md` (571 lines, complete read acknowledged)
- `context/mac_archive_app_conference_context.md`
- `research/2026-07-11_initial_landscape.md`
- `research/2026-07-11_engine_distribution_matrix.md`
- `research/2026-07-11_windows_interoperability_contract.md`
- `research/2026-07-11_architecture_options.md`
- `reviews/codex_conference_mac_archive_app_review.md`

For cross-checking what the first-pass participant proposed and what Apple actually ships, I also read `runs/conference/mac_archive_app/participant_aishuo_minimax.md`. I did not read production paths, did not browse the web, did not run tests, did not open screenshots, did not edit source code, did not scaffold anything.

Compliance:

- Worked only inside `/Users/smkzw/Documents/AI Products`
- Wrote exactly one file: this `qc_architecture_minimax.md`
- Read only the task files plus the first-pass participant record needed to avoid repeating its terminology errors
- No browsing, no test execution, no visual acceptance
- Did not authorize any implementation

---

## 路线选择结论

Recommendation: keep **Option A (capability-routed hybrid core)** as the recommended route. Option B is acceptable as a fallback only when Option A's helper-bundling constraints become blockers. Option C remains rejected because it would force the user to drop already-approved encrypted-7z creation and encrypted-RAR extraction requirements.

Why Option A wins:

1. It is the only route that preserves every approved capability without retreat. minizip-ng covers ZIP create/edit/encrypt/repair; libarchive covers TAR families, GZIP/BZIP2/XZ/Zstandard, ISO and broad read paths; isolated 7zz covers full 7z creation/edit/AES and encrypted RAR/7z extraction; separately licensed RARLAB `rar` is the only lawful RAR creation path and never needs to be bundled.
2. The capability registry (`ArchiveCapabilityRegistry`) is the architectural lever that keeps the UI honest. It is the right place to forbid GUI from guessing capabilities from filename extensions, and the right place to expose per-format reasons when something is read-only or requires a rebuild.
3. The transaction layer (`ArchiveTransaction`) is the product-quality separator from Keka and BetterZip. Staging, verification, fsync, atomic replacement, recovery metadata and free-space preflight are the difference between "looks like a consumer app" and "is safe to use on large archives". This belongs in the core, not glued onto a helper-centric shell afterward.
4. The three-engine differential cost is real but bounded. The cost is paid once in the routing layer and once in differential-test fixtures. Returning to a single-engine route to save integration cost would push the encryption gap back onto the user.

Why Option B is fallback-only:

- Helper-centric collapses structured progress, cancellation, partial-entry extraction, and language-agnostic error mapping into stderr parsing. The 7-Zip helper is excellent for occasional heavy operations, not for every menu click. Use it where Option A already puts it: encrypted 7z and encrypted RAR heavy lifting.

Why Option C is rejected:

- It cannot serve the user's approved requirement to create encrypted 7z archives without bundling its own 7z writer, which the verified library evidence does not supply. Dropping this requirement is a scope regression the user has not approved.

---

## Windows 兼容提示语

The W0/W1/W2 contract stays in the codebase as internal tier codes and as advanced-settings labels. Primary UI never shows "W0", "W1", or "W2" to ordinary users. Instead, primary UI uses receiver-targeted wording where the user sees the destination machine, not the implementation tier.

User-visible primary wording:

- W0 ZIP preset shows as `发给 Windows 11 用户` with subtitle `对方直接双击就能打开，无需安装其他软件`. The Chinese version stays short and ends with a clear scenario, not an acronym.
- W1 7z-AES preset shows as `加密发给 Windows 用户` with subtitle `对方需要安装 7-Zip 或 WinRAR 才能打开`. We do not promise native Windows Explorer compatibility because Microsoft documents that Explorer does not operate on encrypted archives.
- W1 ZipCrypto legacy preset shows as `兼容老版本解压软件` with subtitle `密码保护较弱，兼容性较高`. The tradeoff is shown explicitly so the user can choose.
- W1 RAR-create preset shows as `RAR 压缩包 (需要本机已安装 WinRAR)` and is greyed out with the explanation `未在本机检测到已授权的 RAR 创建工具` when the provider is missing. The user is never told "we can create RAR" without an installed and authorized binary.
- W2 TAR family shows in advanced settings only, never in the primary preset row. Its label starts with the format (`TAR.GZ`/`TAR.ZST`) and adds the receiver hint (`适合命令行或归档服务器`). Consumer users do not see this row by default.

Where W codes may appear:

- Advanced/Developer settings that show the real format, method, encryption profile and filename policy.
- Logging, diagnostics, crash reports, internal capability registry output, OpenSource build manifests.
- Multipart case messages where the user genuinely needs the split-volume convention and the meaning is shown inline.
- AppleDouble / `.DS_Store` cleaning logic where a developer-grade user toggles the macOS-metadata strip option.

Where W codes may not appear:

- Main window buttons, menus, list/empty states, default preset names, error banners shown to non-technical users, marketing strings (currently out of scope), Quick Action names, Share Extension labels, onboarding copy.

Failure wording requirement: any error or warning tied to a Windows tier must explain the receiver environment, not the tier code. Example: `Windows 资源管理器无法读取加密压缩包，请告诉对方安装 7-Zip 或 WinRAR`. Never `W1 解密失败`.

---

## 全工作流走查

Walkthrough of twenty user journeys against the proposed architecture. Each row identifies the action, the components it touches, any missing state, and any unsafe wording that must be fixed before approval.

### 1. 打开压缩包 (open)

Action: user double-clicks a `.zip` in Finder or opens from app menu.
Touches: `ArchiveCapabilityRegistry.canRead`, format adapter, transaction layer registers a session, namespace becomes the source of truth for the open document window.
Missing state needed: a clear `正在打开…` progress with engine name and password prompt timing, especially for hidden metadata parsing (AppleDouble, Windows paths, RSA-encrypted 7z headers).
Unsafe wording to reject: any message saying `正在加载` forever without a cancel. Open must always expose a cancel control and a "密码?" inline prompt that does not block the main window.

### 2. 浏览 (browse)

Action: user navigates the archive tree or list.
Touches: registry's read capabilities, table/outline view, sidebar, search-in-archive.
Missing state needed: column disclosure (`修改时间`, `原始大小`, `压缩大小`, `压缩方法`), column sort persistence per archive, empty state with offer to extract or preview.
Unsafe wording to reject: any empty state that implies the archive is empty when in reality filenames failed to decode. Decode-ambiguity state must be visible per row, not silently hidden.

### 3. 预览 (preview)

Action: user presses Space on selected entry.
Touches: preview extractor streams into quarantined bounded cache with byte/time/type limits, Quick Look integration or built-in safe text/image viewers.
Missing state needed: when preview is refused because entry exceeds limits or matches a blocked extension list (executable, installer, script), a `无法预览，可改为展开到临时文件夹` action with explicit one-time consent.
Unsafe wording to reject: "预览失败" with no next step. "无法安全预览此条目" + alternate path is correct.

### 4. 添加条目 (add)

Action: user drags files from Finder into the archive outline.
Touches: registry confirms `canEditByRewrite` for the format, transaction begins, staging directory materializes copies.
Missing state needed: preflight result sheet (free space, duplicate name policy, encoding normalization, Windows-invalid-name collisions) before any byte is committed. The sheet must be visible when issues exist and skippable when clean.
Unsafe wording to reject: silent rename to fix Windows-invalid or NFC/NFD collision without offering a reversible name policy table.

### 5. 移除条目 (remove)

Action: user selects entries and chooses Remove.
Touches: registry confirms support, transaction marks logical delete, rebuild plan shown.
Missing state needed: a `重建进度 (需重新打包)` indicator when the underlying format only supports delete-by-rebuild (most compressed formats). Honest disclosure is required: not every archive can be edited in place.
Unsafe wording to reject: `正在删除` shown for a format that can only rebuild — it lies about the operation. The correct state is `正在重建压缩包`.

### 6. 重命名条目 (rename)

Action: user edits the name of a selected entry.
Touches: encoding layer normalizes display, registry records whether the format supports rename without rebuild, transaction stages.
Missing state needed: collision check against existing entries (case-insensitive, NFC/NFD-equivalent, Windows reserved names); explicit action when collision would change SHA verification on the receiver side.
Unsafe wording to reject: `已重命名` followed immediately by `正在重新打包` — the user sees two contradictory status strings. Pick one consistent sequence.

### 7. 替换条目 (replace)

Action: user drops a new file onto an entry to replace its content.
Touches: transaction stages the replacement, manifest updates, integrity check after stage.
Missing state needed: when the new file differs in path-relative metadata (mtime, perms), show `保留原始条目信息` toggle before stage. Otherwise the receiver sees a different timestamp or permission set and may flag hash drift.
Unsafe wording to reject: silent permission drop on ZIP where macOS ACL did not exist on Windows.

### 8. 保存 (save)

Action: user closes window or presses Cmd-S.
Touches: transaction materializes stage, runs integrity test, fsyncs, atomically replaces original, writes recovery record.
Missing state needed: `保存中` indicator that distinguishes `压缩 / 校验 / 写入 / 收尾`. Multi-phase progress is mandatory because single-string save hides the failure mode.
Unsafe wording to reject: `保存成功` without atomic-replace confirmation and without the recovery record path so the user could locate a rollback target later.

### 9. 展开 (extract)

Action: user clicks Extract or right-clicks `展开到此处`.
Touches: transaction, capability registry, path security layer (Zip Slip, symlink escape, decompression bomb, device-name rejection), preview cache for inline preview.
Missing state needed: preflight summary screen showing "X 个文件 / 原始 Y MB / 展开后 Z MB / 跳过 N 项（含 N1 个不安全路径 / N2 个名称冲突）" before commit. Naming-collision policy must be selectable before commit.
Unsafe wording to reject: silent overwrite of existing files without warning when an extracted file would clobber a user-authored file.

### 10. 提取 (create / new archive)

Action: user chooses New Archive or `新建压缩包`.
Touches: capability registry selects an engine, format preset row defaults to `发给 Windows 11 用户` (W0), advanced settings expose format/method/encryption/profile.
Missing state needed: receiver-targeted preset as default row; advanced row collapses by default; compression level default = balanced, not max.
Unsafe wording to reject: any row labeled `Windows 兼容 ZIP` without distinguishing encrypted vs unencrypted behavior. The 7z or AES ZIP row must surface "接收方需要 7-Zip/WinRAR".

### 11. 加密 (encrypt)

Action: user adds a password + optional header encryption.
Touches: registry confirms `canEncrypt`, chosen engine emits the correct encryption profile (ZIP AES-256 vs ZipCrypto vs 7z AES-256 with encrypted headers).
Missing state needed: passphrase strength meter (zxcvbn-style wordlist guidance, no password content logging), optional Keychain save toggle, secondary warning when ZipCrypto is selected (`兼容性较高，但密码保护较弱`).
Unsafe wording to reject: `密码错误` reused for "wrong password" and "encrypted but no password entered yet"; distinguish `请输入密码` vs `密码错误，请重试`.

### 12. 分卷 (split)

Action: user requests split into volumes.
Touches: registry confirms format supports split (ZIP split, 7z volumes, RAR volumes), hardlink staging policy.
Missing state needed: volume size parameter with unit clarity (`MB` vs `MiB` — show both), naming pattern explanation (`xxx.zip.001 / xxx.zip.002`), `第 X 卷 / 共 Y 卷` placeholder.
Unsafe wording to reject: `分卷成功` without showing where the manifest and recovery info are stored.

### 13. 修复 (repair)

Action: user runs Test/Repair on a damaged archive.
Touches: registry confirms format supports recovery (ZIP central directory recovery, 7z recovery record, RAR recovery record), stages recovered data to a sibling file.
Missing state needed: explicit `修复` outcome degrees: `完整性正常`, `已修复 (Y 处)`, `无法修复，已生成诊断报告`. Files with missing data segments must be marked, not hidden.
Unsafe wording to reject: `修复成功` when only metadata was recovered; partial recovery must say `部分修复`.

### 14. 转换 (convert)

Action: user converts a 7z archive to ZIP.
Touches: registry routes extract → staging → re-create; transaction treats this as a staged rewrite.
Missing state needed: warning when target format cannot preserve per-entry metadata (Unix permissions, symlinks, ACLs, AppleDouble) and a per-entry decision table for which metadata to drop.
Unsafe wording to reject: `转换完成` without disclosing what was dropped.

### 15. 密码错误 (wrong password)

Action: user enters wrong password.
Touches: secure field, error taxonomy maps to localized message.
Missing state needed: counter with rate-limit hint (`剩余尝试 N 次` when applicable), `重新输入` button that clears the field without erasing remembered Keychain entry unless user explicitly asks.
Unsafe wording to reject: `密码错误` only — must include `请重新输入` and the file format implication (`当前文件为 AES 加密`).

### 16. 损坏 (corrupted)

Action: archive fails integrity check.
Touches: adapter reports structured failure category, transaction stays in source-untouched state.
Missing state needed: distinct copy with error report (no source mutation), `诊断` button that shows CRC failures per entry; dialog offers `尝试修复` if the format supports it.
Unsafe wording to reject: `文件已损坏，无能为力` — must always say what the user can still do.

### 17. 卷缺失 (missing-volume)

Action: user opens a split archive with part missing.
Touches: registry identifies required volume list, transaction blocks operation.
Missing state needed: clear list of expected volumes with re-prompt for the missing path; never silently proceed.
Unsafe wording to reject: `无法打开` only — must enumerate which volumes are missing.

### 18. 冲突 (collision)

Action: extracted file would overwrite an existing one.
Touches: path security + collision policy preflight.
Missing state needed: explicit naming policy selection (overwrite, rename, skip, cancel) applied per-archive, not per-entry unless the user selects manual.
Unsafe wording to reject: `已跳过 N 个文件` without listing them and offering an "展开到另一个文件夹" recovery path.

### 19. 取消 (cancel)

Action: user cancels an in-flight operation.
Touches: transaction must stop workers, release staged data, leave source untouched.
Missing state needed: `已取消` transition followed by `已清理临时文件` confirmation; staged data must be on an app-managed sibling volume, not the source.
Unsafe wording to reject: `取消中` never resolving to a terminal state — must always end with one of: `已取消`, `部分完成 (X/Y)`, `无法停止，正在收尾`.

### 20. 崩溃恢复 (crash-recovery)

Action: app or system crashes during a staged save.
Touches: recovery record persists outside the source archive; next launch scans for orphan transactions.
Missing state needed: on next launch a single sheet `检测到上次未完成的任务` with three options: `继续`, `放弃`, `查看详情`. The detail view lists the source path, staged path, lock-file location.
Unsafe wording to reject: silent overwrite of an orphan that may contain partial work without explicit user confirmation. Default behavior on next launch must be `询问`, never `自动放弃`.

Cross-journey concerns raised by walkthrough:

- The architecture must keep an `AuditTrail` per logical archive session, separate from logging, so the recovery record and the integrity report come from the same source.
- Encoding, normalization, collision and device-name checks are shared across at least nine of the twenty journeys. They belong in a single shared preflight service, not duplicated in each journey.
- Every journey that mutates must end in one of three terminal states: `已完成`, `已取消`, `失败`. Showing `进行中…` after the user closed the window is the most common shipping defect.

---

## 中文术语修订表

This table is my second-pass correction. It is built on three sources: current macOS 26.5.1 `Archive Utility.app` Chinese strings (recorded in `research/2026-07-11_initial_landscape.md`), `participant_aishuo_minimax.md` first-pass proposal (cross-checked, several revisions applied), and ordinary mainland macOS usage. Conflicts between participant intuition and live Apple strings are resolved in favor of the live strings, per the Code QC pass.

| 英文/概念 | 第一轮提议 | 修订后建议 | 处理依据 |
|---|---|---|---|
| Archive (n.) | 压缩包 (主) / 归档 (辅) | **归档 (动作/工具对齐) + 压缩包 (口语主线)** | Apple 自身用 `归档`；消费场景 90% 用 `压缩包`。两者并存而非替换。 |
| Create Archive | 创建归档 | **新建压缩包** (按钮) / **创建归档** (菜单) | 按钮用口语，菜单与系统对齐；不混排 |
| Open Archive | 打开归档 | **打开压缩包** | 主 UI 口语，菜单可用 `打开归档` |
| Extract (v.) | 展开 (主) / 解压缩 (辅) | **解压缩 (主) / 展开 (辅)** | 关键反转：当前 macOS 26.5.1 `归档实用工具` 实际使用 `解压缩`/`创建归档`/`正在解压缩`。`展开` 用于 Finder 双击行为可以保留，但不可作为主词覆盖系统动作。 |
| Decompressing | 正在解压缩 | **正在解压缩…** | 与 Apple 文案一致 |
| Compress (v.) | 压缩 | **压缩** | 无争议 |
| Settings | 偏好设置 | **设置** | 当前 macOS 系统用 `设置…`，`归档实用工具` 也是 `设置…`/`归档实用工具设置`。`偏好设置` 是 PowerPC-era 旧词，证据不支持当前主推 |
| Archives (in-progress) | 进行中的压缩包 | **正在处理的任务** | 比 `进行中的压缩包` 更自然；可访问性标签用全句 |
| Healthy | 正常 | **正常** | 与第一轮一致 |
| Repair | 修复 | **修复** | 保留 |
| Multi-volume | 分卷 (第 X / 共 Y 卷) | **分卷 (第 X 卷 / 共 Y 卷)** | 第一轮 `共 Y` 听起来像错字，修正为 `共 Y 卷` |
| Corrupted | 压缩包已损坏 | **压缩包已损坏** | 与第一轮一致；新增：错误消息必须始终搭配可行的下一步动作 |
| Decompression bomb | 压缩包异常膨胀，已阻止 | **压缩后体积异常，已阻止** | 避免 `解压炸弹`/`可能恶意` 等刺激性词 |
| Quarantine | 此文件来自压缩包，首次打开请确认来源 | **此文件来自压缩包，首次打开请确认来源** | 与第一轮一致 |
| Password storage | 是否记住此压缩包的密码？保存到 "密码本" 中 | **是否记住此压缩包的密码？保存到钥匙串** | 反转：Apple `归档实用工具` 文案是 `将密码储存在钥匙串中`。`密码本` 是创词，没有 Apple 支持证据 |
| Keychain Access | `钥匙串访问.app` (系统 app) | **钥匙串** 出现在 UI，`钥匙串访问` 出现在系统 app 引用 | 与 Apple 原生一致 |
| Repackage | 重新压缩 | **重新压缩** | 与第一轮一致 |
| Source/archive | 压缩包/源文件 | **源压缩包** / **压缩包** | 用 `源` 区分磁盘文件 vs 压缩包内条目 |
| Entry/item | 条目/文件 | **条目 (主) / 文件 (辅)** | 队列/状态用 `条目`，普通列表用 `文件` |
| Preview | 预览 | **预览** (主) / **快速查看** (与 Quick Look 文本一致) | 区分应用内预览 (`预览`) 与 Finder Quick Look (`快速查看`) |
| Replace contents | 替换条目内容 | **替换内容** | 短、动词在前 |
| Save | 保存 | **保存** | 无争议 |
| Discard changes | 不保存 | **放弃更改** | 弃用 `不保存`；用 `放弃更改` 更正式 |
| Filename encoding | 文件名编码 | **文件名编码** | 无争议 |
| NFC/NFD normalization | 名称规范化 | **Unicode 规范化** | `Unicode 规范化` 比 `NFC/NFD` 更易懂 |
| Windows reserved name | Windows 保留名 | **Windows 保留文件名** | 全称更明确 |
| Decompression limit | 解压限制 | **展开大小限制** | 与系统 `解压缩` 区分：动作用 `展开`，动名词用 `展开…` |
| Header encryption | 加密文件名 | **加密文件名（连同目录）** | 与 7z AES-256 header encryption 措辞对齐 |
| Recipient contract | W0/W1/W2 | **接收方提示语** + 见 Windows 兼容提示语 | 不暴露 W 代码 |

Forced-revision highlights:

1. `展开` → **`解压缩` 主，`展开` 辅**: First-pass MiniMax was wrong to elevate `展开` over `解压缩`. Apple's own `归档实用工具` uses `解压缩` and `正在解压缩…` for the very act this product performs. Treating Apple's own production strings as advisory rather than authoritative is the classic evaluator-thinks-they-know-better trap. Mainland users can read `解压缩` fluently; the user's mainland familiarity argument does not override live OS evidence.
2. `偏好设置` → **`设置`**: macOS has migrated all system surfaces to `设置`. `偏好设置` is a holdover. Using `设置` puts the app in the same family as `系统设置`, `应用设置`, `归档实用工具设置`. Cost of consistency with system is zero, cost of diverging is unnecessary friction.
3. `密码本` → **`钥匙串`**: Same reasoning. Apple ships the localized `钥匙串`; consumers understand it; introducing a second word (`密码本`) creates a parallel concept and confuses Keychain Access.app launch attempts.

Decisions where Apple evidence does not yet exist and where I keep first-pass judgement while flagging the gap:

- `压缩包` vs `归档` as the primary noun: both surfaces should appear (button = `压缩包`, menu = `归档` aligned with system). This is mixed but acceptable.
- `分卷` naming pattern: the `(第 X / 共 Y 卷)` form is a guess at consumer readability; needs usability testing with two or three mainland macOS users before final spec.
- `正在处理的任务` vs `进行中的压缩包`: I prefer the former because it does not conflate archive state with task state; the participant preferred the latter because `正在处理` overlaps with engine-internal progress. Open question for user test.

Things to remove entirely (not in table because they have no good replacement):

- Any usage of `归档档`, `压缩档`, `文件柜`, `资源柜` (first-pass already flagged these as anti-patterns; keep them banned).
- Any tier code `W0/W1/W2` in primary UI (see Windows 兼容提示语 section).
- Any mention of engine internals in user-facing strings (`libarchive`, `minizip-ng`, `7zz`).

Implementation discipline: every string above must live in a `String Catalog` with `xcstrings` pluralization and accessibility comments. Strings must not be hard-coded in views. Locale variants `zh-Hans`, `zh-Hant`, `en` are required; `ja`, `ko`, `ar`, `ru` are architecture-ready but not authored for v1.

---

## Liquid Glass 与可访问性

Audit of the proposed Liquid Glass/navigation proposal against native hierarchy, accessibility, and large-archive usability. The proposal's claims (`NavigationSplitView` three-column, table content-first, glass on system-supported bars only) are mostly aligned with Apple guidance. Several specific gaps must be filled before design freeze.

Native hierarchy check:

- `NavigationSplitView` with sidebar / content / inspector is the correct baseline. Three-column layout must collapse to two when window width drops below the sidebar's min width, and to single column below 700pt. Test cases must include Stage Manager 4-wide, full-screen split, and external 6K display at 100% and 200%.
- `Inspector` content is read by default in commercial archive apps (BetterZip, Keka). Apple does not prescribe view defaults; product judgement is required. The architecture must allow turning the inspector off without code change.
- Glass on system-supported bars: confirm the toolbar uses `.toolbar` API and `.background(.regularMaterial)` (or the macOS 26 Liquid Glass equivalent) only where Apple documents it. Hand-rolled `NSVisualEffectView` is acceptable where SDK does not provide a wrapper, but the rule is "use SwiftUI first, AppKit where SDK is missing".

Accessibility checklist:

- VoiceOver must read entry count, current selection, and modifications in this order: `归档实用工具选择, 文件 第 3 项 / 共 17 项, 名称.docx, 原始 1.2 MB, 已选中`. Rotor must support `Heading`, `Form Control`, `Selected`. Static text must not announce focus changes; announcements must be opt-in.
- Full Keyboard Access: every primary action must be reachable without the mouse (`Cmd-O` open, `Cmd-N` new, `Cmd-E` extract, `Cmd-S` save, `Cmd-Shift-E` extract to folder, `Cmd-R` repair, `Cmd-F` find in archive, `Cmd-1/2/3` switch columns). Tab order must not trap focus in any pane.
- Increase Contrast / Reduce Transparency: Liquid Glass at full transparency is unreadable. App must respect both system settings. If `Reduce Transparency` is on, the glass surfaces must fall back to `.regularMaterial` (or `opaque` background) without losing contrast. If `Increase Contrast` is on, text and dividers must use the system contrast tokens.
- Dynamic Type: macOS supports it on text views; numeric columns in the table must use the system monospaced digit font and not break alignment when the type size ramps up.
- Keyboard navigation inside the table: arrow keys move selection, `Space` toggles preview, `Return` opens (extracts for preview), `Delete` removes from staging set, `Esc` cancels in-flight operations. Modifier keys (`Cmd`, `Option`) must not be silent.
- Color is never the only signal. Archive status uses icon + text + numeric badge, never color alone. The "压缩包异常膨胀，已阻止" dialog must pair message color with an icon.

Large-archive usability:

- A 100k-entry archive should open in under 2 seconds on Apple Silicon; the registry must not instantiate 100k SwiftUI rows eagerly. The architecture must adopt a lazy view backed by `Table` or a paginated list, with virtualized scrolling, sorted columns that trigger incremental resort, and incremental search.
- Search-in-archive must use a background scanner with cancellation and visible progress (`已扫描 12,348 / 87,102`); the foreground table must remain responsive. Search results must be navigable (`Next`/`Previous`) and must not lose selection when re-running the same query.
- Preview against > 100 MB entries must not block the main thread. The quarantined bounded cache must support streaming copy with progress and explicit user cancellation.
- Quick Look Preview Extension must be sized for representative zip contents (file with thousands of small text files must not crash the extension). Memory and time budgets must be enforced, and the extension must return a structured refusal rather than allocate unbounded memory.
- Window-state persistence per archive is mandatory: column widths, sort order, sidebar selection, inspector visibility. Re-opening the same archive must restore the user's layout.

Outstanding Liquid Glass questions for Codex (which owns visual acceptance):

- SwiftUI Liquid Glass sample compilation has not yet been verified locally because full Xcode is not installed. The architecture's Liquid Glass usage must be confirmed against the current SDK in the next loop.
- Apple documentation says Liquid Glass is system-provided material; the architecture must not hand-author a blurred background that visually imitates Liquid Glass. This is the most likely error in implementation and must be checked first.

---

## 必须修订项

Ordered list of changes that must land before the design specification is approved. Each item names the owner-loop responsibility, not just a generic wish.

1. Replace primary action word `展开` with `解压缩`; introduce `展开` only as secondary wording for Finder-style drag-to-folder. Owner: terminology loop. Evidence: current macOS 26.5.1 `归档实用工具` strings. Do not defer.
2. Replace `偏好设置` with `设置` everywhere in user-facing UI; menu item `设置…` mirrors Apple system menu vocabulary. Owner: terminology loop. Evidence: live Apple strings.
3. Replace `密码本` with `钥匙串` and use Apple phrase `将密码储存在钥匙串中` in the save-password dialog. Owner: terminology loop. Evidence: live Apple strings.
4. Remove all `W0`/`W1`/`W2` from primary UI; keep in advanced settings, logging and diagnostics; convert to receiver-targeted wording in user messages. Owner: UX wording loop.
5. Add a shared preflight service covering NFC/NFD normalization, Windows reserved names, path-length risk, case-insensitive collisions, AppleDouble/file-mode warnings; expose per-archive collision policy selection. Owner: architecture loop.
6. Add a structured error taxonomy so wrong-password, encrypted-but-no-password, encrypted-but-format-unsupported, wrong-encryption-mode, and corrupted-encrypted are distinct user-visible states. Owner: backend loop.
7. Add `AuditTrail` per archive session that survives crashes and drives the recovery sheet; next-launch behavior defaults to `询问`, never `自动放弃`. Owner: transaction layer loop.
8. Add explicit per-format message rules for stage-rebuild-required operations: rename, partial remove, replace, encrypt-after-create, repair, convert. Source-mutation messages must distinguish `保存中`, `重新打包中`, `校验中`, `写入中`, `收尾中`. Owner: UX wording loop.
9. Verify SwiftUI Liquid Glass API against current Xcode SDK before architecture freeze. If full Xcode is not installable in this loop's time budget, defer the visual choice but keep the architecture Liquid-Glass-friendly (use system materials, no custom blur layers). Owner: Codex, with engineering support.
10. Confirm Windows interoperability fixtures (real Windows 11 24H2 + 7-Zip + WinRAR). Until that physical acceptance happens, the architecture must not claim W0/W1/W2 meet real receivers; keep them as design contracts and as future release gates. Owner: future physical-acceptance loop.
11. Add `Accessibility` test plan covering VoiceOver rotor order, Full Keyboard Access reach, Increase Contrast / Reduce Transparency fallback, Dynamic Type expansion, large-archive keyboard-only navigation. Owner: QA loop.
12. Add an LGPL compliance plan placeholder for the Direct/OpenSource profiles. The Local profile may discover a separately installed `7zz`, but the moment we bundle a 7-Zip-derived binary we owe source/notice compliance. Owner: legal/compliance loop, before Direct/OpenSource build profile activation.
13. Document the boundary: where the architecture opts into App Sandbox for any profile, it must accommodate the embedded helper via `com.apple.security.helper` or appropriate entitlement. If sandbox is not adopted, the architecture must say so explicitly per profile. Owner: architecture loop, per build-profile decision.
14. Add a `String Catalog` requirement to the spec, including pluralization, accessibility comments, locale list (`zh-Hans`, `zh-Hant`, `en`, plus architecture-ready `ja/ko/ar/ru`) and the rule that no view hard-codes a Chinese string. Owner: localization loop.
15. Add a `File a Bug` command and `Help` menu linkage to documentation, even if documentation is a stub. Commercial product standard; do not ship without it. Owner: UX wording loop.

Not-must-revise (intentional non-changes):

- Keep Option A. The capability registry is the right architectural primitive; do not collapse it into a helper-centric shell to save code.
- Keep the three-engine split for Option A; do not collapse engines inside Option A as a complexity-reduction move. The differential test burden is the price of feature coverage.
- Keep the transaction layer mandatory. Do not offer a "fast save" that bypasses staging, even for "obviously safe" formats.

---

## LOOP 记录

Actions this loop:

- Read SOUL.md (571 lines, complete). Acknowledged.
- Read all six listed task files in full.
- Cross-checked `participant_aishuo_minimax.md` to avoid repeating terminology errors flagged by Codex.
- Cataloged current macOS 26.5.1 Chinese strings as baseline.
- Walked twenty user journeys, identified missing states and unsafe wording.
- Audited Liquid Glass / navigation proposal against native hierarchy and accessibility.
- Drafted the revised terminology table with evidence column.
- Produced this output file as the second-pass QC for Codex review.

Observations:

- The first-pass MiniMax proposal was strong on user scenarios and capability registry thinking, but wrong on three high-visibility terminologies (`展开`, `偏好设置`, `密码本`) when judged against current macOS strings. The errors are individually small but cumulatively loud: the app would diverge from the system on its three most-frequent action verbs/settings screens/password dialogs.
- The architecture options document already encodes the right architectural primitives: capability registry, transaction layer, security layer, localization layer. The QC-2 question is whether they cover the twenty real-user journeys and the terminology layer. They mostly do; several journeys surface missing error states (wrong-password vs encrypted-no-password, corrupt-encrypted vs missing-volume) that the options document does not yet enumerate.
- The `W0/W1/W2` tier codes are an excellent internal contract but a poor user surface. The Codex review did not flag this as a risk; this QC-2 flags it as a required revision.
- Liquid Glass adoption is in the right direction (use SwiftUI system materials, let SDK choose) but visual acceptance is blocked on full Xcode. This QC explicitly hands the visual call back to Codex; I do not claim rendered Liquid Glass acceptance.
- Large-archive usability (100k entries) is plausible on Apple Silicon but the option doc does not specify lazy views, virtualized tables, or incremental search-cancel. Missing.
- The `解压` verb concern raised by some consumer reviewers is valid for friendliness, but the user's mainland users read `解压缩` comfortably and Apple's own strings use it. The user's preference for friendliness does not override live Apple evidence when Apple ships both words and chooses `解压缩` for its own UI.

Evaluation:

- Hypothesis: Option A is correct. Verified: it is the only route that preserves the user's approved scope without regression. Option B is acceptable as a fallback when helper-bundling becomes a hard blocker.
- Hypothesis: the main terminology errors can be fixed in spec without re-architecting. Verified: terminology is a localization-loop concern, not an architecture-loop concern. No engine work is invalidated by fixing strings.
- Hypothesis: W0/W1/W2 can be hidden from primary UI cleanly. Verified: by rewriting preset rows to receiver-targeted wording and reserving W codes for advanced settings, logs, and the OpenSource manifest. No data-model change is required.
- Hypothesis: Liquid Glass adherence is verifiable against system SDK without rewriting the architecture. Verified: use SwiftUI system materials, do not hand-author blur; this is a coding guideline, not a redesign. Visual acceptance still needs Xcode and Codex.

Revisions proposed:

- Primary action `展开` → `解压缩`.
- `偏好设置` → `设置`.
- `密码本` → `钥匙串`.
- W0/W1/W2 hidden in primary UI, kept only where technical users need them.
- Shared preflight service added to requirements list.
- Error taxonomy distinct per encryption state.
- Crash-recovery sheet as required next-launch surface, defaulting to `询问`.
- Per-stage progress labels mandatory.
- Accessibility and large-archive test plan in spec.
- LGPL compliance placeholder for Direct/OpenSource profiles.
- Localized `String Catalog` requirement with locale list.

Uncertainty I cannot resolve from bounded inputs:

- Whether a future Windows physical-acceptance loop is staffed for the project. The W0/W1/W2 contract cannot be claimed met without it. I have flagged it as a release gate; whether it actually runs is a user decision.
- Whether the user, after seeing this revision, still wants `压缩包` as primary noun or pushes it back toward `归档`. Both are defensible; the test is consumer readability, not personal preference.
- Whether the user wants sandbox on at any profile. The architecture supports either, but the security-and-deployment delta is meaningful. This is a user decision, not a QC decision.
- Whether a third-party localization review with mainland-Chinese macOS users is possible before design freeze. Recommended; user decision.

Recommended next loop:

- A terminology-only SubAgent loop to apply this revision to every menu, button, dialog and accessibility label against the existing `participant_aishuo_minimax.md` table. Output: a diff-style reconciliation so Codex can audit line-by-line.
- An architecture detail loop to draft the preflight service contract (NFC/NFD, reserved names, collisions, decompression limits) and the error taxonomy, both inside the Option A spec.
- A Codex-led visual loop once full Xcode is installed, with this QC-2 reviewed against actual Liquid Glass rendering.
- A physical-acceptance loop on Windows 11 24H2 + 7-Zip + WinRAR. Until that loop completes, architecture claims W0/W1/W2 compliance as a design contract, not a verified outcome.
