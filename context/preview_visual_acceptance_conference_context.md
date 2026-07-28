# Conference Context: preview_visual_acceptance

Created: 2026-07-12 10:16:39
Objective: 审查 ArchiveWorkbench 默认和最小宽度真实窗口截图，聚焦工具栏重叠、标题溢出、省略号歧义、Finder 式预览布局与中文视觉层级；仅输出审查建议，不编辑源码
Task type: `visual_delivery_conference`
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

- `ArchiveWorkbench/runs/conference/preview_visual_acceptance/evidence/toolbar-default.png`: XCTest 截取的 1226×872 默认宽度真实应用窗口。
- `ArchiveWorkbench/runs/conference/preview_visual_acceptance/evidence/toolbar-minimum.png`: XCTest 截取的 900×700 最小宽度真实应用窗口。
- `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`: 当前工具栏结构与中文标签。
- `ArchiveWorkbench/App/Sources/MediaPreviewView.swift`: 当前 Finder 式媒体预览结构。
- `ArchiveWorkbench/AppTests/DocumentShellTests.swift`: 重叠、单行文件名、一级/二级功能和截图证据的自动化检查。

## Scope

- In scope: 逐张查看两张截图；检查标题、按钮、搜索框、工具栏顺序与间距、一级/二级操作、默认/最小宽度、侧边栏/预览/检查器/媒体条带的视觉层级；按阻断、重要、优化分级。
- Out of scope: 修改源码、运行测试、浏览网络、发布应用、替代 Codex 作最终视觉验收。

## Success Criteria

- 两张截图均被实际读取，结论引用具体可见区域而非仅凭源码推断。
- 明确判断用户指出的标题圆角框溢出、右侧省略号、`检测完整性` 一级按钮是否仍存在。
- 识别真实的新问题，同时避免把刻意的单行中间省略、水平滚动媒体条带或系统 Liquid Glass 容器误报为缺陷。
- 输出可执行的修复优先级；若无阻断问题，明确说明。

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
- 允许参与者读取并视觉检查上述两张本地 PNG；不得读取其他屏幕截图或用户桌面内容。

## Loop Log

- 2026-07-12 10:16:39: Conference initialized by `hermes_workflow_guard.py init-conference`.
