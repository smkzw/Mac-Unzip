# Reasonix Task Plan: archive_helper_security

Date: 2026-07-12
Task: Security-focused implementation critique and bounded patch plan for Task 7 (Helper Isolation and Password-Transport Security Spike)
Status: Pre-implementation review — no HelperSpike code exists yet

---

## Boundary Check

### Sources read (authorized)
| File | Lines/size | Status |
|------|-----------|--------|
| `context/archive_helper_security_context.md` | 55 lines | Read in full |
| `docs/superpowers/plans/2026-07-11-archive-workbench-foundation.md` Task 7 | Lines 766–858 | Read in full |
| `design/2026-07-11_full_design_spec.md` | §17–22, §30 | Read key security sections |
| `ArchiveWorkbench/project.yml` | 85 lines | Read in full |
| `ArchiveWorkbench/Config/Base.xcconfig` | 10 lines | Read in full |
| `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveCapability.swift` | 27 lines | Read in full |
| `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ArchivePathPolicy.swift` | 55 lines | Read in full |
| `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ResourceBudget.swift` | 93 lines | Read in full |

### Sources NOT read (not authorized — not in context list)
- No production paths accessed
- No `/Users/smkzw/.hermes/` paths accessed
- No web fetches performed
- No browser/PPT/PDF/image inspection performed

