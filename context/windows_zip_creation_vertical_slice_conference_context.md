# Conference Context: windows_zip_creation_vertical_slice

Created: 2026-07-13 06:32:24
Objective: 设计并审查 Windows 11 原生兼容 ZIP 创建的端到端垂直切片：原生中文创建面板、输入与保存选择、全树兼容预检、流式创建、进度取消、同目录事务发布、创建后重新打开并核对清单/大小/SHA-256、失败清理和真实 E2E
Task type: `complex_delivery_conference`
Risk: `high`
Conference mode: `parallel`

## Codex Main Venue

- Chair: Codex.
- Duties: understand the real task, decompose, define sources of truth, route work, protect boundaries, verify final artifacts, own visual/browser/PPT/PDF checks, own production writes, and deliver to the user.

## Conference Panel Assignment

- Visual/design tasks use a Codex-led panel with no Hermes sub-venue chair: Hermes `aishuo / MiniMax-M3`, Hermes `buddy / kimi-k2.7-code`, and Hermes OpenCode Go `qwen3.7-plus`.
- Chinese labels or Chinese sentence review uses a single Hermes `buddy / deepseek-v4-pro` gate and does not start a conference.
- Other complex tasks use Hermes `buddy / glm-5.2` as the sub-venue chair, leading Hermes `aishuo / MiniMax-M3`, Hermes `buddy / deepseek-v4-pro`, and Hermes OpenCode Go `mimo-v2.5`.
- This conference route does not invoke Reasonix for a high-risk second review.
- Every conference role is dispatched through a three-round same-session loop: independent pass, skeptical challenge, and corrected final pass. A new session is a routing failure unless a primary role failed before a resumable session existed and the documented fallback was activated.

## Source Of Truth

- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/WindowsZIPProfile.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests/WindowsZIPCreationTests.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/include/AWBMinizipBridge.h`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`
- `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/App/Sources/RootWindowView.swift`
- `design/2026-07-11_full_design_spec.md`, especially sections 5.3, 13, 14, 19 and 25.
- User corrections in the active task: local/direct distribution only for now; no upload; Windows-compatible output; native Chinese; RAR creation remains separately installed validated RARLAB only.

## Scope

- In scope: Windows-native unencrypted ZIP creation; file/folder input selection; save destination; preflight manifest; UTF-8/NFC and Windows path compatibility; macOS metadata suppression; streaming/cancellable writer boundary; progress; same-parent staging and exclusive publish; source-change detection; reopen plus entry/size/SHA-256 verification; Chinese App state/error mapping; real provider/App/E2E test plan.
- Out of scope: 7z/AES/ZipCrypto UI, split archives, RARLAB discovery/creation, editing an existing archive, website/GitHub publication, App Store distribution, Intel support, and final visual acceptance (handled by a separate visual panel after implementation).

## Success Criteria

- Creating a ZIP never overwrites an existing target and never exposes a partial final archive.
- Inputs are preflighted before the writer opens: reject links/special files, Windows reserved/illegal/trailing names, over-budget paths, NFC/case collisions and root-name collisions; suppress macOS metadata deterministically.
- File content is streamed with bounded memory and cancellation checks; source identity/content changes cause failure and staging cleanup.
- The created ZIP uses Store/Deflate and UTF-8 bit 11 consistently and is reopened by the primary ZIP provider.
- Post-create verification proves the exact expected file manifest, uncompressed sizes and SHA-256 values before publish or before reporting success; define the transaction ordering explicitly.
- App UI uses native Chinese input/save workflows, accurate compatibility copy, progress/cancel, completion/Finder reveal and specific recoverable errors.
- Tests cover multilingual names, empty inputs/metadata-only inputs, collisions, cancellation, source mutation, existing target, post-write corruption/mismatch, cleanup and real E2E.
- Codex independently verifies implementation, full package/App tests, Release arm64/signing, rendered UI and Windows physical interoperability at the appropriate release gate.

## Parallel Work Rule

For logic-heavy, rigor-sensitive, or artifact-heavy tasks, each participant independently runs the whole bounded workflow and writes a separate output. Leads compare after all available participant outputs are in or explicitly marked pending.

## Timeout Policy

- Participant soft wait: 20 minutes.
- Large-task participant wait: 45 minutes.
- Chair hard wait: 90 minutes.
- Failure rule: Do not fail a model for slow response alone; fail only on terminal error, provider exhaustion/rate limit after controlled retry, empty/truncated retry output, or no progress after hard wait plus one retry.

## Risk Boundaries

- Hermes is advisory; Codex remains final authority.
- Codex owns visual/browser/PPT/PDF/rendered checks, live authority checks, final clinical/regulatory conclusions, and production writes.
- Do not mark a slow model failed solely due to latency.

## Loop Log

- 2026-07-13 06:32:24: Conference initialized by `hermes_workflow_guard.py init-conference`.
