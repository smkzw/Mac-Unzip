# macOS Archive App Requirements Traceability Matrix

Date: 2026-07-12
Owner: Codex
Status: living acceptance contract; Tasks 1–7 foundation accepted for provider handoff, product completion remains open

## Status vocabulary

- `Confirmed`: requirement and boundary are explicit.
- `Designed`: architecture/acceptance approach exists but is not implemented.
- `Evidence partial`: some primary/source/build evidence exists; end-to-end proof is missing.
- `Pending decision`: a user selection is required before dependent work.
- `Pending implementation`: approved scope, no implementation evidence yet.
- `Pending environment`: proof needs an unavailable environment/tool.

## Product and delivery requirements

| ID | Requirement | Acceptance evidence | Current state | Authoritative source/evidence |
|---|---|---|---|---|
| P-001 | Product capability and finish must match a formal commercial archive product; commercialization/sales are not required | Requirement-by-requirement functional, stability, security, performance, visual, accessibility and E2E acceptance packet | Confirmed; not implemented | User clarification; `context/mac_archive_app_conference_context.md` |
| P-002 | Current artifact installs on the user’s own Mac | Fresh local install, first launch, open/create/extract/edit workflows on target Mac | Pending implementation | User clarification |
| P-003 | Architecture supports a future website-distributed build | `Direct` build target, hardened runtime, Developer ID/notarization readiness, clean-machine install verification | Designed; publishing unauthorized | `research/2026-07-11_architecture_options.md` |
| P-004 | Architecture supports a possible GitHub open-source edition | Reproducible `OpenSource` build, selected app license, SPDX SBOM, third-party notices, no proprietary RAR binary | Designed; license decision later | User clarification; architecture options |
| P-005 | Mac App Store is not a target | No Store receipt/review/sandbox-specific product branch | Confirmed | User clarification |
| P-006 | No remote repository, GitHub upload, website deployment or public release without explicit command | No configured git remote/deployment action; release action gate requires new user authorization | Confirmed and currently satisfied | User clarification; current workspace inspection |

## Platform and visual requirements

| ID | Requirement | Acceptance evidence | Current state | Source/evidence |
|---|---|---|---|---|
| V-001 | Latest native macOS application | Build/run with latest installed full Xcode and current macOS SDK; native app bundle | Evidence partial; native foundation builds/runs on macOS 26.5.1 with Xcode 26.6/SDK 26.5 | `ArchiveWorkbench/Docs/foundation-acceptance.md` |
| V-002 | Apple Silicon only; no Intel compatibility work | Build architecture inspection contains `arm64` only; launch on target Mac | Foundation pass; app/helper/fixtures are arm64-only | `ArchiveWorkbench/Docs/foundation-acceptance.md` binary proof |
| V-003 | SwiftUI/AppKit native frontend | Xcode project, dependency graph and runtime UI inspection | Foundation pass; native document shell implemented | `ArchiveWorkbench/App/Sources`; clean Xcode scheme |
| V-004 | Native Liquid Glass hierarchy | Toolbar/sidebar/inspector use current system APIs; no decorative glass over content; Reduce Transparency/Contrast checks | Evidence partial; native shell and four rendered appearance states exist, provider states pending | `.superpowers/sdd/task-8-visual/current-*.png` |
| V-005 | Current native macOS-style icon | Icon Composer source, light/dark/tinted/clear appearances, small-size legibility screenshots | Pending visual selection/design | User objective; Apple Icon Composer guidance |
| V-006 | Main UI visual direction selected by user | Explicit selection of generated direction 1, 2 or 3, or a requested combination | Confirmed: direction 1 + 3 adaptive combination; revised mock pending | `design/2026-07-11_visual_direction_decision.md` |
| V-007 | Architecture route selected by user | Explicit approval of revised Option A | Confirmed: Option A approved | User decision; `research/2026-07-11_architecture_options.md` |
| V-008 | Desktop window works at realistic sizes | Original-resolution inspection at default, minimum, maximized and multi-display scale factors; toolbar/title/search/system controls never overlap; long multilingual filenames remain single-line with middle truncation and full accessible/help text | Evidence partial; default/900-point toolbar and long-name regressions pass, current primary media strip is edge-safe; maximized/multi-display/provider states pending | `DocumentShellTests`; Task 8 screenshots |
| V-009 | Accessibility is first-class | VoiceOver, Full Keyboard Access, focus order, contrast, Reduce Motion/Transparency, localization expansion checks | Evidence partial; automated keyboard/accessibility audit and contrast/transparency renders pass; manual VoiceOver workflows pending | `DocumentShellTests`; foundation acceptance |

