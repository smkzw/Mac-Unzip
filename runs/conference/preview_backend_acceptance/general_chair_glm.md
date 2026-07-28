Warning: Unknown toolsets: messaging, moa
# Hermes Sub-Venue Review: preview_backend_acceptance - general_chair_glm

## Inputs Reviewed
- Codex Conference Context (`preview_backend_acceptance_conference_context.md`)
- Main-Venue Acceptance Plan (`codex_main_venue_preview_backend_acceptance.md`)
- Participant Outputs:
  - `general_aishuo_minimax.md` (Round 3, Final)
  - `general_buddy_deepseek.md` (Round 3, Final)
  - `general_opencode_mimo.md` (Round 3, Final)
- Source Files:
  - `ArchiveWorkbench/App/Sources/AppModel.swift`
  - `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
  - `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
  - `ArchiveWorkbench/App/Sources/PreviewRouting.swift`
  - `ArchiveWorkbench/App/Sources/RoutedPreviewViews.swift`
  - `ArchiveWorkbench/App/Sources/MediaPreviewView.swift`

## Participant Comparison
Participants reached strong consensus on the backend preview architecture and identified critical gaps.
- **Security & Integrity (Strong Agreement)**: The descriptor-based security model (`SecureFileMaterializer`, `O_NOFOLLOW`) and `ValidatedPreviewCacheURL` pre-flight checks are robust against directory traversal and symlink attacks.
- **Office UX Gap (Strong Agreement)**: Office Quick Look implementation is incomplete. It lacks a `QLPreviewViewDelegate` implementation in `QuickLookCanvas`, causing silent failures (UX hang).
- **Concurrency & Reliability (Strong Agreement)**: `AppModel`’s `previewRequestID` guard successfully prevents state corruption during rapid selection, but the underlying loader lacks effective cancellation propagation for blocking decompression tasks (DoS-like behavior).
- **Resource Management (Consensus on Deficiency)**: The current cache lifecycle (no startup cleanup/TTL) is a structural design flaw leading to indefinite disk usage growth.

## Conflicts And Missing Work
- **Conflict Resolution (Cache Severity)**:
  - Initial participants vacillated between "crash-handling gap" and "Critical Design Defect."
  - **Resolution**: This is a **High-Priority Design Defect (P1)**. It is not an immediate showstopper for functionality but represents a failure in resource hygiene that must be addressed in the next architectural review cycle.
- **Missing Evidence (Cancellation Propagation)**:
  - The audit relies on inferred cancellation success in `ZIPArchiveProvider`. While `Task.checkCancellation()` calls exist, the actual decompression loop (which is CPU/IO intensive) may block these checks. **Uncertainty remains** on whether these checks are granular enough to preemptively stop decompression during heavy contention.
- **Missing Evidence (Frontend-Backend Integration)**:
  - Integration testing covers materialization (backend) and routing logic (frontend), but no test verifies a full round-trip from materialization to *successful rendering* in the UI for any format other than the PDF fixture.

## Third-Party Perspectives
- **Reliability Engineering**: The current architecture allows the UI to fire requests while the backend is blocked on a long decompression. The application must enforce a "debounce + cancel" mechanism in `AppModel` to genuinely solve the DoS risk.
- **Security Engineering**: The TOCTOU-protected `ValidatedPreviewCacheURL` validation mechanism (re-checking the descriptor during the `readData` lifecycle) is excellent and should be preserved in any future refactor.
- **Quality Assurance**: The heavy reliance on `verify_preview_fixtures.sh` (a shell-based script) is a maintenance fragility. The verification of rendering integrity *must* be formalized within the Swift-based test suite.

## Rerun Or Supplemental Work Plan
- **Actionable Task (Codex-Auth Required)**: Add explicit instrumentation to the decompression loop in `ZIPArchiveProvider` to confirm that `Task.checkCancellation()` is hit frequently enough during large file decompressions.
- **Verification Plan (Recommendation)**: Authorize a supplemental test plan that mocks a slow codec response to verify that `NativeVideoPreviewStateView` and `OfficeQuickLookPreviewStateView` display a "failed" state rather than a silent progress-bar hang.

## Sub-Venue Recommendation To Codex
- **Immediate UX Fix (Frontend)**: Authorize an edit to `RoutedPreviewViews.swift` to fully implement `QLPreviewViewDelegate` for `QLPreviewView`. This is the single highest-impact UX fix required for acceptable Office file previewing.
- **Reliability Fix (Backend)**: Authorize an edit to `ArchiveDocumentLoader.materializePreview` and `ZIPArchiveProvider.materializeEntry` to incorporate robust task-based cancellation propagation. 
- **Architectural Change (Cache Management)**: Implement a startup TTL-based pruning pass on `ValidatedPreviewCacheURL.cacheRoot` to delete files > 24 hours old.
- **Test Engineering**: Migrate fixture-based validation from `verify_preview_fixtures.sh` to a Swift-based integration test (Swift Testing/XCTest) to improve CI reliability.

## Archive And Resume Notes
- Session 20260712_104206_bd7c79.
- This sub-venue conference loop is now complete for Round 3 (Final corrected pass). All findings are consolidated; recommendations are actionable for Codex. No further Hermes sub-venue chair rounds are required.

↻ Resumed session 20260712_104206_bd7c79 (3 user messages, 20 total messages)

session_id: 20260712_104206_bd7c79
Exception ignored in: <coroutine object MCPServerTask.run at 0x10b3479c0>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x10b347880>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x10b347740>
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
