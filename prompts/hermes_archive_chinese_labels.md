You are Hermes running inside a Codex-controlled workflow.

First, fully read and comply with `/Users/smkzw/.hermes/SOUL.md`. In your output, include one sentence saying whether you read the full file. Do not claim this unless you actually read it.

Hard boundaries:
- Work only inside `/Users/smkzw/Documents/AI Products/.worktrees/foundation`.
- Do not read or modify production paths.
- Do not edit files unless Codex explicitly authorizes an edit round.
- Do not browse web, run tests, open browsers, inspect images, or perform visual/PPT/browser acceptance unless explicitly assigned.
- Write exactly one output file: `runs/hermes_archive_chinese_labels.md`.

Read these files only:
- `context/archive_chinese_labels_context.md`
- `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`
- `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/AppTests/DocumentShellTests.swift`

Task:
Review the current user-facing Chinese copy from a native macOS Chinese-user perspective. Focus on toolbar/menu labels and preview loading/error text. Specifically judge whether “检测完整性” is natural, understandable, and correctly demoted under the “操作” secondary menu after the user identified it as low-frequency. Do not edit source. Quote the exact current string for every finding and propose a replacement only when it is materially better.

Output schema:
1. `# Hermes Chinese Copy Review: archive_chinese_labels`
2. `## Boundary Check`
3. `## Must Change`
4. `## Optional Refinements`
5. `## Keep As Is`
6. `## Detection Integrity Verdict`
7. `## Codex-Owned Verification`

Quality gates:
- Do not claim access to sources not listed in the context.
- Do not make final clinical/regulatory/visual/current-web claims.
- Distinguish terminology defects from personal style preferences.
- Do not recommend returning “检测完整性” to the primary toolbar.
