# Archive Workbench foundation acceptance

Evidence date: 2026-07-12 (Asia/Shanghai)
Base commit at proof start: `ab580694f2dd8fbc61f0854b5551070d038357c5`; the Task 8 UI/QC patch described below was then proved in the working tree before its acceptance commit.
Branch: `feature/archive-workbench-foundation`

## Acceptance decision and boundary

**Foundation accepted for provider-plan handoff.** This decision covers only the Task 1–7 foundation: reproducible native arm64 project, domain/capability value contracts, pure path/resource policies, actor scheduler, reviewed Finder-style document shell and preview-cache boundary, plus the non-hardened helper/password/7zz diagnostic spike.

This is **not** product or goal completion. No actual ZIP/minizip-ng, libarchive, production 7zz, RARLAB, DMG, ISO, Finder/Quick Look extension, transaction editor, physical-Windows interoperability, clean-machine install, performance, or complete archive-entry Office/video preview workflow is accepted here. The current document UI is a fixture shell; visible add/extract/menu affordances are not evidence that provider workflows exist.

## Evidence environment

| Item | Observed value |
|---|---|
| Host | macOS 26.5.1 (`25F80`), Apple silicon `arm64` |
| Xcode | 26.6 (`17F113`) |
| macOS SDK | 26.5 |
| Swift | Apple Swift 6.3.3, target `arm64-apple-macosx26.0` |
| XcodeGen | 2.45.4 |
| Fixed diagnostic 7zz | 7-Zip 26.02 arm64; SHA-256 `2f412eded2d37f2cc52f26138e6964bd205ea0bf2ee6a70b8b990a18107e784d` |

## Complete proof matrix

Every command below was rerun from this commit. Exit codes are from commands with `pipefail`; pass counts are copied from the fresh output, not prior reports.

### ArchiveKit normal package tests

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test
```

- Exit: `0`.
- Result: `34` tests in `1` Swift Testing suite passed.
- The command now works normally with the selected full-Xcode toolchain; the earlier CLT-only `Testing.framework` workaround is not needed.
- Post-QC captured log SHA-256: `54ad10fc74ce1fcb67d99d13c0e151fbb79bf95f785d1900b01648825d5af3f9`.

### Thread Sanitizer scheduler tests

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swift test --sanitize=thread --filter OperationSchedulerTests
```

- Exit: `0`.
- Result: `14` scheduler tests in `1` suite passed.
- No `WARNING: ThreadSanitizer`, `ThreadSanitizer: reported`, or `data race` match was emitted.
- Post-QC captured log SHA-256: `a1ef123056d0a2f541cbd92ac7507fc4358105925bd14a52b298da50f0bda9ff`.
- This is direct TSan evidence for the scheduler test surface; it is not a TSan claim for UI frameworks or future provider adapters.

### Clean full Xcode scheme

```bash
cd ArchiveWorkbench
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ArchiveWorkbench.xcodeproj \
  -scheme ArchiveWorkbench \
  -destination 'platform=macOS,arch=arm64' \
  clean test
```

- Exit: `0`; `** CLEAN SUCCEEDED **`; `** TEST SUCCEEDED **`.
- HelperSpike: `27` tests / `3` suites passed.
- App unit tests: `11` passed.
- App UI tests: `10` passed, including the new five-item media-strip edge-clipping regression.
- No `warning:` diagnostic was emitted. Xcode did emit its non-fatal `IDELaunchParametersSnapshot ... no debugger version` message while the committed test action used the intentional PosixSpawn launcher with debugging disabled; this was not hidden or counted as a compiler/build error.
- Result bundle: `~/Library/Developer/Xcode/DerivedData/ArchiveWorkbench-fmhilqkqawnrvbeaituiaddcquqz/Logs/Test/Run-ArchiveWorkbench-2026.07.12_02-46-26-+0800.xcresult`; `Info.plist` SHA-256 `bd092fa01105f2f3173a5d5bde6940c0131acf42b14329d6182a1eb2a786e079`.
- `xcresulttool` reports `48` tests across the three targets (`27` Helper + `11` unit + `10` UI), with `0` failures; dynamic parameter expansion reports `52` passed runs.
- Captured text-log SHA-256: `74c6ba72caf57817f5ace8f83536d6c7cfd8c1575be22bb0991af74845150db3`.