### Pre-existing code inventory (relevant to Task 7)
- **HelperSpike/**: Does not exist — no code to critique
- **HelperSpikeTests/**: Does not exist
- **Docs/security-spike-results.md**: Does not exist
- **ArchiveSecurity**: Only path-policy and resource-budget code (Task 4). No process-isolation, fd-hygiene, or password-transport code.
- **ArchiveDomain**: Only value types (ArchiveFormat, ArchiveEntry, ArchiveError, ArchiveAction, ProviderID, CapabilitySnapshot, CapabilityRegistry). No provider result types.
- **Package.swift**: Targets for ArchiveDomain, ArchiveSecurity, ArchiveOperations, ArchiveFixtures and their tests. No HelperSpike targets.
- **project.yml**: Targets for ArchiveWorkbench (app), ArchiveWorkbenchAppTests (UI), ArchiveWorkbenchUnitTests. No HelperSpike scheme entries.

### Boundary conclusion
This is a **greenfield pre-implementation review**. The plan in `docs/superpowers/plans/2026-07-11-archive-workbench-foundation.md` Task 7 defines the intended implementation contract. Below I audit that contract for security gaps, false-positive test risks, race/deadlock/leak paths, and identify exactly which verification steps Reasonix can perform vs. which Codex must own.

---

## Reasonix-Safe Work

Reasonix can produce the bounded deliverables below without live Xcode, browser, 7zz execution, or visual inspection. Everything below is source-code analysis, design-gap detection, and structured planning derived from the authorized documents.

### 2.1 — Security Gap Audit of the Task 7 Plan Contract

#### Gap 1: PTY vs. Pipe — the plan is ambiguous on wire format

**Finding (Important):** The plan alternates between "pipe or PTY" (Step 2 description) and "stdin/PTY" (design spec §18.459). These are fundamentally different transport mechanisms:

- **Pipe (byte-stream, no echoing, no line discipline):** A pipe's write-end connected to child stdin is simple and safe — bytes written by parent arrive exactly as written, no transformation. However, 7zz's interactive password mode may require a TTY (it calls `isatty()` or reads from `/dev/tty`). If 7zz 26.02 requires an actual terminal device for `-p` (no-value) interactive prompting, a plain pipe will fail silently — the child will hang waiting for TTY input that never arrives, and the password timeout will fire, looking like a child crash rather than a capability gap.

- **PTY (pseudo-terminal, line discipline, potential echo):** A PTY provides `isatty() == true` and satisfies tools that demand a terminal. But it introduces:
  - **Echo risk:** If the child's terminal settings enable `ECHO`, the password bytes written by the parent may be echoed back through the PTY master and appear in the stdout drain buffer. The plan's password-channel test (`result.receivedPasswordSHA256`) checks the child's own hash computation, not the PTY echo path. A PTY echo would leak the password into the parent's stdout capture.
  - **CR/LF translation risk:** Default PTY line discipline may translate `\n` to `\r\n` on output.
  - **Buffering:** PTY line discipline may buffer until newline, delaying delivery of the password to the child. The plan's `timeout: .seconds(5)` may be too tight.

**Mitigation required:** The implementation must:
1. Probe both pipe and PTY transports for 7zz 26.02.
2. Before writing the password through a PTY, disable `ECHO` on the child's terminal via `tcsetattr` on the master fd.
3. If using a pipe: verify 7zz 26.02 actually reads the password from stdin (not `/dev/tty`). Test by spawning without a controlling terminal.
4. Record the transport used (pipe or PTY) in `ProviderSpikeResult` so the evidence chain is explicit.

#### Gap 2: Concurrent drain ordering — deadlock risk on password write

**Finding (Critical):** The plan says to "concurrently drain stdout/stderr into capped buffers" but does not specify the ordering relative to the password write. The deadlock scenario:

```
Parent: posix_spawn -> child starts
Parent: writes password to child stdin (blocking)
Child: fills stderr pipe buffer (64KB on macOS) -> child blocks on write(stderr, ...)
Child: never reaches read(stdin, ...) because stderr is blocked
Parent: blocked on write(stdin, ...) waiting for child to read
→ DEADLOCK (broken by timeout only)
```

7zz is known to emit substantial diagnostic output to stderr before reading the password (progress messages, scanning messages, header parsing). If the parent is not actively draining stderr before and during the password write, this deadlock is practically guaranteed for larger archives.

**Mitigation required:** The implementation must:
1. Start concurrent stdout+stderr drain tasks **before** writing the password.
2. The drain tasks must use async I/O or run on a separate thread (DispatchIO or a dedicated Task.detached) — they cannot be cooperative tasks that yield to the password-write task on the same executor.
3. For PTY transport: drain the master fd as well, since echo or line-discipline artifacts may appear there.

#### Gap 3: Swift 6 noncopyable zeroization — COW escape and optimizer elision

**Finding (Important):** The plan's `SecureBytes` type:

```swift
struct SecureBytes: ~Copyable {
    private var storage: ContiguousArray<UInt8>
    borrowing func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.withUnsafeBytes(body)
    }
    mutating func zero() {
        storage.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
    }
    var isZeroed: Bool { storage.allSatisfy { $0 == 0 } }
    deinit { storage.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
}
```

Three concerns:

1. **ContiguousArray COW (copy-on-write):** `ContiguousArray` is a value type with COW semantics. If Swift's optimizer or a code path creates a copy of the `ContiguousArray` (even transiently), the `withUnsafeMutableBytes` in `zero()` might zero a copy, leaving the original in memory. The `~Copyable` marker on the outer struct prevents `SecureBytes` from being copied, but `ContiguousArray` itself is `Copyable`. A `borrowing` access followed by a `mutating` access could theoretically trigger a copy if the compiler can't prove exclusivity.

2. **Optimizer elision of zeroing writes:** Swift's optimizer can legally remove "dead stores" — writes to memory that is about to be deallocated. If `zero()` is called immediately before the struct goes out of scope, the optimizer might elide the zeroing write, reasoning that the deallocation makes it unnecessary. The `deinit` zeroing is also vulnerable to the same elision. Defense: use `UnsafeMutablePointer` with `OpaquePointer` barriers or call `memset_s` (C11 Annex K) through a C interop function that the optimizer cannot see through.

3. **`borrowing` parameter — no copy guarantee:** Swift 6.3 `borrowing` parameters prevent implicit copies of the outer struct, but the callee receives a borrow, not ownership. If the callee's body causes a copy of the `ContiguousArray` through a method that triggers COW, the borrow semantics don't prevent it. The safe pattern is:
   - Provide an explicit `consuming` method that takes ownership, extracts the password, writes it to the child fd, then zeros and discards.
   - Never expose the raw bytes through a `borrowing` accessor that returns the buffer to arbitrary callers.

#### Gap 4: Process-group creation and reaping completeness

**Finding (Important):** The plan mentions "terminate the whole child process group" but doesn't specify:

1. **Process-group creation:** The child must call `setpgid(0, 0)` before `exec`. This creates a new process group with the child as leader. Without it, `kill(-pid, SIGKILL)` targets the parent's process group instead.

2. **Double-setpgid race:** There's a classic race: between `posix_spawn` return and the child's first instruction, the parent hasn't called `setpgid`. The child could `exec` before the parent sets the group, leaving the child in the parent's group. Fix: Use `POSIX_SPAWN_SETPGROUP` with `POSIX_SPAWN_PGROUP_SET(0)` in the spawn attributes, eliminating the race entirely.

3. **Reaping after SIGKILL:** After `kill(-pgid, SIGKILL)`, the parent must `waitpid(-pgid, ...)` (with `WNOHANG` in a loop) to reap all children in the group. A single `waitpid(childPid, ...)` only reaps the direct child; grandchildren remain zombies.

4. **PID reuse after early exit:** If the child exits normally between the last `waitpid` check and the timeout, and the PID is reused, `kill(pid, SIGKILL)` targets an innocent process. Mitigation: record the child's `waitpid` exit status; if already exited, skip the kill.

#### Gap 5: `posix_spawn_file_actions` completeness — inherited fd audit

**Finding (Important):** The plan says to use `posix_spawn_file_actions` with close-on-exec but doesn't enumerate:

1. **Close-everything-except strategy:** On macOS, `posix_spawn` does NOT automatically close all open file descriptors. The plan must either:
   - Use `posix_spawn_file_actions_addclose` for every fd except 0/1/2 and the pipe/PTY endpoints, OR
   - Set `POSIX_SPAWN_CLOEXEC_DEFAULT` (macOS 13+) to make all fds close-on-exec by default, then explicitly dup the intended fds onto 0/1/2.

2. **POSIX_SPAWN_CLOEXEC_DEFAULT availability:** This flag was introduced in macOS 13 (Ventura). Since the deployment target is macOS 26.0, it is available. This is the **strongly recommended approach** because it avoids the enumeration problem entirely.

3. **fd leak on spawn failure:** If `posix_spawn` fails (e.g., executable not found), the pipe/PTY fds created in the file actions may not be closed. The implementation must close them in the failure path.

#### Gap 6: Bounded buffer semantics — truncation vs. blocking

**Finding (Moderate):** The plan specifies `stdoutBytes: 64 * 1024` and `stderrBytes: 64 * 1024` limits. It's unclear what happens when the limit is reached:

- **Truncation:** Stop reading, close the read-end of the pipe, causing the child to get SIGPIPE (or EPIPE on write). This could kill the child before it processes the password, leaving the operation incomplete.
- **Discard-but-continue:** Keep reading but discard bytes. This prevents the pipe from filling and the child from blocking, but silently loses data that might contain error information.
- **Block-and-error:** Return a `resourceLimit` error. But by this point the password may already have been written.

**Recommendation:** The buffer must be a **ring buffer** that drains the pipe continuously (preventing the child from blocking) but only retains the first N bytes. Once the cap is reached, subsequent bytes are counted (for diagnostics) but discarded. The drain must never stop reading while the child is alive, even when the cap is exceeded.

#### Gap 7: Fixed 7zz interactive-password command matrix

**Finding (Important):** The plan's Step 3 specifies four operations: "encrypted create/list/test/extract". The 7zz 26.02 behavior for `-p` (no value) interactive mode must be verified per operation:

| Operation | Command | Interactive `-p` support? | Risk |
|-----------|---------|---------------------------|------|
| Create | `7zz a -p -mhe=on file.7z file` | Expected: prompts for password | May prompt twice (enter + confirm) |
| List | `7zz l -p file.7z` | Unknown for 26.02 | May fail or require `-p` with value |
| Test | `7zz t -p file.7z` | Unknown for 26.02 | Same as list |
| Extract | `7zz x -p file.7z` | Unknown for 26.02 | Same as list |

**Critical:** 7zz `-p` without a value is documented to read the password from stdin. But the behavior differs by operation:
- For `a` (add): It may prompt twice for password confirmation, requiring the parent to write the password **twice** to stdin.
- For `l`/`t`/`x`: It reads once, but **only if the archive is encrypted**. If the archive has no encryption, 7zz may ignore stdin entirely, and the password bytes sit in the pipe buffer unread (not a leak, but the child never consumes them).

The fixture test must:
1. First determine 7zz 26.02's exact interactive behavior per operation with a non-sensitive probe.
2. For create: handle the double-prompt (write password + newline twice).
3. For extract/list/test: verify the archive IS encrypted before counting on stdin consumption.

#### Gap 8: `ProviderSpikeResult` schema — missing transport and environment evidence

**Finding (Moderate):** The plan's `ProviderSpikeResult` only captures: provider, version, status, commandArgumentHash, outputSHA256, failureCode. It should also capture:

- **transportUsed:** `pipe` or `pty` — to distinguish the transport for the evidence trace.
- **processGroupReaped:** Whether all children in the process group were confirmed reaped.
- **sandboxMode:** `sandboxed` or `hardenedNonSandboxed` — which configuration the result was obtained under.
- **interactivePasswordSupported:** Whether 7zz actually read from stdin in interactive mode (vs. `/dev/tty`).
- **duration:** Wall-clock duration including drain.

### 2.2 — Likely False-Positive Tests

| Test | False-positive mechanism | Fix |
|------|--------------------------|-----|
| `password.isZeroed` after `zero()` | Optimizer elision of dead store. Memory may contain password but appear zero because the read is elided or a copy was tested. | Use `memset_s` through a C shim; verify `isZeroed` reads through `volatile`-like barrier. Test: fill with random, verify non-zero, then zero, then verify zero — all in one scope to prevent reordering. |
| `result.argvDump.contains(password) == false` | On macOS, `ps` or `proc_pidinfo` may not reveal arguments for processes owned by the same user (security feature). The test passes because argv was hidden by the OS, not because it was absent. | The fixture child must self-report its own argv/environ via stdout **before** the parent introspects externally. Compare both. |
| `result.environmentDump` absent | Same as above — `environ` might not be accessible via process introspection. | Same fix: child self-reports. |
| `password literal absent from process description` | `proc_pidinfo` on macOS may return empty/masked cmdline for same-user processes. Test passes vacuously. | Use the child's self-report, not parent-side introspection, as the primary evidence. |
| fd leak test with few open fds | A `posix_spawn` test that only opens the pipe fds and closes them may pass because no other fds existed to leak. | Test must open ~50 extra fds before spawn (e.g., open `/dev/null` repeatedly), then have the fixture child report its open fd count via `proc_pidinfo` on itself. |
| Timeout test with instant child | A child that exits in 1ms will never trigger the timeout path. The timeout code path is untested. | Use a fixture child that sleeps > timeout, verify it is killed and reaped. |
| PTY echo absence test with disabled echo | If `ECHO` was disabled before writing, the test passes but doesn't prove that echo was correctly disabled (it could be disabled-by-default or already off). | Test must: enable ECHO on the PTY, write a non-sensitive probe, verify echo appears, disable ECHO, write another probe, verify echo absent. |

### 2.3 — Race/Deadlock/Leak Paths

#### Deadlock Paths

1. **Stderr-full-before-stdin-read (Critical):** Covered in Gap 2 above. The parent must drain stdout and stderr **before and concurrently with** the password write. The simplest correct implementation: spawn child, immediately start `DispatchIO` read channels on both stdout and stderr fds, then after a brief yield (one runloop cycle), write the password to stdin.

2. **PTY line-discipline buffering:** If the password write doesn't end with a newline, the PTY line discipline may buffer it (canonical mode). The child never receives the password. Fix: either put the PTY in raw mode (`cfmakeraw`) before writing, or terminate the password with `\n`. The plan's fixture child "reads one line" — so `\n` termination is assumed. But confirm 7zz also expects a newline.

3. **Double-prompt deadlock:** If 7zz prompts twice for password confirmation during `a` (create), and the parent only writes the password once, both processes hang: 7zz waiting for the second prompt's input, parent waiting for 7zz to exit.

#### Leak Paths

4. **Pipe fd leak on spawn failure:** If `posix_spawn` returns an error (e.g., `ENOENT` for missing executable), the pipe fds passed in `posix_spawn_file_actions` are NOT closed by the system. The parent must close its endpoints of all pipes/PTYs in every failure path.

5. **PTY master fd leak:** `posix_openpt` + `grantpt` + `unlockpt` creates a master fd. If `posix_spawn` fails, the master fd and the child-end fd (opened via `ptsname`) must both be closed. This is a non-trivial error path.

6. **Zombie grandchild processes:** After `kill(-pgid, SIGKILL)`, only direct child zombies are reaped by a single `waitpid`. Grandchildren may remain zombies until the parent exits. Fix: loop `waitpid(-1, &status, WNOHANG)` until `-1`/`ECHILD` after kill.

7. **Task handle leak:** If the concurrent drain uses Swift `Task` and the timeout fires, the drain tasks may be abandoned without cancellation. The pipe read-ends remain open, pinning kernel buffer memory. Fix: use `TaskGroup` with `group.cancelAll()` on timeout, and ensure drain tasks check `Task.isCancelled`.

#### Race Paths

8. **Kill-vs-exit race (Critical):** Between checking `waitpid(pid, &status, WNOHANG)` (returns 0, child still running) and `kill(pid, SIGKILL)`, the child exits and its PID is reused by a new process. We kill an innocent process. This is inherent to Unix signal delivery and cannot be fully eliminated, but mitigation: use process-group kill (`kill(-pgid, SIGKILL)`) which is safer because PIDs in a group are not reused as quickly; additionally, record that the child was killed, check waitpid after kill to confirm it was our child (matching PID + signal death), and accept the residual risk.

9. **Timeout-vs-drain race:** The timeout fires and we call `kill`. Meanwhile, the drain tasks are still reading from the pipes. After `SIGKILL`, the child's pipe write-ends are closed, the drain reads will get EOF. The order is safe, but the drain result status must be collected AFTER the waitpid, not raced.

### 2.4 — Honest Matrix Evidence Requirements

The plan Step 4 asks for a sandbox/hardened-non-sandboxed capability matrix. Reasonix cannot perform the live test. The following identifies exactly what the matrix must cover and which rows are feasible:

| Scenario | Sandboxed | Hardened (non-sandbox) | Feasibility | Notes |
|----------|-----------|----------------------|-------------|-------|
| User-selected bookmark access | Requires security-scoped bookmark + `NSOpenPanel` | Direct path access | Likely PASS in both | Bookmark resolution may fail in sandbox if entitlement missing |
| Bundled helper execution | `posix_spawn` within sandbox — likely BLOCKED unless helper is inside app bundle AND has matching Team ID | PASS if helper signed with same Team ID | Sandbox row: may be capabilityDisabled | App Sandbox restricts exec to bundled helpers only |
| External user-selected executable (7zz) | BLOCKED by App Sandbox — cannot exec arbitrary binaries | PASS (hardened runtime allows exec) | Sandbox row: capabilityDisabled | This is the expected behavior |
| External user-selected executable (rar) | Same as 7zz — BLOCKED | PASS | Sandbox row: capabilityDisabled | Same constraint |
| DMG attach/detach (read-only) | `hdiutil attach` may work within sandbox with user-selected bookmark | PASS | Sandbox may block system volume operations | Requires `com.apple.security.files.user-selected.read-only` + bookmark |
| Quick Look extension boundary | Extension runs in its own sandbox — isolated from main app | Extension in own sandbox | Both: PASS (extension model is inherently sandboxed) | Independent of main app sandbox choice |
| PTY allocation (`posix_openpt`) | May be blocked by sandbox | PASS | Sandbox: may fail | PTYs are considered a system resource |
| Process-group signaling (`kill(-pgid)`) | May be restricted | PASS | Sandbox: may fail | Sandbox may limit signal delivery |

---

## Codex-Owned Verification

These gates cannot be verified by Reasonix and must be performed by Codex with live Xcode, 7zz binary, and macOS environment:

1. **7zz 26.02 interactive-password behavior per operation (create/list/test/extract):**
   - Determine whether `-p` (no-value) works for each operation with 7zz 26.02 arm64 at `/opt/homebrew/bin/7zz`.
   - If any operation fails: record `capabilityDisabled` for that operation, do NOT fall back to `-pPASSWORD`.
   - For `7zz a -p`: determine whether it prompts once or twice (password + confirm).

2. **Sandbox vs. hardened-runtime live matrix:**
   - Build the app with App Sandbox entitlement active, run the helper fixture, record each matrix row.
   - Build with hardened runtime only (no sandbox), run again, record.
   - This requires actual Xcode build + run + entitlement configuration.

3. **`POSIX_SPAWN_CLOEXEC_DEFAULT` availability:**
   - Verify the macOS 26.0 SDK defines this flag (it should, since it's macOS 13+).
   - If unavailable: fall back to explicit `posix_spawn_file_actions_addclose` for every fd.

4. **DMG attach/detach under sandbox:**
   - Requires live `hdiutil attach` test with security-scoped bookmark.
   - May require `com.apple.security.temporary-exception.files.home-relative-path.read-write` or similar entitlement.

5. **Quick Look extension sandbox boundary:**
   - Verify the extension's sandbox is independent and cannot execute providers or access the main app's file permissions.

6. **Live pipe-fd-leak test:**
   - Build, run the fixture child that reports its own fd count.
   - Verify 0/1/2 + pipe endpoints only; no inherited fds.

7. **Live PTY echo test:**
   - If using PTY transport: verify with actual 7zz that echo does not appear in the master-side read stream.

8. **Live zeroization verification:**
   - Build with optimizations enabled (`-O`), run the `isZeroed` assertion, verify it holds.
   - If possible: use `leaks` or Instruments to confirm no password bytes in heap at test exit.

9. **Full Xcode scheme integration:**
   - Add HelperSpike and HelperSpikeTests targets to `project.yml`.
   - Generate Xcode project, build, run tests.
   - Verify Thread Sanitizer and Address Sanitizer pass on the helper tests.

10. **Hardened runtime + code signing verification:**
    - Confirm `ENABLE_HARDENED_RUNTIME = YES` propagates to HelperSpike targets.
    - Verify `posix_spawn` is not blocked by hardened runtime (it shouldn't be — it's a public API — but the spawned child's signing matters).

---

## Proposed Next Prompt Or Execution Slice

### Slice 1: File authoring (Reasonix can execute — explicit Codex authorization required)

If Codex authorizes an edit round, Reasonix can create the following files with the security mitigations described in §2 above baked in:

1. `ArchiveWorkbench/HelperSpike/PasswordTransport.swift`
   - `SecureBytes`: Use `ManagedBuffer` or `UnsafeMutableRawBufferPointer` backed by `mmap` with `MLOCK` + `MADV_DONTDUMP` to prevent swap/paging of password memory. `zero()` uses `memset_s` via a C shim; `deinit` calls `munlock` then `memset_s`. Add `consuming func extractAndWrite(to fd: Int32)` to prevent buffer escape.
   - Define `PasswordTransport` enum: `.pipe` / `.pty` with documented tradeoffs.

2. `ArchiveWorkbench/HelperSpike/HelperLauncher.swift`
   - Uses `posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT` (or explicit close-all if unavailable).
   - Creates process group via `POSIX_SPAWN_SETPGROUP` + `POSIX_SPAWN_PGROUP_SET(0)`.
   - Spawns child, then immediately starts concurrent `DispatchIO` drains on stdout/stderr before writing password.
   - Timeout: `withTaskCancellationHandler` + `Task.sleep`, on fire: `kill(-pgid, SIGKILL)`, then loop `waitpid(-1, ..., WNOHANG)`.
   - Accepts `executable: URL`, `arguments: [String]`, `password: consuming SecureBytes`, `limits: HelperLimits`.

3. `ArchiveWorkbench/HelperSpike/SpikeCommand.swift`
   - `ProviderSpikeResult` with added fields: `transportUsed`, `sandboxMode`, `processGroupReaped`, `interactivePasswordSupported`.
   - Command-line tool entry point for standalone spike testing.

4. `ArchiveWorkbench/HelperSpikeTests/PasswordTransportTests.swift`
   - Tests with false-positive mitigations as described in §2.2.
5. `ArchiveWorkbench/HelperSpikeTests/HelperIsolationTests.swift`
   - fd-leak test with ~50 pre-opened fds.
   - Deadlock-prevention test (stderr fills before stdin read).
   - Process-group reap test (child spawns grandchild).
   - Timeout-kill test (child sleeps beyond timeout).

6. `ArchiveWorkbench/Docs/security-spike-results.md` (template with empty result tables).

7. Modifications to `ArchiveWorkbench/project.yml` for the new targets.

### Slice 2: Review and iteration (Reasonix can execute)

After Slice 1, Reasonix can:
- Re-read the authored files and verify all gap mitigations from §2.1 are addressed.
- Check for Swift 6 strict concurrency warnings in the design.
- Run a second-pass review comparing the implementation against the false-positive traps in §2.2.

### Slice 3: Codex-owned live verification (Reasonix cannot execute)

Codex runs:
- `xcodegen generate`, build, test with Thread Sanitizer.
- 7zz interactive probe with PTY and pipe transports.
- Sandbox vs. hardened-runtime matrix.
- fd leak verification.
- Updates `security-spike-results.md` with actual command outputs and hashes.

---

## Escalation Triggers

Stop and escalate to Codex if any of the following are encountered during Reasonix execution:

1. **Ambiguous source instruction:** The plan or design spec contradicts itself (e.g., pipe vs. PTY choice, buffer behavior on overflow) and the correct security posture cannot be inferred from the source material alone.

2. **Missing system capability:** `POSIX_SPAWN_CLOEXEC_DEFAULT`, `POSIX_SPAWN_SETPGROUP`, or `posix_openpt` is not available in the documented SDK version, and the fallback has materially worse security properties.

3. **7zz interactive mode incompatible:** If documents or probing suggest 7zz 26.02 does NOT support interactive `-p` mode for critical operations, the entire encrypted-archive path becomes `capabilityDisabled` — this is a product-level decision Codex must make.

4. **Sandbox blocks all provider execution:** If the sandboxed matrix shows `capabilityDisabled` across all external-provider rows, the product decision between sandbox (security) vs. providers (functionality) must be made by Codex/User — Reasonix cannot choose.

5. **Zeroization fails under optimization:** If `isZeroed` is true but a heap scan (via Instruments/leaks) shows residual password bytes, the `SecureBytes` implementation is insufficient and needs a redesign that goes beyond the current plan.

6. **Scope creep:** Any request that goes beyond the authorized sources or requires web access, browser interaction, live 7zz execution, or visual inspection.

---

*Reasonix CLI — task complete. Output written to `runs/reasonix_archive_helper_security.md`. Codex owns final review, live verification, and acceptance.*
