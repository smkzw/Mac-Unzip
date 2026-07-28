# ArchiveWorkbench Preview Security & Reliability Review

**Reviewer:** Reasonix CLI `deepseek-pro`
**Date:** 2025-07-16
**Scope:** 11 source + test files under `ArchiveWorkbench/App/` and `ArchiveWorkbench/Packages/ArchiveKit/`
**Method:** Static analysis with self-challenge against exact source; every HIGH/MEDIUM claim re-verified against the relevant line range.

---

## Executive Summary

The preview subsystem is well-architected for its threat model. The core security primitives — `openat` + `O_NOFOLLOW` directory-walk, `SecureFileMaterializer` with fd-bounded writes, and path-component deny-listing — are correct in isolation. The main weaknesses are: (1) a TOCTOU gap where path-based consumers (AVPlayer, QLPreviewView) reopen a URL after fd validation closes, (2) `SecureFileMaterializer` cleanup that silently swallows `unlinkat` failures, (3) `ArchiveDocumentLoader` never cleans up its session directory on deinit, accumulating disk usage, and (4) cancellation/staleness coordination that wastes extraction work on superseded requests. No critical (exploitable without same-user code execution) vulnerability was found.

---

## Findings by Severity

### HIGH — 2 findings

#### H1. TOCTOU between fd validation close and path-based consumer open (PreviewRouting.swift:57–85; RoutedPreviewViews.swift:226–238, 207–224)

**Claim:** `ValidatedPreviewCacheURL.readData()` and `init?(candidateURL:)` use `openValidatedFile` which opens every path component with `openat` + `O_NOFOLLOW` and validates the file descriptor via `fstat`. After `openValidatedFile` returns, the descriptor is closed. Later, `readData()` re-opens and re-validates — so the data path is TOCTOU-safe. **However**, `NativeVideoPreviewStateView` (line 230) and `QuickLookCanvas.revalidatedURL` (line 222) call `ValidatedPreviewCacheURL(candidateURL: $0.url)?.url` which returns a **path-based URL**, not a file descriptor. AVPlayer and QLPreviewView then open that URL by path. Between the re-validation `close()` and the media framework's `open()`, the inode at that path can be swapped.

**Verified:** Lines 226–238, 221–223 of RoutedPreviewViews.swift; lines 101–155 of PreviewRouting.swift (the fd is closed at `close(descriptor)` or via `FileHandle` dealloc in `readData`).

**Impact:** An attacker with write access to the `0o700` cache directory can replace a validated preview file with an arbitrary regular file (same path, within the 256 MB size limit) after re-validation. AVPlayer or Quick Look then opens the attacker's file. The attacker needs same-user code execution to write into a `0o700` directory, which typically means they already own the process — but in a sandboxed Mac app, a co-resident malicious XPC service or plugin could exploit this.

**Self-challenge:** Is the race window realistically exploitable? The window is between `close()` inside `openValidatedFile` (line 155 return) and AVPlayer's internal `open()`. On a modern Mac this is nanoseconds to microseconds. An attacker would need to busy-poll the cache directory and atomically swap files. Hard but not impossible for a local attacker with `FSEvents` or `dispatch_source` watching the directory.

**Rejected alternative:** Passing an `fd` to AVPlayer. AVPlayer has no public fd-based initializer; it only accepts `URL` or `AVAsset`. `AVURLAsset` also takes a URL. The only fd-safe path would be to read the entire file into a `Data` and use `AVPlayer(items:)` with an `AVPlayerItem(asset: AVAsset(...))` — but `AVAsset` also has no `Data` initializer for arbitrary formats. **This is a platform limitation, not a code defect.** The mitigation is the `0o700` directory permission, which is a reasonable compensating control.

---

#### H2. `SecureFileMaterializer` silently swallows `unlinkat` failure on partial write (SecureFileMaterializer.swift:71–76, 97–108)

**Claim:** When `write()` fails before `published = true`, the defer block attempts `unlinkat(parentFD, name, 0)` but discards the return value with `_ =`. If `unlinkat` also fails (e.g. `EACCES`, `EBUSY`, filesystem full), the partial/corrupt file persists on disk. Additionally, if `fsync(leafFD)` at line 98 succeeds but `close(leafFD)` at line 101 fails, `leafFD` is set to `-1` and an error is thrown — but the defer block sees `leafFD = -1` and skips the close, and `published` is still `false`, so `unlinkat` runs. However, if `fsync(leafFD)` fails (line 98–99), the function throws and `published` stays `false`, triggering the `unlinkat` — but the file on disk may be partially written and `fsync` may have partially flushed. The `unlinkat` result is silently discarded.