## Binary, signing, and bundle proof

The fresh Debug products were inspected directly.

| Artifact | `lipo` / `file` result | SHA-256 |
|---|---|---|
| `ArchiveWorkbench.app/Contents/MacOS/ArchiveWorkbench` | `arm64`; Mach-O 64-bit executable arm64 | `a6a61d91b051f30f6d451f6ccc016a343293e8898e28feaf25a777bd8ed71d4b` |
| `HelperSpike.framework/Versions/A/HelperSpike` | `arm64`; Mach-O 64-bit dynamically linked shared library arm64 | `7ddd61468d66eec535fb632f36de069b209514ae5c9482282e7fbff742d47713` |
| `HelperFixture` | `arm64`; Mach-O 64-bit executable arm64 | `3edd6448db901758650e3f6dc3c4b06c6e7cc606a568f72d893a78337bace8bb` |
| `LowFDHarness` | `arm64`; Mach-O 64-bit executable arm64 | `d953fffdc4b2eed66c57b7e4904b7e0f515bf0d4808e462cbe05910aa72c87d0` |

`codesign --verify --deep --strict --verbose=2` exited `0`; the app was valid on disk and satisfied its Designated Requirement. `codesign -d --verbose=4` reported identifier `com.smkzw.ArchiveWorkbench`, flags `0x10002(adhoc,runtime)`, ad-hoc signature, no team, and runtime version 26.5.0. This proves a hardened local ad-hoc build, not Developer ID signing or notarization.

The generated bundle declares display name `归档工作台`, identifier `com.smkzw.ArchiveWorkbench`, and minimum system 26.0. `Contents/MacOS` contains one app executable. Resources present after the clean test:

- `Contents/Resources/zh-Hans.lproj/Localizable.strings`, SHA-256 `af5b45c568cffa7375297ccc89592696196e64841fc4de93caf712b3287358d3`;
- `Contents/Resources/首页主视觉.png`, SHA-256 `783b38d37e3400791e1b43e21ca29bfbf94724a4a00b3aad43b95d3ed3b67377`.

## String Catalog and user-visible language evidence

```bash
jq empty App/Resources/Localizable.xcstrings
jq -r '.strings | keys[]' App/Resources/Localizable.xcstrings \
  | LC_ALL=C rg -c '^[[:ascii:]]+$'
rg -n 'Text\("[^"\n]*[A-Za-z][^"\n]*"\)|Button\("[^"\n]*[A-Za-z][^"\n]*"\)' \
  App/Sources
```

- String Catalog JSON validation exited `0`; post-QC source catalog SHA-256 `efbe697d2cc129b4ce3b91baaa3df3a6a6f1b47cbb8abd7e8d2788d2c63d347a`.
- ASCII-only catalog key count: `0`.
- The compiled Simplified-Chinese strings file contains the reviewed primary commands and help text, including `打开压缩包`, `创建归档`, `添加`, `解压缩`, `操作`, and `检测完整性`. MiniMax-M3 findings were applied by removing stale `更多`/unused integrity keys and tightening help/status copy; the explicit user decision keeps the short visible menu label `操作` rather than expanding it.
- Direct visible-text scan found only `品牌素材与文档.zip` and `Quick Look 预览` as English-letter candidates. The first is a sample filename/extension; Quick Look is Apple's product name embedded in Chinese. Other English-letter literals found by the broader source scan are file extensions, units, format/framework names (`PDF`, `PDFKit`, `Office`, `HEIC`, `SVG`, `MPEG-4`), SF Symbol identifiers, test launch flags, or preview-document/sample-filename content—not standalone English commands.
- The current shell therefore has no unexplained standalone English primary command. Full `zh-Hant`/English authored UI catalogs, pseudolocalization, and full future-screen localization remain pending; this foundation check does not close L-004/L-005.