## Language and filename requirements

| ID | Requirement | Acceptance evidence | Current state | Source/evidence |
|---|---|---|---|---|
| L-001 | All primary buttons, labels and settings use natural Simplified Chinese | Complete String Catalog review; screenshots of all states; no stray English scan | Evidence partial; current foundation shell commands are Chinese, complete future screens/catalogs pending | `Localizable.xcstrings`; foundation acceptance |
| L-002 | Chinese terms are reviewed by aishuo MiniMax-M3 and Codex | Per-screen glossary review output plus Codex comparison with live macOS strings | Foundation surface pass; current MiniMax three-round review accepts `操作` hierarchy and low-frequency `检测完整性` placement | `runs/conference/archive_foundation_acceptance/general_aishuo_minimax.md`; Codex review |
| L-003 | Apple-native terms take precedence over model preference | Commands consistently use `归档`, `创建归档`, `解压缩`, `设置`, `钥匙串`; `展开` reserved for disclosure/navigation | Designed | macOS 26.5.1 live strings; QC synthesis |
| L-004 | Localization architecture supports multiple UI languages | String Catalogs, contextual comments, plural rules, pseudolocalization/layout tests | Designed | Architecture option A |
| L-005 | v1 authored UI locales | `zh-Hans`, `zh-Hant`, and English strings complete; other locales architecture-ready | Proposed; full spec pending | MiniMax QC-2 recommendation; user asked Chinese/English/multilingual compatibility |
| L-006 | Archive filenames support multilingual Unicode | Round trip Simplified/Traditional Chinese, Japanese, Korean, Arabic/RTL, Latin diacritics, emoji and supplementary-plane characters | Evidence partial | Local 7-Zip smoke; physical Windows pending |
| L-007 | Existing archive name bytes are not silently rewritten | Before/after central-directory byte comparison for unchanged entries | Designed; pending tests | Architecture option A |
| L-008 | Legacy encodings are reversible and explicit | CP437/CP932/CP936/CP950 fixtures; confidence/override UI; reopen reproduces selected decoding | Designed; pending fixtures | minizip-ng capability and QC-2 |
| L-009 | Windows filename conflicts are preflighted | Tests for invalid characters, device names, trailing dot/space, canonical/case collisions and path budget | Designed; pending implementation | Microsoft naming rules; Windows contract |

## Format capability requirements

