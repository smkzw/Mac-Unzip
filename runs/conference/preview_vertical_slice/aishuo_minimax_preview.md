Warning: Unknown toolsets: messaging, moa
# Aishuo / MiniMax-M3 — Archive-Entry Preview Vertical Slice Review (Round 3 Final Pass)

**Role:** Chinese terminology + user-workflow reviewer.
**Status:** Round 3 of 3 (Final Corrected Pass).
**Constraint Check:** Bounded to `/Users/smkzw/Documents/AI Products/.worktrees/foundation`. No source edits, no terminal commands.

## Boundary

- **Scope:** Six files reviewed: `AppModel.swift`, `ArchiveDocumentView.swift`, `MediaPreviewView.swift`, `RoutedPreviewViews.swift`, `PreviewRouting.swift`, `ArchiveDocumentLoaderTests.swift`.
- **Review Areas:** Chinese terminology, preview workflow (loading/failure/unsupported/password/oversize/selection-change), Finder-like expectations for 6 format families (image/video/PDF/Word/Excel/PowerPoint).
- **Hand-off:** Visual / layout / render / overlap / print / mobile-fit / PPT-editability remain handed back to Codex.

## What Works

- **Selection Hygiene:** `AppModel.loadSelectedPreview()` (`AppModel.swift:120-150`) effectively uses `previewRequestID` to discard stale async results and verify entry identity before application (`AppModel.swift:139`).
- **Cache Hardening:** `ValidatedPreviewCacheURL` (`PreviewRouting.swift:30-163`) implements secure file-system access (e.g., `O_NOFOLLOW`, `O_DIRECTORY` checks) to mitigate path-traversal risks during preview materialization.
- **Archive-level Chinese Copy:** Archive-level failures (e.g., password required for archive, corrupted archive) are correctly mapped to high-quality, professional Chinese strings in `AppModel.swift:298-326`.

## Problems

### Blockers

- **B1. Encryption Blindness (Router Logic):** `PreviewRoutingPolicy` (`PreviewRouting.swift:13-27`) relies solely on filename extensions. `ArchiveEntrySnapshot` already provides an `isEncrypted` boolean (`ArchiveDocumentLoaderTests.swift:63`). When a user selects an encrypted entry inside a ZIP, the router proceeds to `loadSelectedPreview`, which attempts to materialize the entry and fails with a generic error. **Correction:** The router must check `isEncrypted` to trigger a password-entry workflow or at least surface the appropriate Chinese error ("该文件已加密，请提供密码") instead of the generic "无法生成预览".
- **B2. Video Failure Surface (UX Gap):** `NativeVideoPreviewStateView` (`RoutedPreviewViews.swift:226-238`) only handles the loading state (`ProgressView`). It lacks error-handling logic for `AVPlayer` initialization or playback failures. The preview will hang indefinitely on a spinner if the video fails to load, and there is no Chinese failure string for video.

### Important

- **I1. Oversize Error Short-circuit:** `AppModel.loadSelectedPreview` short-circuits on `nil` from the `ValidatedPreviewCacheURL` initializer (`AppModel.swift:140-143`) before reaching the typed switch in `previewMessage(for:)`. **Correction:** `ValidatedPreviewCacheURL` should throw a specific error (e.g., `.oversize`) that `loadSelectedPreview` can catch to route to the correct Chinese copy ("这个文件过大，已停止生成预览。").
- **I2. Office Generic Labeling:** The labels/symbols for Word, Excel, and PowerPoint are collapsed into a generic "Office 文档预览" (`MediaPreviewView.swift:207`). **Correction:** Distinguish in terminology: "Word 文档预览", "Excel 表格预览", "PPT 演示文稿预览".
- **I3. Finder-like Navigation/Affordance:** The media strip (`MediaPreviewView.swift:88-144`) lacks keyboard-navigation (arrows) and has no affordance for "Quick Look" (Finder-style spacebar). This causes the media preview to feel detached from macOS system behavior.

## Evidence

- **B1 (Encryption):** `PreviewRoutingPolicy.kind(forFilename:)` (`PreviewRouting.swift:13`) signature lacks `isEncrypted`.
- **B2 (Video Failure):** `NativeVideoPreviewStateView` (`RoutedPreviewViews.swift:231-236`) has no path for `AVPlayerItem.status == .failed`.
- **I1 (Oversize):** `AppModel.swift:140` returns `nil` for oversize, triggering line 141 ("无法安全预览这个文件。"), which is NOT the specific oversize error string in `AppModel.swift:335-336`.
- **I2 (Office):** `PreviewRoutingPolicy.kind(forFilename:)` (`PreviewRouting.swift:22`) returns `.quickLookOffice` for all Office extensions.
- **I3 (Finder):** No `QLPreviewPanel` or `onKeyDown` handlers found in `MediaPreviewView`.

