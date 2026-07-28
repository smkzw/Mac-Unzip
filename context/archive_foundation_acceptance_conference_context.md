# Conference Context: archive_foundation_acceptance

Created: 2026-07-12 01:51:32
Objective: Validate Archive Workbench Tasks 1-7 foundation with evidence-backed technical, Chinese terminology, workflow, accessibility, and visual QC; freeze honest provider handoff boundaries
Task type: `complex_delivery_conference`
Risk: `high`
Conference mode: `parallel`

## Codex Main Venue

- Chair: Codex.
- Duties: understand the real task, decompose, define sources of truth, route work, protect boundaries, verify final artifacts, own visual/browser/PPT/PDF checks, own production writes, and deliver to the user.

## Conference Panel Assignment

- Chinese terminology, information architecture and implemented workflow review: Hermes `aishuo / MiniMax-M3`.
- Technical contract review: Hermes `aishuo / GLM-5.2`; if that primary route produces a terminal/provider-stale failure after the controlled retry, use Hermes `buddy / GLM-5.2` and record the primary failure.
- Security and high-risk backend review: Reasonix CLI `deepseek-pro` only. Hermes, buddy, OpenCode Go and direct DeepSeek routes are forbidden for DeepSeek V4 Pro.
- Visual review is a Codex-led panel with no Hermes chair: `aishuo / Gemini-3.5-Flash` and `buddy / kimi-k2.7-code` may provide image-grounded triage; Codex performs and accepts the original-resolution comparison.
- The guard-generated `general_buddy_deepseek` and `general_opencode_mimo` commands are not authorized for this task and will not be run.
- Every conference role is dispatched through a three-round same-session loop: independent pass, skeptical challenge, and corrected final pass. A new session is a routing failure unless a primary role failed before a resumable session existed and the documented fallback was activated.

## Source Of Truth

- `docs/superpowers/plans/2026-07-11-archive-workbench-foundation.md` Task 8.
- `.superpowers/sdd/progress.md` and Task 1-7 reports.
- `ArchiveWorkbench/Docs/foundation-acceptance.md` once the Codex-owned proof run writes it.
- `ArchiveWorkbench/Docs/security-spike-results.md`.
- `plans/mac_archive_app_requirements_traceability.md`.
- `design/2026-07-11_full_design_spec.md`.
- `ArchiveWorkbench/App/Sources/*.swift`, `App/Resources/Localizable.xcstrings`, `AppTests/*.swift`, and `AppUnitTests/*.swift` for implemented UI behavior.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/**` and tests for current domain/security/scheduler contracts.
- `ArchiveWorkbench/HelperSpike/**`, fixtures and tests for the helper boundary.
- Current original-resolution screenshots under `.superpowers/sdd/task-8-visual/current-*.png` and the visual source `design/assets/adaptive-finder-media-visual-target-v3.png`. Task 6 screenshots are historical only because they predate the user's latest toolbar correction.
- Do not add production paths unless the user explicitly authorized reading them for this task.

## Scope

- In scope: determine whether the Tasks 1-7 foundation is honestly accepted; audit implemented Chinese labels/workflows, accessibility, architecture contracts, security boundaries and current rendered shell; freeze interfaces and explicit pending provider work.
- Out of scope: claiming real ZIP/7z/TAR/RAR provider integration, RAR creation, physical Windows interoperability, complete Office real-fixture preview, signing/notarization, website/GitHub distribution, or commercial-product completion.

## Success Criteria

- All Task 8 proof commands have exact results and artifact hashes.
- Five skeptical risks are each linked to direct evidence or remain open.
- MiniMax-M3, GLM-5.2, Reasonix deepseek-pro and image-grounded visual consultations are boundary-audited; route failures remain visible.
- Codex resolves every Critical/Important finding or keeps the relevant foundation requirement open.
- The traceability matrix marks only directly proven foundation requirements and keeps provider/E2E requirements pending.
- No remote upload, deployment, notarization, or public release occurs.

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

- 2026-07-12 01:51:32: Conference initialized by `hermes_workflow_guard.py init-conference`.
- 2026-07-12: Codex overrode the generic generated routing to honor the user-specific aishuo/GLM fallback and the governing Reasonix-only DeepSeek V4 rule.