| ID | Format | Required operations | Engine/provider design | Proof required | State |
|---|---|---|---|---|---|
| F-001 | ZIP | Create, browse, search, preview, extract, add, remove, rename, replace, encrypt, split, integrity/repair where supported | minizip-ng primary | Unit/integration/fixture/fuzz/Windows tests | Evidence partial; engine 244/244 passed |
| F-002 | 7z | Create, browse, search, preview, extract, update/edit, AES encryption, encrypted headers, split, integrity test | isolated pinned `7zz` | Helper contract, mutation, cancellation, encrypted/multipart Windows tests | Evidence partial; local smoke passed |
| F-003 | TAR | Create, browse, extract | libarchive | Round trip metadata/security/Windows tar tests | Evidence partial; upstream suite passed |
| F-004 | GZIP | Create/extract/browse as single stream and TAR.GZ composition | libarchive | Stream and composed archive fixtures | Evidence partial |
| F-005 | BZIP2 | Create/extract/browse as stream and TAR.BZ2 composition | libarchive | Stream/composition fixtures | Evidence partial |
| F-006 | XZ | Create/extract/browse as stream and TAR.XZ composition | libarchive | Stream/composition fixtures | Evidence partial |
| F-007 | Zstandard | Create/extract/browse as stream and TAR.ZST composition | libarchive | Stream/composition and Windows-tool proof | Evidence partial |
| F-008 | RAR | Browse, search, preview and extract including encrypted/multipart cases | `7zz`; libarchive unencrypted diagnostic fallback | RAR4/5, encrypted, solid, Unicode, multipart fixtures | Evidence partial; libarchive fixture gaps open |
| F-009 | RAR | Create/update when lawful provider is installed | separately installed licensed RARLAB `rar`; never bundled | Executable identity/version/license acknowledgement plus live create/test/extract probe and Windows WinRAR test | Designed; provider not installed/verified |
| F-010 | DMG | Read-only browse/mount/extract workflow | isolated macOS disk-image provider | Read-only/no-auto-open/no-browse mount, detach/recovery/adversarial image tests | Designed |
| F-011 | ISO | Read-only browse/extract | libarchive primary | ISO9660/UDF/Joliet/Rock Ridge fixture matrix | Evidence partial |
| F-012 | Format detection | Detect by signatures/capabilities, not extension alone | capability registry | Mismatched/absent extension fixtures | Designed |
| F-013 | Conversion | Deferred beyond v1; no menu, toolbar or contextual entry may be shown until a loss matrix and transaction design are approved | no v1 provider route | UI absence scan; later design gate | Explicitly deferred from v1 after QC-3 |

## Core user workflows

| ID | Workflow | Definition of done | Evidence state |
|---|---|---|---|
| W-001 | Open archive | File picker, drag/drop, Finder open-with and recent list open a supported archive; errors are categorized | Pending implementation |
| W-002 | Browse contents | Hierarchical outline/table supports large archives, sorting, columns, selection and keyboard navigation | Evidence partial; Finder-style fixture shell/list/media selection works, real large-archive provider pending |
| W-003 | Search/filter | Search name/path/type across archive without extracting; 100 ms indexed-feedback hypothesis measured | Evidence partial; fixture search works, real provider index/performance pending |
| W-004 | Preview selected entry | Safe bounded cache; native image/PDF/text/video viewers; system Quick Look for Word `.doc/.docx`, Excel `.xls/.xlsx`, PowerPoint `.ppt/.pptx`; no automatic execution; explicit failure state | Evidence partial; bounded descriptor-relative cache and image/PDFKit fixture proven; video and Office hosts exist but all real archive-entry formats remain pending |
| W-005 | Extract selected/all | Destination selection, collision policy, progress, cancellation, quarantine and post-extract verification | Designed |
| W-006 | Create archive | Source selection, format/preset/encryption/split/name policy, receiver warning, test-after-create | Designed |
| W-007 | Add items | Drag/drop and command add to editable formats; staged change visible | Designed |
| W-008 | Remove items | Staged removal, undo before save, source preserved on failure | Designed |
| W-009 | Rename items | Whole-tree collision/security preflight; staged rename; unchanged names preserved | Designed |
| W-010 | Replace/edit item | External-editor round trip or replace command uses controlled temp copy, immutable accepted snapshot and explicit save state | Designed in full spec §14.6 |
| W-011 | Save changes | Same-volume stage, verify, fsync, source SHA-256 recheck, atomic replace for single-file archive | Designed |
| W-012 | Save multipart changes | Always `另存为…`, stage/verify complete set, never claim atomic in-place replacement | Designed |
| W-013 | Encrypt/password | Secure fields; AES/ZipCrypto compatibility labels; optional Keychain; no password logging | Designed |
| W-014 | Integrity test/repair | Format-aware availability, structured result, repair never overwrites the only source | Designed; low-frequency `检测完整性` is intentionally under `操作`, provider behavior pending |
| W-015 | Queue/progress/cancel | Concurrent independent jobs, one mutation per archive, bounded helper lifecycle and safe cancellation | Evidence partial; actor scheduler and diagnostic helper cancellation/backpressure pass, production provider integration pending |
| W-016 | Crash recovery | Recovery journal discovers staged work; never auto-commits; user chooses recover/delete | Designed |
| W-017 | Nested archive | No automatic recursion; isolated child session with aggregate limits | Designed |
| W-018 | Missing split volume | Identify expected volume; validate volume identity/snapshot; allow locate/retry/cancel; never mislabel as corruption | Designed in full spec §20 |
| W-019 | Wrong password/unsupported encryption/corruption | Distinct states, distinct copy and recovery actions | Designed in full spec §§10, 18, 22 |
| W-020 | Finder/Quick Look integration | Read-only Quick Look extension and scoped Finder Quick Actions; no misuse of Finder Sync | Designed; pending Xcode |
| W-021 | Settings | Chinese categories for general, extraction, creation, compatibility, passwords, providers, privacy, advanced/diagnostics | Terminology/spec pending |
| W-022 | Help/diagnostics/licenses | Capability/provider status, redacted diagnostics, component/licenses, no private path/password leakage | Designed |

