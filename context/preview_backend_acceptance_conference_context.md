# Conference Context: preview_backend_acceptance

Created: 2026-07-12 10:23:06
Objective: 复核 ArchiveWorkbench 压缩包内图片、视频、PDF、Word、Excel、PowerPoint 真实物化与预览后端链路，重点检查取消、缓存生命周期、加密条目、资源上限、跨格式真实性和测试覆盖；仅审查不编辑源码
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

- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
- `ArchiveWorkbench/App/Sources/PreviewRouting.swift`
- `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
- `ArchiveWorkbench/App/Sources/MediaPreviewView.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`
- `ArchiveWorkbench/AppUnitTests/ArchiveDocumentLoaderTests.swift`
- `ArchiveWorkbench/AppUnitTests/PreviewRoutingTests.swift`
- `ArchiveWorkbench/Scripts/verify_preview_fixtures.sh`

## Scope

- In scope: 真实 ZIP 条目物化、预览缓存约束、取消和选择竞争、加密条目、资源上限、图片/视频/PDF/Office 路由、视频可播放性、测试是否真正覆盖六类格式。
- Out of scope: 修改源码、运行命令、视觉美学验收、网络调研、发布或分发。

## Success Criteria

- 每项结论必须给出具体文件与代码证据，并区分已验证缺陷、推断风险、误报和后续功能。
- 明确检查快速切换选择、取消、加密条目、大文件、缓存清理、视频失败态、Office Quick Look 路径。
- 审核测试是否包含真实 ZIP 物化和真实可播放视频，而非仅扩展名或假字节。
- 给出阻断/重要/优化分级；不得以模型共识替代证据。

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
- 不得读取截图或用户桌面内容；视觉验收由独立 visual conference 与 Codex 完成。

## Loop Log

- 2026-07-12 10:23:06: Conference initialized by `hermes_workflow_guard.py init-conference`.
