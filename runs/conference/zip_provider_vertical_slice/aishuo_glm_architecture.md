Warning: Unknown toolsets: messaging, moa
I have read the `/Users/smkzw/.hermes/SOUL.md` file fully and agree to comply with its instructions.

***

# Architecture Review: ZIP Provider Vertical Slice

## Executive Summary
The vertical slice for the ZIP provider successfully implements the core requirements: bridging Minizip, providing a secure actor-based reader, and implementing a robust Windows-compatible ZIP creator with preflight checks and atomic publication. The reliance on POSIX `openat`/`unlinkat` and `O_NOFOLLOW` is excellent for security.

However, there are critical risks regarding C-bridge resource management, incomplete error handling in the C bridge, and potential data loss scenarios in the materialization process.

---

## 1. Critical Blockers

### Memory Leak on C-Bridge Reader Error (`ZIPArchiveProvider.swift`)
In `ZIPArchiveProvider.swift`, the `ZIPBridgeReader` initializer (`init(url:)`) handles failure by throwing an error, but it does not seem to guarantee the cleanup of the C-level reader handle if `mz_zip_reader_open_file` fails *after* `mz_zip_reader_create` has succeeded.
*   **Location:** `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`, lines 125-127.
*   **Finding:** If `awb_mz_reader_open` fails, the `ZIPBridgeReader` object might not have taken ownership of the `opened` handle correctly depending on the bridge implementation's state, leading to leaked C-structures.

### Missing Error Code Mapping (`AWBMinizipBridge.c`)
The mapping function `awb_mz_map_result` in `AWBMinizipBridge.c` is incomplete.
*   **Location:** `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`, lines 18-44.
*   **Finding:** Several `minizip` error codes are not explicitly handled or are mapped to generic `AWB_MZ_IO_ERROR`. Specifically, `MZ_INTERNAL_ERROR` and `MZ_CRC_ERROR` (which is mapped but potentially insufficient for corruption) should be explicitly distinguished from general IO errors to allow the Swift layer to make better decisions.

---

## 2. Important Fixes

### TOCTOU Risk in `syncFile` and `publishExclusively` (`WindowsZIPProfile.swift`)
*   **Location:** `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/WindowsZIPProfile.swift`, lines 46-52 and 56-65.
*   **Finding:** While `O_NOFOLLOW` is used, which is good, the atomic publication relies on `Darwin.link`. If a malicious actor creates a symlink at the destination between the check and the link, `link` might still fail as expected (`EEXIST`), but the error handling could be more robust. Furthermore, `fsync` on the directory descriptor in `syncDirectory` is not guaranteed to be supported on all macOS filesystems for atomicity.

### Insecure Materialization Buffer Loop (`SecureFileMaterializer.swift`)
*   **Location:** `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`, lines 78-96.
*   **Finding:** The loop handling data writes does not account for partial writes that might not be due to `EINTR` (e.g., `result == 0`). While `guard result > 0` is present, it treats 0 as an `EIO` (which is correct), but the overall logic needs to ensure the file descriptor remains valid across the entire `Data` range write.

---

## 3. Optional Improvements

### Archive Entry Fingerprinting
The current fingerprinting logic in `SourceFingerprint` (`WindowsZIPProfile.swift`, lines 92-112) is strong, but it relies on `fileResourceIdentifier`. For some filesystems, this might be unstable across renames or copies.
*   **Location:** `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/WindowsZIPProfile.swift`, line 108.
*   **Recommendation:** Consider adding content hash (e.g., SHA-256) if the `resourceIdentifier` is determined to be insufficient in future stress tests.

---

## 4. Open-Scope Gates

### Special File Handling
The current implementation suppresses `.DS_Store` and `__MACOSX`, but does not explicitly handle other special files like named pipes, character devices, or sockets beyond rejecting them in `WindowsZIPPreflight.collect`.
*   **Finding:** The current approach is safe (reject-by-default), but documentation should explicitly state this behavior to clarify why these files are excluded from the archive.

---

## Test Verification Analysis
The tests provided (`ZIPArchiveProviderTests.swift`, `WindowsZIPCreationTests.swift`, `SecureFileMaterializerTests.swift`) are high quality. They cover:
*   UTF-8 handling.
*   Suppression of macOS metadata files (`.DS_Store`).
*   Windows-reserved device name rejection.
*   Case-insensitive collision detection.
*   Traversal protection.

**The tests prove the functional claims, but do not yet stress-test C-layer memory stability under high-frequency error injections.** I recommend adding a stress test that opens and closes malformed ZIP files in a loop to ensure no memory leaks occur in the C-bridge.


session_id: 20260712_035503_25a05d
Exception ignored in: <coroutine object MCPServerTask.run at 0x108f59bc0>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x108f59a80>
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
Exception ignored in: <coroutine object MCPServerTask.run at 0x108f59940>
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
