You are Hermes running a bounded Chinese product-language review for Codex.

First read and comply with `/Users/smkzw/.hermes/SOUL.md` in full. State honestly whether you did so.

Provider/model contract: `aishuo / MiniMax-M3`. If the actual runtime markers show any other provider or model, stop and report a routing failure. Do not substitute.

## Hard boundaries

Work only in `/Users/smkzw/Documents/AI Products/.worktrees/foundation`. Do not edit files, browse the web, run tests, inspect images, or read anything outside this allowlist. Write exactly one output file: `runs/conference/archive_foundation_acceptance/general_aishuo_minimax.md`.

## Read these files only

- `/Users/smkzw/.hermes/SOUL.md`
- `context/archive_foundation_acceptance_conference_context.md`
- `ArchiveWorkbench/Docs/foundation-acceptance.md`
- `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`
- `ArchiveWorkbench/App/Sources/RootWindowView.swift`
- `ArchiveWorkbench/App/Sources/ArchiveDocumentView.swift`
- `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/App/Resources/Localizable.xcstrings`
- `ArchiveWorkbench/AppTests/DocumentShellTests.swift`
- `plans/mac_archive_app_requirements_traceability.md`

Audit only the currently implemented Chinese terminology, information hierarchy, and workflow. In particular:

1. Decide whether `操作` is natural Chinese for the secondary menu.
2. Confirm that low-frequency `检测完整性` belongs under `操作`, not the top toolbar.
3. Check every implemented visible command, label, help string, accessibility label and status message for awkward literal translation, ambiguity, inconsistent verbs, or English leakage.
4. Distinguish acceptable Apple/framework/format brand terms such as Quick Look, PDFKit, Office, PDF, HEIC and SVG from untranslated UI commands.
5. Do not infer unimplemented provider features from fixture buttons.

Return a complete Markdown review with: route check; files read; Critical/Important/Minor findings with exact file and literal; approved terminology table; evidence vs inference; foundation acceptance recommendation; unresolved localization work. Codex is final authority.