## Accessibility and responsive UI evidence

The post-QC full scheme directly passed:

- `testMediaShellHasOneSidebarAndNoRejectedControls`;
- `testEssentialToolbarControlsDoNotOverlapAtMinimumWidth` at a 900-point window;
- `testLongMultilingualFilenameStaysSingleLineAndKeepsExtensionDiscoverable`;
- `testSearchAndCurrentOperationPopoverWork`, proving `检测完整性` is under the labeled `操作` menu;
- `testDefaultMediaStripShowsAllPrimaryItemsWithoutEdgeClipping`, proving all five primary media items remain inside the visible strip at the default window state;
- `testKeyboardReachabilityAndAccessibilityAudit`.

The accessibility audit did report and narrowly accept only the already-recorded framework structures: two otherwise-empty PDFKit page containers whose subtrees carry the dynamic Chinese page label, the native `操作` MenuButton action mismatch (separately click-tested), a 14×14 glyph under a standard macOS window button, and the virtual Touch Bar node. The test passed after recording those exact structures; this is not represented as “zero audit observations.” Full manual VoiceOver/Full Keyboard Access recordings for real provider workflows remain pending.

One intermediate post-QC full run failed the audit on the bottom status text because the standard `.bar` material did not provide deterministic contrast while the XCUI application was inactive. A focused rerun reproduced it. The status region now uses the native opaque window background in every appearance state; the focused audit passed and the final clean 48-test scheme passed. The failed run is preserved as LOOP evidence rather than hidden.

Current Task 8 original-resolution visual evidence was captured after the user's toolbar correction. Task 6 screenshots are historical only and are not used as current-state proof:

| State | Artifact | SHA-256 |
|---|---|---|
| Light | `.superpowers/sdd/task-8-visual/current-light-default.png` | `423e30e6d55d6948f961c7db4f5ddc75bf906c624e3a3509ae587afea31b5a4e` |
| Dark | `.superpowers/sdd/task-8-visual/current-dark-default.png` | `7ad1ece1934977ac5808f241dc0c2e161a24933d141d5696a7fa58cdf893eae1` |
| Reduce Transparency | `.superpowers/sdd/task-8-visual/current-reduce-transparency.png` | `464634f7335db1e64be2045ad395c20b3df0dce31931d3b8086641db241563f3` |
| Increase Contrast | `.superpowers/sdd/task-8-visual/current-increase-contrast.png` | `c5cb64ce92f4a6fcc8dea53dd18f57b757588a8c8c6ee9c18f1c0d8f71422139` |
| 900-point runtime | `.superpowers/sdd/task-8-visual/current-minimum-light.png` | `035f966dc759529c0e32a964ffa15f4b2848cbc2ca4dedf7c6d05991d5c5a5d2` |

Codex inspected the current light render and the approved Finder/media source at original resolution in the same review context. That pass caught a real trailing-edge clip on `品牌指南.pdf`; a failing UI regression measured `1248 > 1197`, the strip geometry was reduced to a 108-point item/12-point gap/16-point inset rhythm, the focused test then passed, and all five labels/sizes are fully visible in the recaptured light state. A separate 900-point inspection found the long search placeholder visually truncated; a second red/green regression now requires the compact placeholder `搜索`, while its accessibility identifier/label remains `搜索压缩包内容`. The title has no decorative rounded badge, no top-level integrity action or ambiguous standalone ellipsis remains, and the explicit `操作` menu is visible.

## Required model-QC disposition