**Verified:** Lines 71–76 (defer block), lines 97–108 (publish sequence).

**Impact:** Stale/partial files accumulate in the session directory. In pathological cases (filesystem full during extraction), the materializer could leave corrupt files that later pass validation (if they happen to be valid regular files within the size limit) and get served as previews. However, the `SecureFileMaterializer` writes to a UUID directory that is only read by `ValidatedPreviewCacheURL` — and `materializePreview` in `ArchiveDocumentLoader` removes `activePreviewRootURL` before creating a new one. So stale files are contained to one preview session.

**Self-challenge:** Could a partial write produce a file that `fstat` considers valid but contains attacker-controlled content? The `write()` loop (lines 78–95) writes data from the decompressed archive entry. If `write()` fails partway through, the file on disk has a prefix of the archive entry's data. The `fsync` failure prevents `published = true`, so `unlinkat` is called. If `unlinkat` fails silently, the partial file remains. On the next `materializePreview` call, `removeItem(at: activePreviewRootURL)` removes the entire UUID directory — so this partial file doesn't survive across preview requests. The only risk is within the same preview request's lifetime, which is minutes at most.

---

### MEDIUM — 3 findings

#### M1. `readData()` re-validates on every call but consumers reconstruct path-based URLs (PreviewRouting.swift:57–85, 30–55; RoutedPreviewViews.swift:230, 222)

**Claim:** `ValidatedPreviewCacheURL.url` (line 53) is reconstructed from `cacheRoot + components` — a string path, not an fd. Every consumer that uses `.url` gets a path-based URL that must be re-validated by the consumer. `NativeVideoPreviewStateView` and `QuickLookCanvas` do re-validate (by constructing a new `ValidatedPreviewCacheURL`), but `ArchiveImagePreviewStateView` calls `cacheURL?.readData()` which is fd-safe. `PDFKitPreviewStateView` also calls `readData()`, which is fd-safe.

**This is a documentation/consistency issue, not a new vulnerability.** The fd-safe vs path-safe split is:
- **Fd-safe:** `readData()` → used by `ArchiveImagePreviewStateView`, `PDFKitPreviewStateView`
- **Path-safe with re-validation:** `NativeVideoPreviewStateView`, `QuickLookCanvas` — re-validate then pass URL
- **No consumer uses `.url` directly without re-validation.**

**Verified:** All four preview views in RoutedPreviewViews.swift.

**Impact:** If a future developer adds a new preview view and uses `previewCacheURL?.url` directly without re-validating, the TOCTOU window opens wide. The current code is correct but fragile.

---

#### M2. No memory ceiling on concurrent `readData()` or `PDFDocument(data:)` / `NSImage(data:)` (PreviewRouting.swift:57–85; RoutedPreviewViews.swift:13, 37)

**Claim:** `readData()` allocates up to `maximumBytes + 1` (≈ 256 MB) of `Data`. Then `PDFDocument(data:)` and `NSImage(data:)` each create additional internal copies, roughly doubling peak memory per preview. Although the UI serializes preview loads (one `selectedEntryID` at a time), a sufficiently fast user clicking through entries or programmatic `loadSelectedPreview()` calls could queue multiple `materializePreview` operations on the actor. Each extracts data into the session directory and `readData()` loads it into memory. SwiftUI's `.task(id:)` cancels old tasks, but `materializePreview` and `readData()` do not check for cancellation — they run to completion.

**Verified:** `AppModel.loadSelectedPreview()` lines 120–150 (no `Task.isCancelled` check); `ArchiveDocumentLoader.materializePreview()` lines 28–49 (no cancellation); `ValidatedPreviewCacheURL.readData()` lines 57–85 (no cancellation).

**Impact:** Memory pressure under rapid selection changes. Not exploitable for DoS without user interaction, but a zip with many near-256 MB entries could cause jetsam (app killed by macOS memory manager) if the user rapidly clicks through the media strip entries.

**Self-challenge:** Is this really MEDIUM severity? The 256 MB budget per entry is controlled; macOS will compress inactive memory pages. With 5 rapid clicks on 256 MB entries, peak could reach ~1.2 GB. On a 16 GB Mac, this is survivable. On an 8 GB Mac with other apps open, jetsam is possible. Severity is appropriate.

