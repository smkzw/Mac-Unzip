# Archive Workbench — Independent Security Review (Reasonix deepseek-pro)

**Reviewer:** Reasonix CLI `deepseek-pro` (high-risk backend reviewer per conference route)
**Date:** 2026-07-12
**Evidence commit:** `ab580694f2dd8fbc61f0854b5551070d038357c5`
**Scope:** Foundation boundary — secret exposure, stdin backpressure, cancellation/timeout, FD inheritance, process-group cleanup, executable trust/TOCTOU, escaped descendants, test gaps, acceptance wording overclaiming.
**Boundary:** This review is advisory. Codex owns final acceptance.

---

## Boundary Compliance

The foundation acceptance document (`ArchiveWorkbench/Docs/foundation-acceptance.md`) is **honest about its boundaries**. Every claim links to specific evidence; every known gap is called out explicitly (lines 182–196). The capability matrix in `security-spike-results.md` (lines 29–35) is uniformly `capabilityDisabled` for all hardened/sandboxed rows — no false passes are claimed. No overclaiming was detected.

However, two **Critical** residual risks and four **Important** findings remain open. They do not invalidate the foundation pass but must be provider-stage gates before any production claim.

---

## Findings

### Critical — Must Gate Provider Stage

#### C-1: Executable Replacement TOCTOU (HelperLauncher.swift:145–149, 237)

**What:** `access(executable.path, X_OK)` validates executability; `posix_spawn` follows as a separate, non-atomic operation. An attacker who can replace the binary between these calls gets arbitrary code execution under the caller's uid.

```swift
// HelperLauncher.swift:145-149 — validation
guard executable.isFileURL,
      executable.path.hasPrefix("/"),
      access(executable.path, X_OK) == 0 else {
    throw HelperError.invalidExecutable
}

// HelperLauncher.swift:237 — spawn (non-atomic with above)
posix_spawn(&processID, executable.path, &actions, &attributes, ...)
```

**Evidence:** The code never hashes the executable before spawn. `processSnapshotContainsExpectedExecutable` (line 288–294, `inspectProcess`) uses `KERN_PROCARGS2` — a post-spawn check that confirms what *did* run, not what *will* run. The security-spike-results.md (line 45) explicitly acknowledges this window.

**Risk:** A local attacker with write access to the executable path (or a parent directory) can substitute a malicious binary. The post-spawn `KERN_PROCARGS2` check will report `processSnapshotContainsExpectedExecutable: true` if the attacker's binary reports the expected name (trivial to forge), or `false` if it doesn't — but by then the attacker's code has already executed.

**Required provider gate:** Before production, the hardened helper host must either:
- (a) compute and verify a cryptographic hash of the executable bytes immediately before spawn (same locked region), or
- (b) use `posix_spawn` with a file descriptor opened `O_EXEC` + `O_NOFOLLOW` to the validated inode, eliminating the path-based TOCTOU, or
- (c) enforce mandatory access control (sandbox profile) restricting which binaries can be spawned.

Acceptance document line 168 already records this as "explicit residual risk." The foundation pass is valid only because the scope is explicitly non-hardened.

---

#### C-2: Escaped Descendant Survivability (HelperLauncher.swift:217–219, 357–365, 628–637)

**What:** The launcher creates a new process group (`POSIX_SPAWN_SETPGROUP`, `posix_spawnattr_setpgroup(&attributes, 0)`) and kills it with `kill(-processID, SIGTERM)` → SIGKILL on termination. However, a child process can fork a grandchild that calls `setpgid(0, 0)` or `setsid()` to escape the process group. The launcher detects this condition (lines 357–361: `processGroupIsGone` false after direct-child exit → `protocolFailure`) but does NOT hunt or kill the escaped descendant.

```swift
// HelperLauncher.swift:357-361 — detection without remediation
let groupWasGone = processGroupIsGone(processID)
if !groupWasGone, terminal != .timedOut, terminal != .cancelled {
    terminateProcessGroup(processID, grace: limits.terminationGrace)
    terminal = .protocolFailure
}
```

