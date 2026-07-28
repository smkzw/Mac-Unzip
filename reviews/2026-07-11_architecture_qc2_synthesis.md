# Architecture QC-2 Codex Synthesis

Date: 2026-07-11
Status: Codex adjudication complete; revised Option A awaits user approval

## Route evidence

| Reviewer | Route result | Acceptance |
|---|---|---|
| MiniMax-M3 | Completed 406-line product/Chinese UX review | Content used selectively; process gate failed because it read one unlisted prior-review file. It also retained internal `展开`/`提取` wording contradictions, which Codex rejected. |
| aishuo GLM-5.2 | No output after provider-stale detection, three API retries and five consecutive stale checks | Failed; terminal failure text overrides process exit code 0. |
| buddy GLM-5.2 | Completed 477-line source-bounded technical review | Accepted as the user-authorized GLM fallback after Codex file/boundary review. |
| Reasonix `deepseek-pro` | Completed 336-line adversarial review | Accepted after Codex file/boundary review. This is the required DeepSeek V4 Pro route; no Hermes/buddy DeepSeek route was used. |

All substantive reviewers converged on Option A. Option B remains a prototype/fallback because one CLI helper would own too many common operations. Option C is rejected because it cannot satisfy encrypted 7z and encrypted RAR extraction requirements.

## Accepted findings and resulting changes

1. Engine overlap was underspecified. The architecture now has exactly one primary engine per `(format, operation)` tuple, structured fallback reasons, read-only fallback limits and a prohibition on switching engines mid-mutation.
2. “Sibling staging when possible” was too weak. Sibling same-volume staging is mandatory; otherwise save becomes `另存为…`. Single-file archives use fsync plus atomic replacement.
3. Split archives are not one atomic file. Existing split archives use `另存为…`; a complete new part set is staged and verified before publication. The product no longer claims atomic in-place split-set replacement.
4. Source-change detection now uses coordinated access, file identity/metadata and SHA-256 at open and before commit. A mismatch stops save.
5. Helper lifecycle is short-lived per operation in v1, with private working directories, explicit concurrency limits, bounded output drains, version/identity checks and cancellation escalation.
6. Preview extraction now uses a random per-window cache root, random filesystem names, no-follow/exclusive creation, canonical containment checks, quarantine and strict quotas. Archive paths never become cache paths.
7. Nested archives never recurse automatically; child sessions share aggregate depth/byte/time budgets.
8. RARLAB discovery now requires explicit selection/confirmation, symlink resolution, ownership/permission/architecture/version checks and a live create/test/extract probe.
9. Local/Direct/OpenSource build profiles now have distinct 7-Zip/RARLAB/signing/license boundaries while sharing the same domain model. No upload or release is authorized.
10. Windows naming rules now follow Microsoft’s current official list, including superscript COM/LPT device names, invalid characters, trailing space/period, case-insensitive/canonical-equivalent collisions and a conservative path budget with a visible conflict-resolution workflow.
11. PKWARE APPNOTE resolves the UTF-8 ambiguity: W0 defaults to UTF-8 bit 11 without redundant Unicode Path extra fields. The alternate legacy representation remains a differential-test candidate.
12. DMG mount is a separate read-only, no-auto-open/no-browse provider with mount identity, detach and crash recovery.

## Findings rejected or narrowed by Codex

- Cross-volume `rename()` does not “silently fail”; it returns an error such as `EXDEV`. The design still forbids cross-volume commit because falling back to copy-and-delete would destroy atomicity.
- A universal 260-character archive-relative limit is not technically meaningful because the Windows extraction root is unknown and modern long-path behavior varies. The product uses a conservative relative budget, discloses the assumption and requires physical Explorer extraction evidence.
- `$MFT` and similar NTFS metadata names were suggested by one reviewer without primary evidence in the cited Win32 naming contract. They are not added to the normative W0 DOS-device list unless physical tests or an authoritative source require them.
- MiniMax’s `展开` and `提取` primary commands are rejected. Current macOS Simplified Chinese evidence supports `解压缩`; `创建归档` is the creation command. `展开` may describe disclosure of a tree row, not archive extraction.
- Model-proposed performance numbers are not treated as passed requirements. The revised budgets are explicit hypotheses for target-Mac benchmarking and tuning.

## Remaining design-to-build gates

- User approval of revised Option A.
- Full design specification and its QC-3 review.
- Full Xcode installation; current machine has Command Line Tools only.
- Physical Windows 11 24H2, Windows 7-Zip and WinRAR interoperability environment.
- Exact application open-source license selection before any OpenSource profile is published.
- Component/SBOM/license-notice generation and clean-build verification.
- No GitHub remote, upload, website deployment or public artifact until explicit user authorization.