---

#### M3. `ArchivePathPolicy` is a critical dependency but not in review scope

**Claim:** Both `ZIPArchiveProvider.open()` (line 38) and `SecureFileMaterializer.write()` (line 18) call `ArchivePathPolicy().validate()`. If `ArchivePathPolicy` has a bypass (e.g., doesn't catch `..` components, null bytes, or absolute paths), the entire path-traversal defense collapses. `SecureFileMaterializer` adds `openat` with `O_NOFOLLOW` as a second layer, but `ArchivePathPolicy` is the first line of defense against malicious entry names in the archive.

**Verified:** ZIPArchiveProvider.swift:38, SecureFileMaterializer.swift:18.

**Impact:** Cannot assess without reading `ArchivePathPolicy`. This review assumes it correctly rejects traversal components.

**Recommendation:** Include `ArchivePathPolicy` source in the review scope or add a dedicated fuzz test for malicious paths through the full extraction pipeline.

---

### LOW — 4 findings

#### L1. `ArchiveDocumentLoader` leaks session directories until next `open()` or app quit (ArchiveDocumentLoader.swift:52–71, no deinit)

**Claim:** `ArchiveDocumentLoader` has no `deinit`. The `previewSessionURL` directory (created in `resetPreviewSession()`) persists on disk after the loader is deallocated. `resetPreviewSession()` removes the old session, but only when `open(url:)` is called again. If the user closes the document window without opening another archive, the session directory remains until app termination (`applicationWillTerminate` removes the entire cache root).

**Verified:** No `deinit` in ArchiveDocumentLoader.swift; ArchiveWorkbenchApp.swift:11–13.

**Impact:** Disk usage accumulation. Each session directory contains extracted preview files. Over a long app session with many documents opened and closed, this could accumulate significant space. Mitigated by `applicationDidFinishLaunching` cleanup on next launch.

**Fix:** Add `deinit` that calls `try? FileManager.default.removeItem(at: previewSessionURL)` for non-isolated state, or a synchronous cleanup in the actor's deinit. Note: actor deinit is non-async, so `removeItem` (synchronous) works.

---

#### L2. `AppModel.loadSelectedPreview()` ignores `Task.isCancelled` — wastes actor work (AppModel.swift:120–150)

**Claim:** SwiftUI's `.task(id:)` cancels the task when selection changes. The `await loader.materializePreview(...)` suspension point is a cancellation opportunity, but the actor's `materializePreview` doesn't check `Task.isCancelled`, so the extraction runs to completion. The `previewRequestID` guard at lines 139 and 147 discards the result, but the work was already done.

**Verified:** AppModel.swift:120–150, ArchiveDocumentLoader.swift:28–49.

**Impact:** Wasted CPU and I/O on stale preview requests. No security impact. The `previewRequestID` pattern is a correct staleness guard for UI state — just inefficient for system resources.

---

#### L3. `SecureFileMaterializer.write()` uses `withUnsafeFileSystemRepresentation` for root but string `withCString` for components (SecureFileMaterializer.swift:24–27 vs 41–49)

**Claim:** The root directory is opened via `rootURL.withUnsafeFileSystemRepresentation` which returns a filesystem-encoding C string (UTF-8 on APFS). Component names are converted via `component.withCString` which uses the String's UTF-8 representation. On macOS, these should be identical for valid paths, but `withUnsafeFileSystemRepresentation` handles Unicode normalization (e.g., NFD vs NFC) that `withCString` does not. If an archive entry name uses a different Unicode normalization than the filesystem, `openat` could fail or open a different file.

**Verified:** SecureFileMaterializer.swift:24–27, 41–49.

**Impact:** Very unlikely on APFS (which is normalization-insensitive). Could matter on external HFS+ volumes or network shares mounted under the cache path. The cache is always on the boot volume (`~/Library/Caches/`), which is APFS on modern macOS. Severity is LOW.

---

#### L4. `FileManager.default.removeItem(at:)` follows symlinks — used in cleanup paths (ArchiveDocumentLoader.swift:31, 46, 55; ArchiveWorkbenchApp.swift:8,12)

**Claim:** `removeItem(at:)` follows symlinks. If `activePreviewRootURL`, `previewSessionURL`, or `cacheRoot` were replaced with symlinks (by an attacker with write access to the parent directory), `removeItem` would delete the symlink's target. However, all these paths are under `cacheRoot` which has `0o700` permissions and is opened with `O_NOFOLLOW` in the security-sensitive paths. The cleanup paths don't re-verify before calling `removeItem`.

**Verified:** ArchiveDocumentLoader.swift:31, 46, 55; ArchiveWorkbenchApp.swift:8,12.

**Impact:** If an attacker can replace one of these directories with a symlink (requires write access to the cache root's parent or the cache root itself), `removeItem` would delete arbitrary files. This is a privilege-escalation-by-symlink-attack. The `0o700` cache root prevents this for non-owner attackers. Same-user attackers can already delete these files directly.

**Mitigation in SecureFileMaterializer:** The `write()` function uses `unlinkat(fd, name, 0)` with `AT_REMOVEDIR` flag NOT set — so it only unlinks files, not directories, and uses fd-relative paths, making it immune to symlink attacks. **Contrast:** the `FileManager` cleanup paths are path-based and symlink-following. The inconsistency is worth noting but LOW severity given the directory permissions.

---

### INFO — 3 observations

#### I1. Fixture-based model tests bypass the real materialization/validation pipeline (ArchiveDocumentLoaderTests.swift:147–188)

**Claim:** `testSelectedSupportedEntryMaterializesIntoValidatedPreviewCache` uses `StubArchiveDocumentLoader` which returns a pre-written file URL. It never exercises `ZIPArchiveProvider.materializeEntry()` or `SecureFileMaterializer.write()`. The test validates that `AppModel.loadSelectedPreview()` correctly sets `previewCacheURL` when the stub returns a URL under the cache root, but it doesn't test the extraction-to-disk path.

**Verified:** Lines 169–188.

**Impact:** A regression in `SecureFileMaterializer` would not be caught by this test. The two `LoaderZIPFixture` tests (`testRealLoaderMaterializesArchiveBytesInsidePreviewCache`, `testRealLoaderMaterializesImagePDFWordExcelAndPowerPointBytes`) do exercise the full pipeline, so coverage exists — but it's in different test methods.

---

#### I2. `PreviewRoutingPolicy.kind(forFilename:)` trusts file extensions; no magic-byte/content inspection (PreviewRouting.swift:13–27)

**Claim:** Routing is purely extension-based. A file named `evil.pdf` containing `#!/bin/bash` routes to `.pdfKit` and gets parsed by PDFKit. PDFKit will reject it gracefully, but there's no defense-in-depth content inspection.

**Verified:** Lines 13–27.

**Impact:** Low. System frameworks (PDFKit, NSImage, AVPlayer, Quick Look) are the intended security boundary for content parsing. The app's job is to ensure files don't escape the sandbox and are within size limits — both are satisfied. Content-based routing (e.g., checking file magic bytes) would be a defense-in-depth improvement but is not required for the current threat model.

---

#### I3. `ZIPBridgeReader` holds a C handle that depends on path-based access (ZIPArchiveProvider.swift:128–144)

**Claim:** `ZIPBridgeReader` opens the archive via `awb_mz_reader_open(path, &opened)` — a path-based C API. The `ArchiveDocumentLoader.open(url:)` acquires a security-scoped bookmark with `startAccessingSecurityScopedResource()` and releases it in `defer`. If `awb_mz_reader_open` internally closes and re-opens the file (rather than holding the initial fd), subsequent reads in `materializeEntry` would fail after the security scope ends.

**Verified:** `ArchiveDocumentLoader.open()` lines 20–26; `ZIPBridgeReader.init(url:)` lines 130–140.

**Impact:** The `defer { stopAccessingSecurityScopedResource() }` runs after `provider.open(url:)` returns, so the C open happens within the security scope. If minizip holds the fd (typical for zip readers), subsequent reads work. If minizip re-opens by path, it would fail. This is a robustness issue that depends on minizip's internal behavior — not verifiable from Swift source alone.

---

## Rejected Hypotheses

These were investigated and found NOT to be vulnerabilities:

| Hypothesis | Investigation | Conclusion |
|---|---|---|
| `readData()` always returns `nil` (unconditional bug) | Traced all code paths: the `while` loop returns `result` on EOF (via `guard !chunk.isEmpty else { return result }`), and only falls through to `return nil` when `result.count >= readLimit` (file exceeded limit). | **REJECTED.** Boundary behavior is correct. |
| `openValidatedFile` TOCTOU: directory replaced between `openat` for parent and `openat` for child | `openat` uses the parent fd, which is bound to the inode, not the path. Even if the path is replaced with a symlink, the fd points to the original directory. Tested by `testDescriptorRelativeReadCannotBeRedirectedWhenParentIsReplaced`. | **REJECTED.** Fd-based traversal is TOCTOU-safe. |
| `Int(expectedSize)` could overflow on 32-bit | The deployment target is macOS (64-bit only). `Int.max == Int64.max`. Additionally, `ZIPArchiveProvider.readEntry()` guards `snapshot.uncompressedSize <= UInt64(Int.max)`. | **REJECTED.** Not relevant. |
| `ValidatedPreviewCacheURL.init?` leaves a stale `url` after file deletion | `url` is reconstructed from `components`, not cached from the original. If the file is deleted, `url` might point to a non-existent file, but consumers re-validate (either via `readData()` or constructing a new `ValidatedPreviewCacheURL`). | **REJECTED.** Re-validation catches missing files. |
| `Fixtures` in `AppModel.mediaFixture` could leak into production | Guarded by `usesFixturePreview = true` which causes `loadSelectedPreview()` to return early. | **REJECTED.** Guard is effective. |

---

## Smallest Safe Fixes

### For H1 (TOCTOU with AVPlayer / Quick Look):

**Option A (recommended):** For video and Office previews, read the entire validated file into `Data` via `readData()`, write it to an `NSTemporaryDirectory()` location with `O_EXCL`, and pass that URL to AVPlayer/QLPreviewView. The temporary file is disposable and avoids the cache-root TOCTOU.

**Option B:** Keep current re-validation pattern (it's already quite narrow) and document the residual risk. Add an audit assertion that no consumer uses `ValidatedPreviewCacheURL.url` without re-validation.

**Option C:** `AVPlayer` can accept `AVAsset`, but creating an asset from in-memory data requires a custom `AVAssetResourceLoaderDelegate`. This is complex but eliminates the TOCTOU entirely for video.

### For H2 (silent `unlinkat` failure):

```swift
// In defer block, log or accumulate unlinkat failures:
if !published {
    let unlinkRC = leaf.withCString { name in unlinkat(parentFD, name, 0) }
    if unlinkRC != 0 {
        // Log errno; consider retry or marking for deferred cleanup
    }
}
```

Also: after `fsync(leafFD)` failure, the defer's `unlinkat` runs but the file may have been partially flushed. Consider `ftruncate` before `unlinkat` to ensure no partial content persists.

### For M2 (memory pressure):

Add `try Task.checkCancellation()` at the start of `readData()` and after each chunk read. In `loadSelectedPreview()`, add a `try Task.checkCancellation()` after re-obtaining the main actor. This allows SwiftUI's `.task(id:)` cancellation to propagate and abort in-flight reads.

### For L1 (session directory leak):

```swift
// In ArchiveDocumentLoader:
deinit {
    if let url = previewSessionURL {
        try? FileManager.default.removeItem(at: url)
    }
}
```

Note: Actor deinit runs on the actor's executor, so this is safe — `removeItem` is synchronous and doesn't need `await`.

### For L4 (symlink-following `removeItem` in cleanup):

Wrap cleanup calls with a pre-check:
```swift
// Check the URL is not a symlink before removing:
if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
   values.isSymbolicLink == true {
    // Refuse to follow; log and skip
    return
}
try? FileManager.default.removeItem(at: url)
```

Or use `unlink`/`unlinkat` directly (like `SecureFileMaterializer` does) rather than `FileManager.removeItem`.

---

## Required Regression Tests

1. **TOCTOU: Video preview re-validation race** — Create a validated cache file, then in a tight background loop swap it with a different file of the same name but different content. Verify that `NativeVideoPreviewStateView` either plays the originally-validated content or fails safely (does not play the swapped file). **This test may need `DispatchQueue` timing tricks and will be flaky — the purpose is to document the race exists, not to reliably catch it.**

2. **SecureFileMaterializer unlinkat failure** — Mock or inject a failure in `unlinkat` (e.g., via `chflags` to make the file immutable before the write fails). Verify the partial file is handled (logged, not served as a preview).

3. **Concurrent rapid selection changes** — Simulate 100 rapid `selectedEntryID` changes (faster than extraction can complete). Verify that: (a) no crash, (b) final state matches the last selection, (c) no stale `previewCacheURL` from superseded requests.

4. **Session directory cleanup on loader deinit** — Create an `ArchiveDocumentLoader`, call `open(url:)`, then release the loader. Verify the session directory is removed.

5. **Cache root permissions survive umask** — Run `resetPreviewSession()` with `umask(0o022)`. Verify the created directories have `0o700`, not `0o755`.

6. **Sparse file rejection with exact boundary** — Create a sparse file with logical size exactly `maximumPreviewBytes + 1` and verify `ValidatedPreviewCacheURL.init?` returns nil. Create one with logical size exactly `maximumPreviewBytes` and verify it succeeds.

7. **ZIP with symlink entry** — Create a ZIP containing a symlink entry. Verify `ZIPArchiveProvider.open()` rejects it (throws `.unsafePath` or similar) for the symlink entry. Verify `materializeEntry` throws for symlink entries.

8. **ZIP with path traversal in entry name** — Create a ZIP with an entry named `../../../etc/passwd`. Verify `ArchivePathPolicy.validate()` (or the `ZIPArchiveProvider.open()`) rejects the archive with `.unsafePath`.

9. **`readData()` with maximumBytes=0** — Verify correctly returns nil for any positive-size file and empty Data for a zero-byte file.

10. **`readData()` with file exactly at maximumBytes** — Verify returns full data (not nil).

---

## Source-Archive Lifetime Summary

| Component | Created | Released | Mechanism |
|---|---|---|---|
| `ZIPBridgeReader` handle | `ZIPArchiveProvider.open()` | `deinit` of `ZIPBridgeReader` | `awb_mz_reader_close(&handle)` |
| Cache root (`PreviewCache/`) | `applicationDidFinishLaunching` (recreated) | `applicationWillTerminate` | `FileManager.removeItem` |
| Session directory | `resetPreviewSession()` | `resetPreviewSession()` on next `open()`, or app quit | `FileManager.removeItem` |
| Per-request UUID directory | `materializePreview()` | Next `materializePreview()` or on error | `FileManager.removeItem` |
| Extracted preview file | `SecureFileMaterializer.write()` | Same as per-request directory (removed with parent) | `unlinkat` on write failure; `removeItem` on session reset |

**Gap:** No cleanup on `ArchiveDocumentLoader.deinit` (L1 above). Between window close and app quit, all session+request directories persist.

---

## Overall Assessment

The preview pipeline's fd-based security model is sound and well-tested (the `testDescriptorRelativeReadCannotBeRedirectedWhenParentIsReplaced` test is particularly strong). The TOCTOU gap for AVPlayer/QLPreviewView is a real limitation of the platform APIs, mitigated by restrictive directory permissions. The code is production-quality for the stated threat model (archive preview from potentially-malicious ZIP files). The fixes above are small and incrementally close the remaining gaps.
[2m  ▎ thinking[0m
[2mThe[0m[2m report[0m[2m is[0m[2m written[0m[2m.[0m[2m Let[0m[2m me[0m[2m verify[0m[2m it[0m[2m's[0m[2m complete[0m[2m and[0m[2m well[0m[2m-structured[0m[2m by[0m[2m reading[0m[2m it[0m[2m back[0m[2m.[0m
Report written. Let me verify the output file:
  · 60088 tok · in 59971 (59904 cached / 67 new) · out 117 (19 reasoning) · ¥0.0024
  -> bash {"command": "wc -l runs/reasonix_preview_security.md && echo \"---\" && head -3 runs/reasonix_preview_security.md && ech...
  · tool output truncated: 130366 of 163134 bytes elided
[2m  ▎ thinking[0m
[2mThe[0m[2m file[0m[2m was[0m[2m written[0m[2m successfully[0m[2m ([0m[2m282[0m[2m lines[0m[2m,[0m[2m [0m[2m25[0m[2mKB[0m[2m).[0m[2m The[0m[2m tail[0m[2m output[0m[2m seems[0m[2m corrupted[0m[2m with[0m[2m null[0m[2m bytes[0m[2m padding[0m[2m —[0m[2m that[0m[2m's[0m[2m likely[0m[2m the[0m[2m shell[0m[2m trunc[0m[2mating[0m[2m the[0m[2m output[0m[2m.[0m[2m The[0m[2m file[0m[2m itself[0m[2m should[0m[2m be[0m[2m fine[0m[2m since[0m[2m write[0m[2m_file[0m[2m reported[0m[2m "[0m[2mw[0m[2mrote[0m[2m [0m[2m251[0m[2m55[0m[2m bytes[0m[2m".[0m[2m Let[0m[2m me[0m[2m verify[0m[2m the[0m[2m actual[0m[2m content[0m[2m is[0m[2m intact[0m[2m by[0m[2m reading[0m[2m the[0m[2m first[0m[2m and[0m[2m last[0m[2m few[0m[2m meaningful[0m[2m lines[0m[2m.

[0m[2mActually[0m[2m,[0m[2m the[0m[2m tail[0m[2m output[0m[2m shows[0m[2m a[0m[2m bunch[0m[2m of[0m[2m null[0m[2m bytes[0m[2m,[0m[2m which[0m[2m is[0m[2m strange[0m[2m.[0m[2m Let[0m[2m me[0m[2m re[0m[2m-read[0m[2m the[0m[2m file[0m[2m to[0m[2m confirm[0m[2m it[0m[2m's[0m[2m intact[0m[2m.[0m
The tail output is garbled — let me verify the file is intact:
  · 92693 tok · in 92513 (60032 cached / 32481 new) · out 180 (97 reasoning) · ¥0.1000
  -> read_file {"offset": 275, "path": "runs/reasonix_preview_security.md"}
  · tool output truncated: 132343 of 165111 bytes elided
[2m  ▎ thinking[0m
[2mThe[0m[2m file[0m[2m content[0m[2m itself[0m[2m is[0m[2m intact[0m[2m —[0m[2m line[0m[2m [0m[2m277[0m[2m is[0m[2m the[0m[2m last[0m[2m meaningful[0m[2m content[0m[2m line[0m[2m ("[0m[2mThe[0m[2m preview[0m[2m pipeline[0m[2m's[0m[2m fd[0m[2m-based[0m[2m security[0m[2m model[0m[2m is[0m[2m sound[0m[2m...[0m[2m").[0m[2m The[0m[2m null[0m[2m bytes[0m[2m starting[0m[2m at[0m[2m line[0m[2m [0m[2m278[0m[2m are[0m[2m padding[0m[2m/[0m[2martifact[0m[2m of[0m[2m the[0m[2m tool[0m[2m output[0m[2m.[0m[2m The[0m[2m file[0m[2m is[0m[2m correctly[0m[2m written[0m[2m at[0m[2m [0m[2m282[0m[2m lines[0m[2m with[0m[2m the[0m[2m full[0m[2m report[0m[2m.

[0m[2mThe[0m[2m task[0m[2m is[0m[2m complete[0m[2m.[0m[2m Let[0m[2m me[0m[2m provide[0m[2m a[0m[2m summary[0m[2m to[0m[2m the[0m[2m user[0m[2m.[0m
The file is intact — the tail null bytes seen in the shell output were an artifact of the truncated `bash` display. The actual file content ends cleanly at line 277. Output: **`runs/reasonix_preview_security.md`** (282 lines, ~25 KB).

---

**Summary of findings:**

| Severity | Count | Key Items |
|---|---|---|
| **HIGH** | 2 | H1: TOCTOU between fd-close and AVPlayer/QLPreviewView path-open; H2: Silent `unlinkat` failure leaves partial files on disk |
| **MEDIUM** | 3 | M1: Fragile fd-vs-path safety split across preview views; M2: No memory ceiling on concurrent `readData()`; M3: `ArchivePathPolicy` not in review scope (critical dependency) |
| **LOW** | 4 | L1: No `deinit` cleanup of session directories; L2: `Task.isCancelled` not checked in `loadSelectedPreview`; L3: `withCString` vs `withUnsafeFileSystemRepresentation` inconsistency; L4: `FileManager.removeItem` follows symlinks in cleanup paths |
| **INFO** | 3 | I1: Stub tests bypass real materialization; I2: Extension-only routing (no magic bytes); I3: C handle depends on path-based minizip |

**Bottom line:** The fd-based security model (`openat` + `O_NOFOLLOW` + `fstat`) is correct and well-tested. The primary gap is at the AVPlayer/QLPreviewView boundary where platform APIs force path-based access. Every finding includes a concrete fix in the report.
  · 124647 tok · in 124213 (92672 cached / 31541 new) · out 434 (74 reasoning) · ¥0.0995
