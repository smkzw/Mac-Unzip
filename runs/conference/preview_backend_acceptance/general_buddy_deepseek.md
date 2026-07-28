Warning: Unknown toolsets: messaging, moa
  ┊ review diff
a/runs/conference/preview_backend_acceptance/general_buddy_deepseek.md → b/runs/conference/preview_backend_acceptance/general_buddy_deepseek.md
@@ -1,6 +1,6 @@
 # Conference Participant Output: preview_backend_acceptance - general_buddy_deepseek
 
-**Round:** 2 (skeptical challenge)
+**Round:** 3 (corrected final pass)
 **Model:** buddy / deepseek-v4-pro
 **Date:** 2026-07-12
 
@@ -14,74 +14,60 @@
 - No web browsing, browser tests, or visual acceptance (Codex domain): YES
 - Output file: `runs/conference/preview_backend_acceptance/general_buddy_deepseek.md`
 
-## Independent Work Product (Challenge/Refinement)
+## Independent Work Product (Final Audit Synthesis)
 
-This audit was challenged by re-verifying the interaction between `AppModel`, `ArchiveDocumentLoader`, `ZIPArchiveProvider`, and the SwiftUI preview views, specifically looking for edge cases where the UI might fail silently or the backend budget could be bypassed.
+This audit concludes that the core materialization, security, and cancellation defense chain for `ArchiveWorkbench` preview backend is robust. The primary issues identified are UX feedback gaps for Office files and a lack of comprehensive integration test coverage for failure modes.
 
-### 1. Refined Audit: Office Quick Look UX Gap (H1)
-*Initial Finding:* Quick Look has no failure state.
-*Skeptical Challenge:* Does `QLPreviewView` provide failure feedback automatically?
-*Inference:* `QLPreviewView` is a wrapper around the system Quick Look framework. It requires implementing `QLPreviewViewDelegate` to receive error callbacks (e.g., `previewView(_:didFailToPreview:item:)`).
-*Finding (Strengthened):* The gap is not just the lack of a "failed" UI state in `OfficeQuickLookPreviewStateView` (which is true), but the **total absence of `QLPreviewViewDelegate` implementation** in `QuickLookCanvas`. This means the application cannot react to file corruption, missing Office plugins, or system resource issues during the QL generation process.
-*Evidence:* `RoutedPreviewViews.swift:261-278` (QuickLookCanvas struct) provides only `NSViewRepresentable` body; no delegate context or implementation.
+### 1. Robust Security and Cancellation Defense (Verified)
+- **Race Protection:** The `previewRequestID` + `selectedEntryID` dual guard in `AppModel` effectively prevents stale preview results from overwriting newer ones during rapid selection.
+- **Materialization Security:** The use of `SecureFileMaterializer` with `O_NOFOLLOW` and explicit POSIX permissions (`0o700`) correctly prevents path traversal and symlink attacks during materialization.
+- **Cancellation Propagation:** Deep integration of `Task.checkCancellation()` within `ArchiveDocumentLoader` and `ZIPArchiveProvider` ensures that previews are aborted promptly.
+- **Budgetary Defense:** `ResourceBudget` correctly enforces `maxExpandedBytes` and compression ratios (50:1), and these limits are enforced both at the provider read level and the chunked-read level, preventing ZIP bombs.
 
-### 2. Refined Audit: Resource Budget Integrity
-*Initial Finding:* Provider read and budget enforcement are independent and correct.
-*Skeptical Challenge:* Can `ZIPArchiveProvider.readEntry()` be coerced into reading more than `maximumBytes`?
-*Evidence Check:* `ZIPArchiveProvider.swift:86-90`. The method is called with `snapshot.uncompressedSize` or `budget.maxExpandedBytes`. If `snapshot.uncompressedSize` is *larger* than `budget.maxExpandedBytes` but smaller than the limit checked in line 82-85, is it blocked?
-*Correction:* Line 82 (`snapshot.uncompressedSize <= maximumBytes`) *is* the budget-driven limit (passed in from `materializeEntry` as `budget.maxExpandedBytes`). The logic is airtight because `materializeEntry` calls `readEntry` using `budget.maxExpandedBytes` as the limit. The contract is respected.
+### 2. High-Severity UX/Functional Gap: Office Quick Look
+- **Finding:** The Office Quick Look backend (`OfficeQuickLookPreviewStateView` + `QuickLookCanvas`) fails silently. 
+- **Cause:** `QuickLookCanvas` lacks an implementation of `QLPreviewViewDelegate`. It cannot detect rendering errors, codec failures, or file corruption.
+- **Impact:** While the backend correctly materializes the file, the UI provides no feedback if the system fails to render it.
 
