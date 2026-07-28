# Conference Context: zip_provider_vertical_slice

Created: 2026-07-12 03:52:05
Objective: Validate the real ZIP provider vertical slice: pinned minizip bridge, safe UTF-8 list/read/materialization, Windows-native ZIP creation, Chinese native app binding, security boundaries, and honest acceptance gates
Task type: `complex_delivery_conference`
Risk: `high`
Conference mode: `parallel`

## Codex Main Venue

- Chair: Codex.
- Duties: understand the real task, decompose, define sources of truth, route work, protect boundaries, verify final artifacts, own visual/browser/PPT/PDF checks, own production writes, and deliver to the user.

## Conference Panel Assignment

- Chinese terminology and user-workflow review: Hermes `aishuo / MiniMax-M3` in a three-round same-session loop.
- Architecture review: first attempt Hermes `aishuo / glm-5.2`; if terminally unavailable, use the user-authorized `buddy / glm-5.2` fallback without substituting another model.
- High-risk C bridge, filesystem and transaction review: Reasonix CLI `deepseek-pro`; DeepSeek V4 is forbidden through Hermes, Buddy, OpenCode Go, or a direct provider.
- Rendered screenshot review: Codex is final authority. If a current provider-state screenshot becomes available, attempt `aishuo / Gemini-3.5-Flash`, then `buddy / kimi-k2.7-code` only as advisory fallback.
- Every conference role is dispatched through a three-round same-session loop: independent pass, skeptical challenge, and corrected final pass. A new session is a routing failure unless a primary role failed before a resumable session existed and the documented fallback was activated.

## Source Of Truth

- Git commit `61accd0` on branch `feature/archive-zip-provider` plus its two preceding provider commits.
- `docs/superpowers/plans/2026-07-12-zip-provider-vertical-slice.md`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/include/AWBMinizipBridge.h`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/WindowsZIPProfile.swift`
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`
- The corresponding focused tests under `ArchiveWorkbench/Packages/ArchiveKit/Tests/` and App/UI tests under `ArchiveWorkbench/AppUnitTests/` and `ArchiveWorkbench/AppTests/`.
- Current generated ZIP interoperability evidence from local `7zz 26.02` and `/usr/bin/unzip`; physical Windows remains an open gate.

## Scope

- In scope: dependency provenance, C ownership, UTF-8 ZIP listing/read, resource ceilings, descriptor-rooted materialization, Windows-native unencrypted ZIP creation, metadata suppression, source fingerprint recheck, exclusive publication, Chinese App open/list states, and honest disabled-state copy.
- Out of scope: ZIP password/encryption, mutation, split/integrity/repair, legacy encoding recovery, complete archive-entry previews, other archive formats, RAR creation provider, physical Windows, notarization, and external publication.

## Success Criteria

- No reviewer may mark the full product complete.
- Every accepted finding cites an allowed file and a concrete symbol or test.
- Critical issues include memory ownership, error-code ambiguity, TOCTOU, symlink/special-file escape, output overwrite/data loss, source mutation, corrupted ZIP handling, and false Windows compatibility claims.
- Chinese review checks natural terminology, low-frequency integrity placement, loading/error/disabled-state clarity, dynamic title/count behavior, and Finder-like list expectations.
- Codex independently reruns package, unit, sanitizer, interoperability, build/signature, and rendered-state checks before accepting the milestone.

## Parallel Work Rule

For logic-heavy, rigor-sensitive, or artifact-heavy tasks, each participant independently runs the whole bounded workflow and writes a separate output. Leads compare after all available participant outputs are in or explicitly marked pending.

## Timeout Policy

- Participant soft wait: 20 minutes.
- Large-task participant wait: 45 minutes.
- Chair hard wait: 90 minutes.
- Failure rule: Do not fail a model for slow response alone; fail only on terminal error, provider exhaustion/rate limit after controlled retry, empty/truncated retry output, or no progress after hard wait plus one retry.

## Risk Boundaries

- Hermes is advisory; Codex remains final authority.
- Codex owns visual/browser/PPT/PDF/rendered checks, live authority checks, final clinical/regulatory conclusions, and production writes.
- Do not mark a slow model failed solely due to latency.

## Loop Log

- 2026-07-12 03:52:05: Conference initialized by `hermes_workflow_guard.py init-conference`.
- 2026-07-12 03:54: user-specific routing replaced the generic generated routes; Hermes DeepSeek and generic Mimo routes are not authorized for this milestone.
- 2026-07-12 03:55: aishuo GLM completed; Codex rejected three source-inconsistent findings and retained fingerprint/stress recommendations.
- 2026-07-12 03:59: Reasonix DeepSeek Pro completed; Codex adjudicated findings against pinned minizip-ng and current tests.
- 2026-07-12 04:08: original MiniMax output excluded for boundary violation; bounded embedded-evidence rerun completed and was incorporated.
- 2026-07-12 04:11: package/unit/security/interoperability checks passed; rendered UI retry remained blocked at app activation with `Running Background`.
