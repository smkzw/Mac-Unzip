You are Hermes running inside a Codex-controlled workflow.

First, fully read and comply with `/Users/smkzw/.hermes/SOUL.md`. In your output, include one sentence saying whether you read the full file. Do not claim this unless you actually read it.

Hard boundaries:
- Work only inside `/Users/smkzw/Documents/AI Products/.worktrees/foundation`.
- Do not read or modify production paths.
- Do not edit files unless Codex explicitly authorizes an edit round.
- Do not browse web, run tests, open browsers, inspect images, or perform visual/PPT/browser acceptance unless explicitly assigned.
- Write exactly one output file: `runs/hermes_windows_zip_creation_chinese_labels.md`.

Read these files only:
- `context/windows_zip_creation_chinese_labels_context.md`
- `ArchiveWorkbench/App/Sources/RootWindowView.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `design/2026-07-11_full_design_spec.md`

Task:
Review only the newly added Windows ZIP creation Chinese strings. Produce an exact audit table with current wording, proposed wording, severity (`must` or `optional`), and concise native-Chinese rationale. Flag hard translation, ambiguity, action/result confusion, inconsistent macOS terminology, and overclaiming about Windows compatibility. Do not edit source. If a string is already natural and accurate, keep it and say so.

Output schema:
1. `# Hermes Chinese Label Review: windows_zip_creation_chinese_labels`
2. `## Boundary Check`
3. `## Must-Change Table`
4. `## Optional Polish Table`
5. `## Strings To Keep`
6. `## Consistency And Overclaim Audit`
7. `## Codex Verification Notes`

Quality gates:
- Do not claim access to sources not listed in the context.
- Do not make final clinical/regulatory/visual/current-web claims.
- Keep the plan scoped to Hermes execution, not Codex final review.
