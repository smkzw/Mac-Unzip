# Helper isolation and password transport spike

Evidence date: 2026-07-12. Host: Apple silicon, macOS, Xcode 26.6 / macOS 26.5 SDK. This is a local capability result, not a claim about every Mac or future tool release.

## Result

The production-shaped `posix_spawn` boundary passed the private-input contract in the non-hardened XCTest probe. It accepts an executable URL plus an argument array, never a shell command; sends password bytes through nonblocking stdin governed by the same monotonic timeout/cancellation loop; allowlists the explicit environment; gives the child a separate process group; drains stdout and stderr concurrently with independent retention limits and a bounded drain deadline; and clears the owned `SecureBytes` storage on every tested completion path. Empty input, more than 16 KiB, unsupported prompt counts, embedded NUL in argv, and NUL/LF/CR in the line-protocol password are rejected before spawn.

The test fixture independently reported child arguments, runtime environment and open file descriptors using `proc_pidinfo(PROC_PIDLISTFDS)`. It observed only descriptors `0, 1, 2`, including when the parent held a descriptor above 300. A dedicated harness also closed parent descriptors 0/1/2 before launch; pipe endpoints were normalized to descriptors at least 3 and the child still received only its intended standard streams. macOS injected `__CF_USER_TEXT_ENCODING` in addition to the explicit `LANG`, `LC_ALL` and `PATH`; no caller environment or secret was present. `KERN_PROCARGS2` inspection was available while the child was alive, and only absence flags plus a SHA-256 summary were retained. The zeroization claim is deliberately limited to the buffer owned by `SecureBytes`; it does not claim erasure of copies inside the OS or framework internals.

## Fixed 7zz probe

- Executable: the pinned local `/opt/homebrew/bin/7zz` (the evidence record does not persist this private absolute path).
- Version: official 7-Zip 26.02, arm64, 2026-06-25.
- Executable SHA-256: `2f412eded2d37f2cc52f26138e6964bd205ea0bf2ee6a70b8b990a18107e784d`.
- Input: randomly isolated mode-0700 directory, Chinese/Latin filename, known payload hash.
- Observed argument contract (paths redacted): create `a -t7z -p -mhe=on <archive> <source>`; list `l -slt <archive>`; test `t <archive>`; extract `x -y -o<directory> <archive>`.
- Transport: pipe stdin; every operation uses exactly one private password line. The create switch is bare `-p`, never `-pPASSWORD`. No PTY fallback was needed.
- Result: local non-hardened probe pass. `l -slt` reported `Encrypted = +`; wrong-password and `/dev/null` no-input controls failed for list, test and extract; correct list/test/extract passed; extracted SHA-256 `93177235ba99d053714cda52199b850d109fd9917946ff1adb06cedb48ec1834` matched input.
- Every accepted result additionally proved no stdout/stderr truncation, no read error, no drain timeout, direct-child reap, process-group absence, and available/expected process inspection.
- Redacted `ProviderSpikeResult`: provider `sevenZip`, version `26.02-arm64`, status `pass`, command-argument-shape SHA-256 `5c77b1290776d594855fe6875e5c9d9c01295c1aaa775db95666a789c8eed566`, output SHA-256 as above, failure code `nil`.

No password value appeared in argv, environment or a temporary password file. The bare `-p` switch explicitly requests interactive password input. The generated archive, source and extraction were removed by test cleanup.

## Capability matrix

Each cell is an observed result or an explicit disabled boundary. “Capability disabled” means the prerequisite implementation does not exist in this foundation task; it is not a pass inferred from a similar configuration.

| Capability | Hardened, non-sandboxed | Sandboxed |
|---|---|---|
| User-selected bookmark access | `capabilityDisabled` — no document-picker/bookmark host exists in Task 7 | `capabilityDisabled` — no sandbox entitlement target and no user-selected bookmark fixture |
| Bundled helper execution | `capabilityDisabled` — the fixture is a sibling test tool launched by XCTest, not an app-bundled hardened helper | `capabilityDisabled` — no sandboxed host/helper entitlement target |
| External user-selected executable | `capabilityDisabled` — 7zz was not selected through a hardened user-picker host | `capabilityDisabled` — no sandboxed host or user-selection security scope exists |
| Read-only `hdiutil` attach/detach | `capabilityDisabled` — no repository evidence artifact or hardened host probe was produced | `capabilityDisabled` — no sandboxed host entitlement/probe target |
| Quick Look extension boundary | `capabilityDisabled` — no Quick Look extension target exists | `capabilityDisabled` — no signed extension/host entitlement target exists |

## Non-hardened diagnostics

Outside that matrix, the non-hardened local XCTest probe passed the helper fixture and fixed 7zz workflow. These observations are diagnostic only and are not promoted into hardened or sandboxed matrix passes. No durable DMG evidence artifact was retained, so no DMG pass is claimed.

## Failure and race coverage

Tests cover staged pipe/C-string/spawn failure, pre-cancellation, child nonzero exit, stdout read failure, output truncation while continuing to drain, nonblocking 1 MiB backpressure timeout/cancellation, residual process group cleanup, group-gone confirmation, a retained writer, an escaped-process-group writer, low/high descriptor isolation, drain-duration overflow, input contract validation, and the encrypted 7zz positive/negative controls. Read errors, drain timeout and residual processes become protocol failures; truncated output cannot be silently accepted by a provider.

The launcher is intentionally for already validated/trusted executables. Path validation followed by `posix_spawn` retains an executable replacement (TOCTOU) window; an adversarial descendant can leave the provider process group. The drain deadline prevents such an escaped writer from hanging the host, but the launcher does not claim to discover or kill arbitrary escaped descendants.

## Reproduction

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project ArchiveWorkbench.xcodeproj \
  -scheme ArchiveWorkbench \
  -destination 'platform=macOS,arch=arm64' \
  test -only-testing:HelperSpikeTests
```

Observed after a clean build: 27 focused tests across 3 suites, zero skips, all passed; the same focused set also completed 20 iterations without failure. The fixed live probe is intentionally strict: a changed/missing executable hash fails rather than silently substituting legacy p7zip.
