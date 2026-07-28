# Codex Conference Review: zip_provider_vertical_slice

Date: 2026-07-12

## Verdict

PASS for the non-visual ZIP provider milestone. The complete product is not finished, and current rendered provider-state acceptance remains open.

## Boundary Compliance

- The first MiniMax output violated its read allowlist and was excluded.
- A bounded embedded-evidence MiniMax rerun passed guard preflight and is the only MiniMax evidence accepted.
- aishuo GLM completed; Buddy fallback was therefore not used.
- DeepSeek Pro ran only through Reasonix CLI.
- No visual model was given a stale screenshot as current-provider evidence.

## Participant Outputs Reviewed

- MiniMax-M3: accepted the low-frequency `检测完整性` placement under labeled `操作`, dynamic directories/counts, Finder-like list terminology, and specific Chinese errors. Its optional suggestion to rename `压缩包根目录` was not adopted because the current wording is unambiguous.
- GLM-5.2: rejected its claimed reader leak, CRC mapping gap, and partial-write defect after source inspection. Retained the recommendation for stronger source-change defenses and malformed-open stress coverage.
- Reasonix DeepSeek Pro: rejected C1 because pinned minizip-ng 4.2.1 verifies CRC in `mz_zip_entry_read_close`, and the bridge checks `awb_mz_reader_close_current`. Accepted entry-count limiting, directory path validation, encrypted-entry preflight, immediate per-file fingerprint recheck, and clearing the C current-entry pointer after close.

## Hermes Sub-Venue Review

Hermes supplied the aishuo MiniMax-M3 Chinese UX pass and the aishuo GLM-5.2 architecture pass. Codex treated both as advisory, excluded the boundary-breaking MiniMax run, reran it with a fixed evidence packet, and independently checked every incorporated claim.

## Main-Venue Codex Review

Implemented and verified:

- provider-derived sidebar directories and counts;
- directory plus search scoped `visibleEntries` and dynamic toolbar count;
- last-component file naming in the Finder-like table;
- specific Chinese archive errors;
- `检测完整性` disabled in both real state and fixture, remaining a secondary menu item;
- one-million-entry listing ceiling with a low-limit regression seam;
- unsafe directory-entry rejection;
- encrypted read returns `passwordRequired` before decompression;
- per-file source fingerprint recheck immediately after writing;
- C current-entry pointer invalidated after close;
- root-file selection correctly keeps `压缩包根目录` visible.

## Codex Independent Verification

- Package tests, focused C regression, App unit tests, ASan, TSan, build, arm64 architecture, local signature, and two independent ZIP readers passed.
- The real ZIP UI test did not reach any UI assertion because macOS/XCTest could not activate the app and reported `Running Background`. A detached clean baseline reproduced zero windows, so this is recorded as an environment-level open gate rather than a product pass or product regression.
- Physical Windows Explorer has not yet been tested; compatibility is supported by ZIP metadata inspection plus 7-Zip and Info-ZIP, not claimed as physical-Windows proof.

## Final Decision

Commit the reviewed provider hardening and App-state corrections as a milestone. Continue with real extraction, editing transaction, encryption/legacy names, preview materialization, additional formats, RAR-provider validation, and distribution preparation. Re-run rendered visual QC as soon as the macOS window activation state recovers.