**Evidence:** `terminateProcessGroup` (line 628) signals the child's PGID only. An escaped descendant with a different PGID survives both SIGTERM and SIGKILL. The `LowFDHarness` and `HelperFixture` don't exercise descendant escape. The security-spike-results.md (line 46) acknowledges: "the launcher does not claim to discover or kill arbitrary escaped descendants."

**Risk:** A compromised or buggy helper could leave orphaned processes consuming resources, holding file locks, or exfiltrating data on a separate timeline.

**Required provider gate:** Production hardened helper must either:
- (a) Run under a sandbox that prevents `setpgid` / `setsid` / `fork` after initial setup, or
- (b) Use `posix_spawnattr_setprocesstype` or equivalent to prevent descendant creation, or
- (c) Implement descendant enumeration (e.g., `proc_listchildpids`) and cleanup after the direct child exits.

---

### Important — Remediate Before Provider Integration

#### I-1: Cooperative Cancellation Cannot Preempt CPU-Bound Work (OperationScheduler.swift:147–165)

**What:** The scheduler cancels a running operation via `Task.cancel()` + `Task.checkCancellation()` (line 155). If the `execution` closure is CPU-bound without suspension points, it will run to completion despite cancellation. The scheduler has no watchdog timer or preemption mechanism.

```swift
// OperationScheduler.swift:153-163 — cancellation is fully cooperative
let task = Task {
    do {
        try Task.checkCancellation()  // only checked once before execution
        try await job.execution()     // no internal suspension = no further checks
        await self.finish(id, proposedState: .succeeded)
    } catch is CancellationError {
        ...
    }
}
```

**Evidence:** The scheduler documentation honestly states "Execution receives structured task cancellation and must leave suspension points cooperatively" (lines 52–53). The test suite's `CancellationAwareGate` always provides suspension points; no test exercises a non-yielding execution closure.

**Risk:** A buggy or hostile provider execution could indefinitely block the scheduler, preventing all other operations (including UI responsiveness). With `maxExternalJobs: 1`, this becomes a complete denial of service.

**Required gate:** Provider execution adapters must be designed with (a) cooperative cancellation at regular intervals, (b) bounded work units, and ideally (c) a scheduler-level execution timeout distinct from the helper-level timeout.

---

#### I-2: Password Zeroization Scope Is Best-Effort (SecureBytes.swift:31, security-spike-results.md:9)

**What:** `SecureBytes.zero()` uses `memset_s` (C11 Annex K) to zero the owned allocation. This prevents compiler elision of the clear, but does not address:
- Copies in kernel pipe buffers (stdin transport path)
- Copies in `DispatchQueue` / libdispatch internal buffers
- Copies in Swift runtime or ARC temporaries
- Copies swapped to disk under memory pressure

**Evidence:** The security-spike-results.md (line 9) honestly limits the claim: "it does not claim erasure of copies inside the OS or framework internals." The `SecureBytes` type is `~Copyable` and uses `borrowing` accessors — these are good Swift ownership practices but do not constitute a formal zeroization guarantee.

**Risk:** In a production context, password material may persist in kernel or runtime memory beyond the `zero()` call. This is inherent to any userspace zeroization scheme and is not a bug in this code.

**Required gate:** Accept as a known limitation. If regulatory requirements demand formal secret-erasure guarantees, a kernel-level or hardware-enforced mechanism (Secure Enclave, kernel-mode helper, `mlock` + controlled I/O path) would be needed.

---

#### I-3: OperationScheduler Memory Accumulation (OperationScheduler.swift:26–28)

**What:** The `operations` and `events` dictionaries are append-only. Terminal operations (`.canceled`, `.succeeded`, `.failed`) are never removed.

```swift
// OperationScheduler.swift:26-28 — never pruned
private var operations: [ArchiveOperationID: ArchiveOperation] = [:]
private var events: [ArchiveOperationID: [ArchiveOperationState]] = [:]
```

**Evidence:** `finish()` (lines 167–179) removes the job from `jobs` and `runningTasks` but does not touch `operations` or `events`. In a long-running session with many operations, these dictionaries grow without bound.

**Risk:** Not a security vulnerability, but a resource leak. In a session processing thousands of archives, memory pressure could degrade performance or trigger jetsam.

