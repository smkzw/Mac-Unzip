# Task Context: archive_chinese_labels

Created: 2026-07-12 10:49:46
Objective: 复核 ArchiveWorkbench 当前中文按钮、菜单和预览状态文案，重点判断检测完整性作为操作二级菜单是否符合中文用户语境
Task type: `chinese_label_sentence_review`
Risk: `low`
Selected agent route: `buddy` / `deepseek-v4-pro` / `high`

## Trigger Reason

This task was initialized through the Codex x Hermes complex-task entrypoint because it is expected to involve more than three execution steps, research/writing/report/code/report-visual work, or source-grounded verification.

## Source Of Truth

- `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`
- `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/AppTests/DocumentShellTests.swift`
- User decision: “检测完整性”不是常用功能；如非关键功能，不放顶栏，改放二级菜单。

## Scope

- In scope: current Chinese toolbar/menu labels and preview loading/error labels; especially the semantic fit of “检测完整性” under “操作”.
- Out of scope: source edits, visual acceptance, feature design, new functionality, web research.

## Success Criteria

- Return only concrete Chinese-copy findings, prioritized as must change / optional refinement / keep.
- Confirm whether “检测完整性” is understandable and suitably placed as a secondary command.
- Avoid literal translation and avoid renaming well-established macOS terms without a clear benefit.

## Risk Boundaries

- Do not write to production paths until Codex review gate passes and writable paths are explicit.
- The delegated agent is not final authority; Codex owns verification and acceptance.

## Timeout Policy

- Do not mark the delegated agent failed for slow response alone.
- For complex or artifact-heavy work, wait and poll generously; use conference mode when multiple independent model perspectives are needed.
- Failure requires terminal error, provider exhaustion/rate limit after controlled retry, empty/truncated retry output, or no progress after hard wait plus one retry.

## Loop Log

- 2026-07-12 10:49:46: Task initialized by `tools/hermes_workflow_guard.py init-task`.
- 2026-07-12 10:50:00: Codex limited the gate to copy review; no source edits are authorized.