-### 3. Refined Audit: Cancellation/Race Condition
-*Initial Finding:* `previewRequestID` + `selectedEntryID` dual guard is robust.
-*Skeptical Challenge:* Is it possible for a cancellation error (`CancellationError`) to occur *before* the requestID/selectedEntryID guard check at line 147?
-*Code Path Analysis:* `ArchiveDocumentLoader.materializePreview` (line 145) is awaited. If it throws `CancellationError`, execution skips to `catch is CancellationError` (line 154), which returns immediately (line 155). This is correct. The dual guard is only required for the success path. *Refinement:* The defense holds.
-
-### 4. Refined Audit: Memory/Lifecycle
-*Initial Finding:* Cache directory is cleaned on every open or request materialization.
-*Skeptical Challenge:* What if the app is suspended and the process is killed?
-*Inference:* `ValidatedPreviewCacheURL.cacheRoot` uses `/Caches/`. macOS might clear this, but `PreviewCache/` remains.
-*Recommendation:* Add a startup pass to clean `PreviewCache/` directories older than a defined threshold (e.g., 24 hours), not just on `deinit` or `open`.
+### 3. Verification Gaps (Test Coverage)
+- **Integration Tests:** The core integration tests (`ArchiveDocumentLoaderTests.swift`) cover success paths for all formats and basic error cases (encryption, cancellation), but they do not cover failure states in the `RoutedPreviewViews.swift` layer (e.g., Office rendering failures, video playability errors).
+- **Cleanup:** No mechanism exists to purge orphaned preview cache directories in `~/Library/Caches/ArchiveWorkbench/PreviewCache/` resulting from process crashes.
 
 ---
 
 ## Evidence And Assumptions
 
-**Evidence sources used:**
-- Files: `AppModel.swift`, `ArchiveDocumentLoader.swift`, `PreviewRouting.swift`, `RoutedPreviewViews.swift`, `MediaPreviewView.swift`, `ZIPArchiveProvider.swift`, `SecureFileMaterializer.swift`, `ResourceBudget.swift`, `ArchiveDocumentLoaderTests.swift`, `PreviewRoutingTests.swift`
-- Verification Script: `verify_preview_fixtures.sh`
+**Evidence:**
+- Path validation: `ArchivePathPolicy` usage in `ZIPArchiveProvider` (line 38) and `SecureFileMaterializer` (line 18).
+- Cancellation check: Three checkpoints in `ArchiveDocumentLoader.materializePreview` (lines 35, 51, 53) and three in `ZIPArchiveProvider.materializeEntry` (lines 98, 110, 115).
+- Budget limits: `ResourceBudget` constants for preview (256MB, 50 ratio) and extraction.
 
 **Inference/Assumptions:**
-- Confirmed that `QLPreviewViewDelegate` is required for failure feedback in Quick Look.
-- Re-confirmed `ResourceBudget` contract enforcement in `ZIPArchiveProvider`.
-- Re-confirmed that no participant outputs were read.
+- Assumed `QLPreviewViewDelegate` is the correct mechanism for handling rendering errors within `QuickLookCanvas`.
+- Assumed that `AppModel`'s state management is the intended authoritative source for UI status messages.
 
 ---
 
 ## Risks, Gaps, And Verification Needs
 
 ### HIGH (Critical UX Defect)
+- **H1 — Office Quick Look failure is unhandled.** `QuickLookCanvas` must implement `QLPreviewViewDelegate` to detect and propagate rendering failures to `AppModel`.
… omitted 37 diff line(s) across 1 additional file(s)/section(s)
Round 3 (最终修正) 完成。

本轮通过最终的综合审计，确认了预览后端在路径安全、解压限制、取消竞态管理方面的实现非常稳健。主要的遗留问题在于 Office 文档预览（Quick Look）缺乏错误回调机制，导致在极端的渲染失败场景下会出现 UI 假死状态，这是本次审计发现的核心 UX 风险。所有 findings 已梳理并按优先级排序，行动计划已直接对接 Codex 验收要求。

↻ Resumed session 20260712_102620_8f63d3 (2 user messages, 32 total messages)

session_id: 20260712_102620_8f63d3
Exception ignored in: <coroutine object MCPServerTask.run at 0x1091cf9c0>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x1091cf880>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x1091cf740>
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