## Inference

- **Workflow Inconsistency:** The app treats archive-level errors as high-priority (specific Chinese copy) but entry-level preview errors as generic fallbacks (lower UX priority).
- **Finder Expectation Failure:** By prioritizing thumbnail-centric previewing over system-standard interactions, the UX creates friction for users expecting Finder-level control (spacebar-to-preview).

## Recommendation (Actionable for Codex)

1.  **P0 - Route Encryption:** Update `PreviewRoutingPolicy` to ingest `isEncrypted` and route to a dedicated `.encrypted` kind, enabling a specific "Password Required" Chinese error message.
2.  **P0 - Fix Typed Error Short-circuit:** Refactor `AppModel.loadSelectedPreview` to distinguish *why* `ValidatedPreviewCacheURL` rejected the entry, allowing the `previewMessage` switch to correctly map to the "oversize" Chinese copy.
3.  **P1 - Video Failure Surface:** Update `NativeVideoPreviewStateView` to monitor `AVPlayerItem` status and show `PreviewFailureStateView` if playback fails.
4.  **P1 - Localize Office:** Split `.quickLookOffice` into `.word`, `.excel`, and `.powerpoint` types in `PreviewRouting.swift` and update the view to use specific Chinese labels.
5.  **P1 - Finder Affordance:** Add keyboard-nav support to the media strip and investigate if `QLPreviewPanel` can be integrated for Finder-like spacebar-to-preview functionality.

## Uncertainty

- **Sync/Async Failure:** Whether the `AVPlayer` will fail synchronously on a sandboxed file or asynchronously; the failure-observation logic is non-trivial without a runtime test.
- **Office QuickLook Runtime:** The feasibility of using `QLPreviewPanel` within the current SwiftUI app structure and sandbox context is high-confidence (as it exists in `RoutedPreviewViews.swift`), but runtime integration needs testing.

## Verification Gaps

- **V1 (Password Prompt):** I cannot verify if `materializePreview` successfully passes the password requirement for encrypted *entries* without a real encrypted-ZIP fixture.
- **V2 (Oversize Test):** No unit test currently exercises the 256 MiB oversize limit; `ArchiveDocumentLoaderTests.swift` only uses tiny fixture payloads.
- **V3 (Race Condition):** The stale thumbnail flash inferred in `AppModel` requires a runtime performance trace to confirm.

↻ Resumed session 20260712_043103_e115fc (2 user messages, 17 total messages)

session_id: 20260712_043103_e115fc
Exception ignored in: <coroutine object MCPServerTask.run at 0x10aac7880>
Traceback (most recent call last):
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 2783, in run
    parked = await self._wait_for_reconnect_or_shutdown(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 1997, in _wait_for_reconnect_or_shutdown
    t.cancel()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 762, in call_soon
    self._check_closed()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 520, in _check_closed
    raise RuntimeError('Event loop is closed')
RuntimeError: Event loop is closed
Exception ignored in: <coroutine object MCPServerTask.run at 0x10aac79c0>
Traceback (most recent call last):
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 2783, in run
    parked = await self._wait_for_reconnect_or_shutdown(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 1997, in _wait_for_reconnect_or_shutdown
    t.cancel()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 762, in call_soon
    self._check_closed()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 520, in _check_closed
    raise RuntimeError('Event loop is closed')
RuntimeError: Event loop is closed
Exception ignored in: <coroutine object MCPServerTask.run at 0x10aac7740>
Traceback (most recent call last):
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 2783, in run
    parked = await self._wait_for_reconnect_or_shutdown(
             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/Users/smkzw/.hermes/hermes-agent/tools/mcp_tool.py", line 1997, in _wait_for_reconnect_or_shutdown
    t.cancel()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 762, in call_soon
    self._check_closed()
  File "/Users/smkzw/.local/share/uv/python/cpython-3.11.15-macos-aarch64-none/lib/python3.11/asyncio/base_events.py", line 520, in _check_closed
    raise RuntimeError('Event loop is closed')
RuntimeError: Event loop is closed
