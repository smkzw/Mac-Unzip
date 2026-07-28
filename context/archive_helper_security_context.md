# Task Context: archive_helper_security

Created: 2026-07-12 00:02:16
Objective: Implement and prove isolated helper execution and private password transport for the native macOS archive workbench, including bounded IO, timeout/cancel, fd hygiene, fixed 7zz interactive-password probe, sandbox/bookmark/helper/DMG capability matrix, tests, review, and evidence without external publishing.
Task type: `code_scoped_patch_plan`
Risk: `high`
Selected agent route: `reasonix-cli` / `deepseek-v4-pro` / `high`

## Trigger Reason

This task was initialized through the Codex x Hermes complex-task entrypoint because it is expected to involve more than three execution steps, research/writing/report/code/report-visual work, or source-grounded verification.

## Source Of Truth

- `docs/superpowers/plans/2026-07-11-archive-workbench-foundation.md`, Task 7 only (lines 766-858).
- `design/2026-07-11_full_design_spec.md`, especially helper isolation, password, provider, sandbox and extension boundaries.
- `ArchiveWorkbench/project.yml`, `ArchiveWorkbench/Config/Base.xcconfig`, and existing Xcode project conventions.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveCapability.swift` and related provider identifiers.
- Current local fixed probe binary: `/opt/homebrew/bin/7zz`, 7-Zip 26.02 arm64, SHA-256 `2f412eded2d37f2cc52f26138e6964bd205ea0bf2ee6a70b8b990a18107e784d`, Homebrew official 7-Zip formula install.
- Official upstream reference: `https://www.7-zip.org/` and its current download/license pages; Codex owns current-web verification.

## Scope

- In scope: a Swift 6 helper-launcher framework/spike; noncopyable password bytes; `posix_spawn` with explicit argv/environment and close-on-exec fd actions; pipe or PTY private password input; bounded concurrent stdout/stderr drain; timeout/cancellation/process-group termination; helper fixture and tests; fixed 7zz encrypted create/list/test/extract probe; provider result record; sandbox/bookmark/helper/external-tool/DMG/Quick Look capability matrix; evidence report; XcodeGen targets.
- Out of scope: production provider integration, UI changes, publishing, GitHub/website upload, notarization, bundling RARLAB, Windows physical testing, claiming Office/video preview complete, or changing Task 1-6 behavior.

## Success Criteria

- Password literal is absent from argv, environment, process description, stdout, stderr, structured diagnostics, and report; it is sent only through a child-private stdin/PTY and the caller-visible buffer is zeroed on every success/failure/timeout/cancel path.
- No unintended descriptors are inherited; only the intended stdin/stdout/stderr endpoints reach the fixture child.
- stdout/stderr buffers stay bounded while pipes are fully drained; timeout and cancellation terminate the whole child process group and reap it without stale processes.
- The launcher accepts an already validated executable URL and an argv array, never a shell command string.
- Fixed 7zz 26.02 arm64 either completes encrypted create/list/test/extract via private interactive input with output hash match and no leakage, or is recorded `capabilityDisabled`; never use `-pPASSWORD`.
- Sandboxed and hardened-non-sandboxed matrix rows are explicit `pass`, `fail`, or `capabilityDisabled`, backed by command/output evidence.
- Focused tests, full app scheme, clean build, signature/arm64/resources/XcodeGen/diff/cache/process gates pass; independent security review has no Critical/Important findings.

## Risk Boundaries

- Do not write to production paths until Codex review gate passes and writable paths are explicit.
- The delegated agent is not final authority; Codex owns verification and acceptance.
- Passwords and private paths must never be written to task artifacts, shell history, argv, environment, logs, temporary files, clipboard, crash diagnostics, or model prompts.
- Tests use a fixed synthetic secret only inside a controlled byte buffer and assert absence from every observable channel.
- No shell construction, `Process` command strings, global environment mutation, destructive process commands, remote upload, or external messaging.
- Do not treat a model plan, compile success, or skipped environment probe as capability proof.

## Timeout Policy

- Do not mark the delegated agent failed for slow response alone.
- For complex or artifact-heavy work, wait and poll generously; use conference mode when multiple independent model perspectives are needed.
- Failure requires terminal error, provider exhaustion/rate limit after controlled retry, empty/truncated retry output, or no progress after hard wait plus one retry.

## Loop Log

- 2026-07-12 00:02:16: Task initialized by `tools/hermes_workflow_guard.py init-task`.
- 2026-07-12: Codex confirmed current `/opt/homebrew/bin/7z` was obsolete p7zip 17.05 and installed Homebrew `sevenzip` 26.02, yielding arm64 `/opt/homebrew/bin/7zz` with the recorded SHA-256.
