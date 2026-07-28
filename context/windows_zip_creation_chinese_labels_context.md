# Task Context: windows_zip_creation_chinese_labels

Created: 2026-07-13 08:15:27
Objective: 审查 ArchiveWorkbench Windows ZIP 创建流程新增的原生中文按钮、标签、说明、错误提示和兼容性文案，避免硬翻译、歧义、过度承诺与不符合 macOS 中文语境的表达
Task type: `chinese_label_sentence_review`
Risk: `medium`
Selected agent route: `buddy` / `deepseek-v4-pro` / `high`

## Trigger Reason

This task was initialized through the Codex x Hermes complex-task entrypoint because it is expected to involve more than three execution steps, research/writing/report/code/report-visual work, or source-grounded verification.

## Source Of Truth

- `ArchiveWorkbench/App/Sources/RootWindowView.swift`, limited to the Windows ZIP creation input/save workflow and `CreateArchiveView`.
- `ArchiveWorkbench/App/Sources/AppModel.swift`, limited to `ArchiveCreationDraft`, creation progress/status and `creationMessage`.
- `design/2026-07-11_full_design_spec.md`, sections 5.3, 7, 13 and the terminology table.

## Scope

- In scope: buttons, panel/section labels, explanatory text, compatibility statement, progress/cancel/completion text and creation-specific error messages added for the Windows ZIP slice.
- Out of scope: visual layout, code logic, other pre-existing archive labels, 7z/RAR/encryption copy and source edits.

## Success Criteria

- Identify must-change wording that is unnatural, ambiguous, misleading or overpromises Windows behavior.
- Preserve concise macOS Chinese conventions and clearly separate user action, compatibility fact and failure recovery.
- Return an exact current → proposed table, with rationale and severity; say explicitly when no change is needed.

## Risk Boundaries

- Do not write to production paths until Codex review gate passes and writable paths are explicit.
- The delegated agent is not final authority; Codex owns verification and acceptance.

## Timeout Policy

- Do not mark the delegated agent failed for slow response alone.
- For complex or artifact-heavy work, wait and poll generously; use conference mode when multiple independent model perspectives are needed.
- Failure requires terminal error, provider exhaustion/rate limit after controlled retry, empty/truncated retry output, or no progress after hard wait plus one retry.

## Loop Log

- 2026-07-13 08:15:27: Task initialized by `tools/hermes_workflow_guard.py init-task`.
