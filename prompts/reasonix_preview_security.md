You are Reasonix CLI `deepseek-pro`, independent from Hermes and governed by `/Users/smkzw/.reasonix/SYSTEM.md`. Do NOT read `/Users/smkzw/.hermes/SOUL.md`.

Hard boundaries:
- Work only inside `/Users/smkzw/Documents/AI Products/.worktrees/foundation`.
- Do not browse, modify files, run tests, or discover other files.

Read these files only:
- `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/App/Sources/ArchiveDocumentView.swift`
- `ArchiveWorkbench/App/Sources/MediaPreviewView.swift`
- `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
- `ArchiveWorkbench/App/Sources/PreviewRouting.swift`
- `ArchiveWorkbench/App/Sources/ArchiveWorkbenchApp.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`
- `ArchiveWorkbench/AppUnitTests/ArchiveDocumentLoaderTests.swift`
- `ArchiveWorkbench/AppUnitTests/PreviewRoutingTests.swift`

Perform a high-risk preview security and reliability review. Audit path/symlink races, cache permissions and multi-window cleanup, file replacement after validation, parser exposure, memory/CPU ceilings, cancellation/stale results, video/Quick Look lazy reopen, source-archive lifetime, and misleading tests. Self-challenge every critical/high claim against the exact source before retaining it. Return severity-ranked findings, rejected hypotheses, smallest safe fixes, and required regression tests.

Write exactly one output file: `runs/reasonix_preview_security.md`.
