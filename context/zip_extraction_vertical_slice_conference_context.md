# Conference Context: zip_extraction_vertical_slice

Created: 2026-07-12 10:55:22
Objective: 设计并审查 ArchiveWorkbench 的真实安全流式 ZIP 全量解压切片，覆盖目标目录事务、路径与链接安全、资源预算、空目录、文件冲突、取消、进度、失败清理及用户可验证结果
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

- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ArchivePathPolicy.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ResourceBudget.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests/ZIPArchiveProviderTests.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveSecurityTests/SecureFileMaterializerTests.swift`
- `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`
- `ArchiveWorkbench/AppTests/DocumentShellTests.swift`
- User requirements: native macOS app; Apple Silicon; Chinese UI; safe real extraction; user-visible commercial-product behavior.

## Scope

- In scope: ZIP full-archive extraction architecture, descriptor-safe streaming writes, aggregate budget, empty directories, destination transaction, deterministic collision-free output folder, cancellation/progress contract, failed-operation cleanup, Finder reveal, and test plan.
- Out of scope: source edits by Hermes, RAR/7z extraction, password UI, archive creation/editing, web research, visual acceptance.

## Success Criteria

- No archive entry is buffered in full solely for extraction.
- Unsafe path, symlink, encrypted entry, budget violation, cancellation, or I/O failure never publishes a partial final output folder.
- Existing destination content is never overwritten; final folder naming is deterministic and conflict-free.
- Empty directories and multilingual UTF-8 paths are preserved.
- Progress is monotonic and cancellation is observable during the decompression loop.
- Tests cover success, path/link rejection, aggregate limits, empty directory, conflict suffix, cancellation, cleanup, and real user workflow.

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

- 2026-07-12 10:55:22: Conference initialized by `hermes_workflow_guard.py init-conference`.