- Hermes `aishuo / MiniMax-M3` completed three rounds in one session. It accepted the current Chinese terminology/hierarchy surface, confirmed `检测完整性` under `操作`, and flagged stale catalog/help/status copy. Codex removed the stale `更多` and unused integrity strings and tightened the copy. Its optional suggestion to rename the visible menu to `更多操作` was not applied because the user's explicit correction prefers a compact, clear labeled secondary control and the current `操作` label is unambiguous in context.
- Hermes `aishuo / GLM-5.2` returned a terminal HTTP 503 after three provider retries. The authorized `buddy / GLM-5.2` fallback then returned `不支持的模型`. Neither failure was silently substituted or treated as review evidence.
- Reasonix CLI `deepseek-pro` completed the corrected bounded security review after the first attempt was invalidated for following erroneous allowlist paths with unauthorized discovery. The corrected pass read only the fixed allowlist and recommended **pass with provider gates**. It retained executable path/spawn TOCTOU and escaped descendants as critical production gates, and added cooperative cancellation, bounded operation-history retention, and sub-operation cancellation checks as provider-stage gates. No production helper capability is enabled by this foundation acceptance.
- Hermes `aishuo / Gemini-3.5-Flash` returned a terminal HTTP 503 after three provider retries. The initial `buddy / kimi-k2.7-code` turn made progress but hit the runner's 1,800-second timeout; one same-session controlled retry returned, but its vision calls had timed out and it created `/tmp/comparison.html` outside the one-output boundary. Codex invalidated that visual review, removed the temporary file, and did not treat its generic `REVISE` checklist as image evidence. Codex's own original-resolution source/current-image review remains final visual authority and drove the two concrete visual regressions above.

## Reproducibility, diff, and cleanup gates

### XcodeGen no-drift

```bash
find ArchiveWorkbench.xcodeproj -type f -print0 | LC_ALL=C sort -z \
  | xargs -0 shasum -a 256 > /tmp/before
xcodegen generate
find ArchiveWorkbench.xcodeproj -type f -print0 | LC_ALL=C sort -z \
  | xargs -0 shasum -a 256 > /tmp/after
diff -u /tmp/before /tmp/after
```

XcodeGen exited `0`; diff exited `0`. The post-QC before/after manifest SHA-256 was identical: `6e0ace774e9044b906a53ef8763920fff4c56b4cd695e67705adfe6f1b1909ca`. Generated file hashes were:

- `project.pbxproj`: `8a391f9d3b2e125f801795c4383b605ebc4ba91971d3695ffdf9797a786dae76`;
- workspace contents: `7f3b00b5c3fdb45242d7b87e1e5c4e25d1fa8129a16c94295ecc4e8ea2235c5f`;
- shared scheme: `8f8c5eed3ee860efe9cd924d87daf2dc95d968d44b4e2f7f8af9484fb3b3ff46`.

### Git and runtime cleanup

- `git diff --check`: exit `0`.
- `git diff --cached --check`: exit `0`; no staged changes existed.
- Cleanup initially found one orphaned app process from `/private/tmp/archive-task7-root-review/.../ArchiveWorkbench` and one generated PDF preview-cache directory from the fresh UI test. The post-QC full UI run generated the cache again, as expected under forced XCUI termination; it was removed again before the final gate.
- Final exact-process scan for `ArchiveWorkbench`, UI-test runner, `HelperFixture`, `LowFDHarness`, `7zz`, `xcodebuild`, and `xctest`: `NONE`.
- Final preview cache: `~/Library/Caches/ArchiveWorkbench/PreviewCache` absent.
- Final `hdiutil info` plus `mount` scan for ArchiveWorkbench/task/worktree attachments: `NONE`.

The worktree already contained unrelated modified/untracked design, research, traceability, conference, and review artifacts. This acceptance run preserved them and did not stage or commit anything.

## Skeptical five-risk review