**Provider gate:** Add bounded retention (LRU eviction or cap on stored operation count) before production integration.

---

#### I-4: Cancellation Blind Spots During I/O (HelperLauncher.swift:302–354, 665–695)

**What:** The main dispatch loop checks `Task.isCancelled` at the top of each iteration (line 313), but sub-operations do not check internally:
- `waitUntilWritable` (line 519–522): `poll()` with 10ms timeout → max 10ms blind spot.
- `writeNonblocking` (line 500–517): EINTR retry loop without cancellation check → bounded by child pipe capacity.
- `inspectProcess` (line 665–695): 20-iteration loop with 5ms sleeps → max ~100ms blind spot.

**Risk:** Low. All blind spots are bounded and short-lived. However, a hostile child that opens stdin but never reads could cause repeated `waitUntilWritable` calls (10ms each) — the accumulated delay before cancellation is noticed is proportional to the timeout window, not unbounded.

**Required gate:** Accept for foundation. In production, add `Task.isCancelled` checks inside `inspectProcess` loop and after `waitUntilWritable` returns.

---

### Minor

#### M-1: High-Frequency Poll on Blocked Stdin (HelperLauncher.swift:348–349, 519–522)

`waitUntilWritable` uses `poll()` with 10ms timeout in a tight loop. If the child process never reads stdin, this wastes CPU. Bounded by the overall timeout/cancellation, so the impact is limited to the timeout window. Not a security concern.

#### M-2: Test Gap — No TOCTOU Simulation

Neither `PasswordTransportTests` nor `SevenZipProbeTests` simulates binary replacement between `access()` and `posix_spawn`. The test suite trusts the fixture's static path. Documented under C-1.

#### M-3: Test Gap — No Descendant Escape Simulation

No test spawns a child that forks an escape-artist grandchild. The `LowFDHarness` only tests FD isolation. Documented under C-2.

#### M-4: Hardcoded 7zz Path in Tests Is Defensive (SevenZipProbeTests.swift:11–13)

The test hardcodes the 7zz path and verifies its hash. This is intentionally strict (security-spike-results.md line 57 confirms: "a changed/missing executable hash fails rather than silently substituting"). This is a security feature, not a bug.

---

## What Was Verified (No Findings)

| Area | Verdict | Key Evidence |
|---|---|---|
| Stdin backpressure | **Pass** | `O_NONBLOCK` + 10ms poll + bounded retry; nonblocking write handles EAGAIN/EWOULDBLOCK. `HelperLauncher.swift:254–256, 348–349, 500–517` |
| FD inheritance | **Pass** | `POSIX_SPAWN_CLOEXEC_DEFAULT` + explicit `addclose` for all parent pipe ends (lines 206–215); `makePipe` ensures FDs ≥ 3 (lines 418–447). Tested via `LowFDHarness` and fixture FD enumeration. |
| Process-group cleanup (normal path) | **Pass** | `POSIX_SPAWN_SETPGROUP` + `terminateProcessGroup` with SIGTERM→SIGKILL escalation (lines 628–637). Normal exit `processGroupIsGone` check labels survivals as `protocolFailure` (lines 357–361). |
| Cancellation (normal path) | **Pass** | Pre-spawn check (line 144), cooperative check in main loop (line 313), graceful termination with reap (lines 315–316), drain-cancellation fallback (lines 367–374). |
| Timeout | **Pass** | Monotonic `ContinuousClock` deadline (lines 250–251, 319–323); same termination path as cancellation. |
| Secret-in-argv prevention | **Pass** | `CStringVector` construction validates no embedded NUL (line 468). Password travels exclusively through stdin pipe, never argv or environment. Tested: `PasswordTransportTests.swift:139–178`. |
| Secret-in-stdout/stderr prevention | **Pass** | Tests search combined stdout+stderr for secret bytes and assert absence. `PasswordTransportTests.swift:158–159`, `SevenZipProbeTests.swift:66–67`. |
| Secret-in-process-snapshot prevention | **Pass** | `KERN_PROCARGS2` inspection confirms `privateInputDetectedInProcessSnapshot: false`. `HelperLauncher.swift:660–703`, tested in both test suites. |
| Bare `-p` contract | **Pass** | `SevenZipProbeTests.swift:28` uses `-p` without value; grep for `-pVALUE` in spike results reports no matches (security-spike-results.md line 23). |
| Scheduler mutation exclusion | **Pass** | `mutatingArchiveIDs` set prevents concurrent mutations on same archive; TSan-clean at 14 tests. `OperationScheduler.swift:143–144, 188–189`. |
| Scheduler external concurrency cap | **Pass** | `runningExternalJobs < maxExternalJobs` (max 2). `OperationScheduler.swift:141–142`. |
| Scheduler permit recovery | **Pass** | `releasePermit` called in `finish()` for all terminal paths (line 172). Test: `OperationSchedulerTests.swift:294–329`. |
| Acceptance document honesty | **Pass** | All 10 pending work items listed explicitly (lines 182–196). Capability matrix is uniformly `capabilityDisabled` (security-spike-results.md lines 29–35). No overclaiming detected. |