## Security and data-integrity requirements

| ID | Invariant | Required proof | State |
|---|---|---|---|
| S-001 | No shell command construction | Process-runner unit tests and source audit | Diagnostic foundation pass; production provider adapters pending |
| S-002 | Path traversal/absolute path rejection | Malicious ZIP/7z/RAR/TAR fixtures across preview and extraction | Evidence partial; pure path policy tests pass, real provider fixtures pending |
| S-003 | Symlink/hardlink escape prevention | Destination-containment fixtures and filesystem inspection | Designed |
| S-004 | Special files never previewed/executed automatically | FIFO/device/socket fixtures | Evidence partial; preview cache rejects non-regular/symlink paths, provider fixtures pending |
| S-005 | Decompression-bomb resource controls | Ratio/entry/depth/free-space/time fixtures and override policy | Designed |
| S-006 | Preview isolation | Random per-window cache roots, no-follow/exclusive open, quarantine, quota/TTL tests | Evidence partial; descriptor-relative no-follow cache and size ceiling pass, provider/session lifecycle pending |
| S-007 | Source archive survives failed/canceled mutation | Kill/fault injection at every transaction phase; hash source unchanged | Designed |
| S-008 | External source modification prevents commit | File identity and SHA-256 mismatch tests | Designed |
| S-009 | Helper identity/version is trusted explicitly | Symlink, writable executable, wrong architecture/version and output-injection tests | Evidence partial; fixed diagnostic 7zz identity/hash proven, production user-selected/bundled helper trust and spawn TOCTOU pending |
| S-010 | Password/private paths are absent from logs | Automated redaction scan and manual diagnostic review | Diagnostic foundation pass; argv/env/fd/stdout/stderr/process snapshot checks pass, production host pending |
| S-011 | DMG content never auto-runs and mounts read-only | Mount flags, process observation, stale-mount recovery tests | Designed |
| S-012 | No silent engine fallback during mutation | Capability registry contract and adapter tests | Evidence partial; deterministic registry contracts pass, runtime provider discovery/UI binding pending |

## Cross-platform acceptance requirements

| ID | Receiver contract | Required physical evidence | Current state |
|---|---|---|---|
| X-001 | Windows Explorer-native unencrypted ZIP | Windows 11 24H2 list/open/extract/hash comparison | Pending environment |
| X-002 | Windows Explorer unencrypted 7z/TAR/RAR cases | Windows 11 24H2 physical behavior matrix | Pending environment |
| X-003 | Windows 7-Zip encrypted ZIP/7z and multipart | Current Windows 7-Zip list/test/extract/hash | Pending environment |
| X-004 | WinRAR ZIP/7z/RAR, encrypted and multipart | Current WinRAR list/test/extract/hash | Pending environment |
| X-005 | Multilingual filenames | Explorer/7-Zip/WinRAR screenshots plus manifest/hash comparison | Pending environment |
| X-006 | ZIP64 and 4 GiB boundaries | Windows tool list/test/extract and byte/hash checks | Pending environment |
| X-007 | macOS metadata suppression preset | No `.DS_Store`, `._*`, `__MACOSX` visible in Windows | Pending implementation/environment |
| X-008 | Windows invalid/colliding paths | Preflight blocks or requires reviewed rename plan | Designed |

