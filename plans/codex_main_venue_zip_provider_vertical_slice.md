# Codex Main-Venue Plan: zip_provider_vertical_slice

Date: 2026-07-12
Objective: Validate the real ZIP provider vertical slice: pinned minizip bridge, safe UTF-8 list/read/materialization, Windows-native ZIP creation, Chinese native app binding, security boundaries, and honest acceptance gates.

## Task Decomposition

1. Verify C handle ownership, CRC behavior, bounded entry listing, bounded reads, and unsafe-path rejection.
2. Verify descriptor-rooted materialization and Windows ZIP transaction behavior.
3. Bind real ZIP snapshots to the native App without advertising unfinished workflows.
4. Replace decorative sidebar/count behavior with provider-derived state and specific Chinese errors.
5. Run package, sanitizer, concurrency, Xcode unit, interoperability, signing, and rendered-state checks.
6. Adjudicate every delegated finding against the pinned source and tests.

## Source Packet

- Git baseline `61accd0` plus the current reviewed changes on `feature/archive-zip-provider`.
- `docs/superpowers/plans/2026-07-12-zip-provider-vertical-slice.md`.
- C bridge, provider, Windows profile, secure materializer, App model/views, and their focused tests.
- Local interoperability output from 7-Zip 26.02 and `/usr/bin/unzip`.

## Participant Assignments And Disposition

| Role | Provider / model | Output | Disposition |
|---|---|---|---|
| Chinese UX | aishuo / MiniMax-M3 | `runs/conference/zip_provider_vertical_slice/aishuo_minimax_bounded_rerun.md` | Incorporated after boundary-clean rerun |
| Architecture | aishuo / glm-5.2 | `runs/conference/zip_provider_vertical_slice/aishuo_glm_architecture.md` | Reviewed; false positives rejected, fingerprint/stress suggestions retained |
| Security | Reasonix / deepseek-pro | `runs/reasonix_zip_provider_security.md` | Incorporated after source-level adjudication |
| Visual | Codex; Gemini/Kimi advisory only if current screenshot exists | none | Open: application cannot be activated from current macOS test session |

The generic generated Buddy/DeepSeek, Mimo, and Buddy/GLM placeholders were not dispatched. DeepSeek V4 remained on the required Reasonix route. Buddy GLM fallback was not needed because aishuo GLM completed.

## Main-Venue Review

- Codex owns final source, test, interoperability, signing, and visual judgments.
- Delegated severity labels were not accepted without checking pinned minizip-ng and current source.
- The original MiniMax run was excluded because it read outside its allowlist. A new embedded-evidence run passed preflight and respected the boundary.

## Codex Verification Checklist

- Package suite: passed, 21 XCTest plus 34 Swift Testing tests.
- C close-state regression: passed, 2 focused tests.
- Xcode App unit suite: passed, 14 tests; root-category follow-up: 4 focused tests passed.
- ASan provider tests: passed with macOS-supported leak setting; TSan provider tests: passed with no race.
- Windows profile ZIP: 7-Zip and `/usr/bin/unzip` both accepted; UTF-8 flag and Deflate confirmed; Mac metadata absent.
- arm64 build and strict local code-sign verification: passed.
- Real provider UI automation: blocked before assertions because XCTest reports the app as `Running Background`; a clean baseline commit reproduced the same global condition.

## Exit Decision

Accept the non-visual ZIP provider milestone. Keep rendered provider-state acceptance open and do not mark the complete product finished.