---

## Residual Risks (Not Findings — Acknowledged Limitations)

1. **Kernel/runtime secret persistence:** `memset_s` clears the userspace buffer; kernel copies in pipe buffers, I/O buffers, and swap are not cleared. Acknowledged in security-spike-results.md:9.

2. **Testing-hook surface:** `HelperLauncherTestingHooks` (lines 81–115) exposes `forceWaitFailure`, `forceStdoutReadFailure`, `holdStdoutWriterOpen`, and `privateInputLimitOverride`. These are only accessible via test-only `init` overloads (lines 126–134). The public `init()` (line 121) leaves them nil. No production exposure.

3. **DispatchQueue label predictability:** The drain queue label `"com.smkzw.ArchiveWorkbench.helper-drain"` (line 274) is not a secret. No risk.

---

## Recommendation

**Pass with gates.** The foundation boundary is honestly described, has direct evidence for all claimed surfaces, and explicitly keeps every known risk open.

Before any provider-integration or production claim, the following must be resolved:

| Gate | Finding | Owner |
|---|---|---|
| G-1 | Executable TOCTOU: hash-before-spawn or fd-based spawn | Provider-stage implementer |
| G-2 | Escaped descendant: sandbox, process-type restriction, or enumeration+cleanup | Provider-stage implementer |
| G-3 | Cooperative cancellation: provider adapters must yield; scheduler needs watchdog timeout | Provider-stage implementer |
| G-4 | OperationScheduler memory: add LRU eviction or cap | Provider-stage implementer |
| G-5 | I/O cancellation responsiveness: add `Task.isCancelled` checks in `inspectProcess` and `waitUntilWritable` paths | Provider-stage implementer |

The foundation pass should not be interpreted as closing these residual risks; the acceptance document already records them correctly.

---

## Evidence References

| File | Lines | What |
|---|---|---|
| `HelperLauncher.swift` | 145–149, 237 | TOCTOU between access() and posix_spawn (C-1) |
| `HelperLauncher.swift` | 217–219, 357–365, 628–637 | Process-group create/kill; escaped-descendant detection without cleanup (C-2) |
| `HelperLauncher.swift` | 206–215, 418–447 | FD isolation via CLOEXEC + explicit close (verified) |
| `HelperLauncher.swift` | 254–256, 348–349, 500–517 | Nonblocking stdin backpressure (verified) |
| `HelperLauncher.swift` | 288–294, 660–703 | KERN_PROCARGS2 inspection for secret in snapshot (verified) |
| `SecureBytes.swift` | 31, 42–46 | memset_s zeroization (I-2 limitation) |
| `OperationScheduler.swift` | 147–165 | Cooperative-only cancellation (I-1) |
| `OperationScheduler.swift` | 26–28 | Unbounded operations/events dictionaries (I-3) |
| `PasswordTransportTests.swift` | 139–178 | Comprehensive secret-channel test (verified multiple properties) |
| `SevenZipProbeTests.swift` | 9–84 | Encrypted 7zz round-trip with negative controls (verified) |
| `security-spike-results.md` | 9, 45–46 | Honest zeroization & TOCTOU/descendant acknowledgments |
| `foundation-acceptance.md` | 11–12, 168, 182–196 | Boundary declarations and pending work (verified honesty) |
