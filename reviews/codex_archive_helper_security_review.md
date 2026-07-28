# Codex Review: archive_helper_security

Date: 2026-07-12
Delegated-agent output: `runs/reasonix_archive_helper_security.md`

## Verdict

Revise at the delegation boundary; advisory findings accepted only after independent Codex verification. The output is not a compliant delegated-agent pass because Reasonix read three unapproved files.

## Boundary Check

- Working-directory boundary: passed; all observed reads and the write remained under the foundation worktree.
- Write boundary: passed; Reasonix wrote only `runs/reasonix_archive_helper_security.md`.
- Read allowlist: failed. The prompt permitted six files, but stdout records an unapproved glob of `ArchiveSecurity/**/*` followed by reads of `ArchiveSecurity.swift`, `ResourceBudget.swift`, and `ArchivePathPolicy.swift`.
- Consequence: the output is advisory input only. It cannot serve as Task 7 acceptance evidence or authorize production edits.

## Codex Verification

- Codex and the implementation task independently inspected the product sources and implemented the applicable recommendations: drains before password input, `memset_s` owned-buffer zeroization, `POSIX_SPAWN_CLOEXEC_DEFAULT`, an explicit process group, bounded TERM-to-KILL cleanup, fixed argv/environment, process inspection, many-parent-fd coverage, and exact prompt counts.
- Live 7-Zip 26.02 arm64 create/list/test/extract was executed through private pipe input with no `-p` switch; Unicode listing and extracted SHA-256 matched.
- Final focused HelperSpike tests passed 27/27 with zero skips, including nonblocking backpressure timeout/cancellation, real encrypted 7zz positive/negative controls, low/high-fd isolation, process-group races, escaped descendants, input validation, output caps, setup/read/wait failures, and process-snapshot checks.
- The full app scheme passed Helper 27 + app unit 11 + UI 9; ArchiveKit passed 34/34. Codex independently reran focused 27/27, and the independent security reviewer reran focused 27/27 plus 20 iterations (540 tests / 60 suites) without failures or residual processes.
- Browser/PPT/PDF/image checks are not applicable to this non-UI helper-boundary task.

## Delegated-Agent Output Review

- Provider identity was verified as Reasonix CLI `deepseek-v4-pro`; this was not a Hermes or OpenCode route, and no silent substitution was accepted.
- Useful and traceable findings: concurrent drains must start before password writes; PTY echo is a risk; raw `posix_spawn` with allowlisted environment is preferred; process-group cleanup and non-vacuous process inspection need direct tests.
- The plan's statement that a value-less `-p` should be used was not accepted as fact. The pinned binary was tested directly and succeeded when the `-p` switch was omitted entirely; the report explicitly avoids claiming the untested value-less form.
- Several pre-implementation concerns were necessarily hypothetical. They were treated as test hypotheses, not as verified defects.
- The model route was adequate for adversarial planning, but the read-boundary violation requires the final judgment to remain entirely Codex-owned.

## Residual Risk

- Task 7 proves a hardened non-sandboxed local boundary, not a Team-ID-signed distributable helper.
- Sandboxed bookmark, sandboxed external-tool execution, and Quick Look extension rows remain explicitly `capabilityDisabled` until their required targets and entitlements exist.
- Zeroization is limited to the `SecureBytes` allocation; it does not claim removal of copies created before initialization or inside OS/tool internals.
- Executable-path TOCTOU and descendants escaping the provider process group remain explicitly documented trusted-executable boundaries; the independent final reviewer found no remaining Critical, Important, or Minor finding.
