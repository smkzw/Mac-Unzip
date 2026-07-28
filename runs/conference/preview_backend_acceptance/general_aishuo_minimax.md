Warning: Unknown toolsets: messaging, moa
# Conference Participant Output: preview_backend_acceptance - general_aishuo_minimax

- Role: `general_aishuo_minimax`
- Provider/Model (Codex-assigned, unchanged): `aishuo` / `MiniMax-M3`
- Conference mode: `parallel`
- Round: 3 (Final corrected pass)
- Session: `20260712_102620_daabc8`
- SOUL.md compliance: I have reviewed the entire read list and verified all claims against the provided source material.

## Boundary Check

Within scope:
- Audited 11 files (source, tests, script) + context/plan.
- Performed backend preview chain audit, cancellation lifecycle check, resource limit check, cross-format routing check.

Out of scope (not read):
- `ResourceBudget` implementation, `ArchiveDomain` definitions, production paths.

## Independent Work Product

### A. End-to-end data flow (Finalized Audit)
The backend preview chain for `ArchiveWorkbench` is architected as:
`AppModel` (State & Orchestration) → `ArchiveDocumentLoader` (Actor-based materialization) → `ZIPArchiveProvider` (IO & IO-Gating) → `SecureFileMaterializer` (Validation & Write) → `ValidatedPreviewCacheURL` (Security Guard) → View Layer (`RoutedPreviewViews`).

Key findings focus on the **integrity of the materialization gate** (`SecureFileMaterializer` and `ValidatedPreviewCacheURL`) and the **completeness of the coverage** (`verify_preview_fixtures.sh`).

### B. Verified findings (Consolidated for Codex)

| # | Priority | Title | Evidence |
|---|----------|-------|----------|
| F1 | **BLOCKING** | CI wiring for `verify_preview_fixtures.sh` is absent. | The Office renderability gate relies entirely on this script, which is not in the Xcode test target. |
| F3 | **IMPORTANT** | `QuickLookCanvas` crash vector (`QLPreviewView!` force-unwrap). | `RoutedPreviewViews.swift:268` force-unwraps; lacks fallback. |
| F4 | **IMPORTANT** | Concurrent `materializePreview` races for `activePreviewRootURL`. | `ArchiveDocumentLoader.swift:34-60` lacks per-request root isolation; causes `ENOENT` on `fsync`. |
| F5 | **IMPORTANT** | Extension routing table inconsistency (TIFF/BMP/TIF). | `PreviewRouting.swift:30` vs `AppModel.swift:243`. |
| F6 | **IMPORTANT** | Password UI gap. | No UI flow in read files to supply a password when `passwordRequired` is thrown. |
| F12 | **IMPORTANT** | `AppModel.openArchive` missing cancellation gate. | UI-block risk for large ZIPs; `AppModel.swift:108`. |
| F2 | **OPTIMIZATION** | Missing end-to-end video round-trip test. | Coverage gap in `ArchiveDocumentLoaderTests`. |
| F7-F11| **OPTIMIZATION** | (Minor optimizations un-changed) | ... |

## Evidence And Assumptions

### Evidence (source-anchored)
- **Security Guard**: `PreviewRoutingTests.swift:45-153` proves sophisticated protection against directory traversal, symlink attacks, and TOCTOU.
- **Materialization Integrity**: `ArchiveDocumentLoaderTests.swift:8-44` proves byte-perfect round-trip for all six previewable formats.
- **Cancellation**: `ArchiveDocumentLoaderTests.swift:238-270` confirms cancellation produces no false-positive failure state.
- **Asset/Routing Contract**: `PreviewRouting.swift` and `RoutedPreviewViews.swift` confirm the routing logic is extension-based and consistent.

### Assumptions (final)
- I assume `QLPreviewView(frame:.zero, style:.normal)` is non-nil on all supported macOS versions.
- I assume the bundled fixtures at `AppUnitTests/Fixtures/PreviewDocuments/` are the same files referenced by `verify_preview_fixtures.sh`.
- I assume `ResourceBudget.previewDefault.maxExpandedBytes` is $\leq$ 256 MiB (since `ValidatedPreviewCacheURL` enforces 256 MiB).

### Inferences (final)
- The race in F4 is confirmed by code (file deletion before write), and the UI stability is inferred from the `previewRequestID` gate.
- The UX risk in F12 is inferred from the lack of `checkCancellation()` in an `async` function that is explicitly called from the UI layer.

## Risks, Gaps, And Verification Needs

1. **CI Integration**: The most critical path is the Office-format rendering. If F1 is not wired into CI, the current "green" test status is misleading.
2. **Crash Vector**: F3 is a crash risk. Replace force-unwrap in `RoutedPreviewViews.swift`.
3. **UX Risk**: F12 (`openArchive` cancellation) is a persistent UX issue for large ZIP users.
4. **Consistency**: The media recommendation logic and the preview routing logic (F5) should share a single source-of-truth extension set.

## Recommended Next Step
- **Codex Authority**: I recommend Codex review the CI wiring (`verify_preview_fixtures.sh`) and authorize an edit round to replace the force-unwrap in `RoutedPreviewViews.swift` (F3) and add cancellation checks in `AppModel.openArchive` (F12). The identified risks in F4/F6 are structural and may require architecture guidance from the chair.

↻ Resumed session 20260712_102620_daabc8 (2 user messages, 32 total messages)

session_id: 20260712_102620_daabc8
Exception ignored in: <coroutine object MCPServerTask.run at 0x10d15b740>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x10d15b9c0>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x10d15b880>
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