| Most likely failure | Decision | Direct evidence and remaining boundary |
|---|---|---|
| Accidental dual-sidebar UI | **Foundation pass** | `ArchiveWorkbench/AppTests/DocumentShellTests.swift:67` asserts exactly one `压缩包侧边栏`; the fresh full scheme passed that test. Task 6 review4 visual hashes above provide rendered evidence. |
| Unsupported capability shown as enabled | **Partially proved; runtime requirement remains open** | `CapabilityRegistryTests.swift:13` proves DMG lacks create/update; `:23` proves RAR create is unavailable until validation; the 34-test package run passed. However the registry is a deterministic design matrix, not installed-provider discovery, and the fixture UI is not bound to runtime capability state. Provider availability/identity validation plus UI disabled/hidden-state E2E must pass before this product risk can close. |
| Raw path bytes lost during display decoding | **Foundation value-contract pass; provider round trip pending** | `ArchiveDomainTests.swift:4` proves raw CP932-like bytes stay distinct from display text. `ArchivePathPolicyTests.swift:54` proves a Windows rename proposal retains original bytes. Actual provider open/edit/save central-directory byte comparison remains pending. |
| Scheduler mutation overlap | **Foundation scheduler pass** | `OperationSchedulerTests.swift:157` proves same-archive mutation maximum is one; `:187` proves different archives may overlap; cancellation races and permit recovery are also covered. Fresh normal tests and the fresh 14-test TSan run passed with no TSan race report. Provider adapters still need cancellation/process-boundary integration tests. |
| Password leakage | **Non-hardened spike pass; production host remains open** | `PasswordTransportTests.swift:139` checks argv, allowlisted environment, FDs, process snapshot, stdout/stderr and zeroization. `SevenZipProbeTests.swift:9` proves fixed bare-`-p` encrypted create/list/test/extract with negative controls and no secret in channels/evidence. Prohibited shell/process API, password-bearing `-pVALUE`, and persistence scans produced no matches. The hardened app-bundled/user-selected helper matrix remains entirely `capabilityDisabled`; executable validation/spawn TOCTOU and escaped-descendant discovery remain explicit residual risks. |

## Foundation accepted

The following foundation surfaces have fresh direct evidence at this commit:

- reproducible XcodeGen project and clean arm64 full-scheme execution;
- hardened local ad-hoc app signature, compiled Simplified-Chinese resources, and Chinese primary shell controls;
- immutable domain values and deterministic capability contracts;
- pure path/resource-budget policies and fixtures;
- actor-isolated scheduler contract, including a passing TSan scheduler run;
- single-sidebar Finder/media shell, 900-point toolbar/filename regressions, typed preview routes, two-page PDFKit fixture, bounded descriptor-relative preview-cache tests, and scoped accessibility audit;
- non-hardened helper/password/fixed-7zz diagnostic contract, with its capability limitations preserved.

## Provider and E2E work still pending

At minimum, the following stay open and must not be inferred from this packet:

1. ZIP/minizip-ng create/list/read/preview/extract/add/remove/rename/replace/encrypt/split/test/repair, transactional save and unchanged-byte proof.
2. libarchive TAR/filter/ISO workflows and the isolated read-only DMG provider.
3. Production 7zz 7z/RAR workflows, multipart handling, encrypted fixtures, cancellation, helper identity/trust, hardened app host, and user-selected executable/bookmark flow.
4. Lawful external RARLAB create/update installation, validation, license acknowledgement, and Windows WinRAR proof.
5. Real archive-entry PDF/image/video and every `.doc/.docx/.xls/.xlsx/.ppt/.pptx` Quick Look E2E preview; Task 6 Office/video states remain hosts/placeholders.
6. All real open/create/extract/edit/save/cancel/recovery/Finder/Quick Look/settings/help workflows and runtime capability gating.
7. Complete `zh-Hant` and English UI catalogs, pseudolocalization, manual VoiceOver/keyboard workflow evidence, icon deliverables, and provider-state screenshots.
8. Physical Windows 11 Explorer/7-Zip/WinRAR interoperability, multilingual filenames, ZIP64/4 GiB, multipart and metadata-suppression checks.
9. Performance/memory/disk/bomb/malicious-fixture/fault-injection targets and target-Mac Instruments evidence.
10. Direct/OpenSource build profiles, SBOM/notices, clean-machine local installation, Developer ID/notarization readiness, and final user-perspective full regression. No upload or publishing is authorized.
