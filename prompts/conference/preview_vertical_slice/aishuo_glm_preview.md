You are Hermes performing a bounded architecture review for Codex. First fully read and comply with `/Users/smkzw/.hermes/SOUL.md`.

Provider/model: `aishuo / glm-5.2`.

Hard boundaries:
- Work only inside `/Users/smkzw/Documents/AI Products/.worktrees/foundation`.
- Do not browse, run commands or tests, inspect screenshots, modify source, or discover other files.
- Write exactly one output file: `runs/conference/preview_vertical_slice/aishuo_glm_preview.md`.

Read these files only:
- `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
- `ArchiveWorkbench/App/Sources/AppModel.swift`
- `ArchiveWorkbench/App/Sources/ArchiveDocumentView.swift`
- `ArchiveWorkbench/App/Sources/MediaPreviewView.swift`
- `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
- `ArchiveWorkbench/App/Sources/PreviewRouting.swift`
- `ArchiveWorkbench/App/Sources/ArchiveWorkbenchApp.swift`
- `ArchiveWorkbench/AppUnitTests/ArchiveDocumentLoaderTests.swift`
- `ArchiveWorkbench/AppUnitTests/PreviewRoutingTests.swift`

Review cache lifetime across multiple windows, actor isolation, cancellation and stale selection, bounded reads, main-thread work, AVPlayer stability, PDFKit/Quick Look handoff, symlink/path revalidation, cleanup, error honesty, and test coverage. Cite exact symbols. Separate blockers, important fixes, optional improvements, false-positive risks, and next tests. Do not mark the full product complete.