## Performance, accessibility and visual quality

| ID | Acceptance target | Proof | State |
|---|---|---|---|
| Q-001 | 100,000-entry first usable list ≤2 s hypothesis | Target-Mac signpost/Instruments benchmark | Pending environment/implementation |
| Q-002 | Indexed search feedback ≤100 ms hypothesis | Benchmark and UI signposts | Pending implementation |
| Q-003 | Scrolling target 60 fps | Instruments and original-resolution recording | Pending implementation |
| Q-004 | Cancel response ≤1 s in-process, ≤3 s helper before escalation | Deterministic cancellation tests | Evidence partial; diagnostic helper bounded timeout/cancel tests pass, production providers pending |
| Q-005 | Memory/disk use bounded | Large/archive-bomb benchmarks and cache accounting | Pending implementation |
| Q-006 | Visual consistency in light/dark and Liquid Glass accessibility modes | Real app screenshots at defined states; peer visual QC plus Codex acceptance | Evidence partial; current light/dark/reduce-transparency/increase-contrast shell inspected, provider states pending |
| Q-007 | Every core workflow usable by keyboard and VoiceOver | Accessibility test scripts/recordings | Evidence partial; current shell automated audit passes, real workflows/manual recordings pending |
| Q-008 | All visible Chinese fits without clipping | Screenshot matrix and accessibility labels | Evidence partial; toolbar/title/long-name/media-strip regressions pass at current fixture sizes, localization expansion and future screens pending |

## Multi-model QC routing contract

| ID | Surface | Required independent checks | Final authority/current note |
|---|---|---|---|
| M-001 | Chinese terminology/information architecture | aishuo MiniMax-M3; GLM-5.2 primary aishuo with user-authorized buddy fallback | Current MiniMax three-round review passed; aishuo GLM returned 503 and buddy GLM reported unsupported model, both retained as route failures |
| M-002 | Backend architecture/data integrity | MiniMax-M3, GLM-5.2, DeepSeek V4 Pro | Reasonix `deepseek-pro` completed bounded security review with provider-stage gates; GLM route unavailable in this pass; Codex remains final authority |
| M-003 | Every implemented function/workflow | Per-milestone bounded prompts to all required available routes, regression reruns after fixes | Codex runtime tests override model opinion |
| M-004 | Visual/aesthetic surface | aishuo Gemini-3.5-Flash and buddy Kimi-K2.7-Code may perform independent visual triage; MiniMax/GLM review wording/workflow | Codex performs final original-resolution real-app acceptance |
| M-005 | Failed/unavailable route | Preserve terminal evidence; controlled retry; use user-approved provider fallback; never silently substitute | Conference metrics and per-milestone QC packet |
| M-006 | Model boundary compliance | Prompt preflight, exact read/output lists, route/stdout/metrics verification | Boundary failure invalidates process acceptance even if content is useful |

## Build and completion gates

1. User selects revised architecture Option A. **Passed 2026-07-11.**
2. User selects one of the three generated visual directions or specifies a combination. **Passed: directions 1 + 3 with Finder-native refinement; implemented shell and current comparison renders exist.**
3. Full written design specification is produced, multi-model reviewed and revised; user has waived further stage approval, so Codex records the gate and proceeds automatically.
4. Full Xcode is installed/selected and the current SDK/toolchain is recorded. **Passed for foundation: Xcode 26.6, macOS SDK 26.5, Swift 6.3.3.**
5. Local git repository may be created for recoverable development; no remote or upload is allowed without a new command.
6. Implementation plan is produced before scaffolding.
7. Core, adapters, UI, extensions and packaging are implemented in testable milestones.
8. Every row above moves to evidence-backed pass or an explicitly user-approved removal; silence never counts as approval.
9. Real target-Mac visual/E2E acceptance and physical Windows interoperability pass.
10. Local install artifact is launched and all core user workflows are rerun from the user perspective.
11. Direct/OpenSource configurations build and pass boundary checks, but remain unpublished until explicitly authorized.
12. Completion audit maps every requirement to current evidence; the goal remains active until all required rows pass.
