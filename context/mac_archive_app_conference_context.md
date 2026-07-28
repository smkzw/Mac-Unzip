# Conference Context: mac_archive_app

Created: 2026-07-11 10:27:13
Objective: 调研、设计、构建并多重验证原生 Apple Silicon macOS 压缩与压缩包内容查看编辑 App，确保 Windows 与多语言兼容并达到商业化可用状态
Task type: `complex_delivery_conference`
Risk: `high`
Conference mode: `parallel`

## Codex Main Venue

- Chair: Codex.
- Duties: understand the real task, decompose, define sources of truth, route work, protect boundaries, verify final artifacts, own visual/browser/PPT/PDF checks, own production writes, and deliver to the user.

## Hermes And Reasonix Delegation

- Lead/chair: OpenCode Go `minimax-m3`.
- Hermes participant models: OpenCode Go `qwen3.7-plus` and OpenCode Go `mimo-v2.5`, all default reasoning effort unless Codex overrides.
- Reasonix CLI participant model: `deepseek-flash` alias for `deepseek-v4-flash`.
- All `deepseek-v4-flash` and `deepseek-v4-pro` routes must leave Hermes and run through Reasonix CLI. OpenCode Go, Hermes custom providers, and the direct DeepSeek provider are not allowed for these models in this workflow.
- `qwen3.7-plus` must be smoke-tested in this route because it recently had intermittent run errors.
- Main-venue high-risk reviewer: Reasonix CLI `deepseek-pro` alias for `deepseek-v4-pro` only. Hermes/OpenCode Go/direct DeepSeek routes are not allowed for this role.

## Source Of Truth

- User objective recorded in this file and the active Codex goal.
- `research/2026-07-11_initial_landscape.md`: Codex-collected current product, framework, format, and licensing evidence.
- Apple, RARLAB, product-vendor, and upstream repository URLs listed in the research packet are the external authorities; model summaries are advisory only.
- Do not add production paths unless the user explicitly authorized reading them for this task.

## Scope

- In scope: Apple Silicon-only native macOS app; latest macOS/SwiftUI/AppKit surface; Liquid Glass; Chinese-first UI; archive create/extract/browse/preview/edit; Windows-readable outputs; multilingual filenames; security, performance, accessibility, signing/notarization, and commercial-quality QA.
- Provisional format baseline approved by user on 2026-07-11: ZIP and 7z create/extract/browse/edit/encrypt; TAR/GZIP/BZIP2/XZ/Zstandard create/extract/browse; RAR extract/browse and create only if a legally distributable commercial-safe implementation exists; DMG/ISO read-only browse/extract.
- Out of scope until explicitly approved: Intel support, iOS/iPadOS, cloud sync, archive hosting, destructive in-place mutation without recoverable transaction semantics.

## Success Criteria

- Written design and implementation plan approved before code scaffolding.
- Current commercial/open-source landscape and licenses documented with queryable sources.
- Fresh Apple Silicon build on latest available full Xcode and macOS SDK.
- Format capability matrix verified with generated fixtures, corruption/adversarial fixtures, multilingual filenames, large files, symlinks, permissions, encryption, and multipart cases where applicable.
- ZIP outputs verified on Windows 11 with Explorer and 7-Zip; 7z outputs verified with current 7-Zip on Windows.
- Archive mutation uses staged rewrite plus atomic replacement, crash recovery, and explicit save state.
- Zip Slip, path traversal, symlink escape, decompression-bomb, password, quarantine, and resource-limit defenses tested.
- Chinese terminology reviewed by Hermes/aishuo MiniMax-M3 and GLM-5.2, then accepted by Codex/user in the written spec.
- Every UI/workflow/backend capability has an auditable multi-model QC record, but Codex owns final runtime and visual acceptance.

## Parallel Work Rule

For logic-heavy, rigor-sensitive, or artifact-heavy tasks, each participant independently runs the whole bounded workflow and writes a separate output. Leads compare after all available participant outputs are in or explicitly marked pending.

## Timeout Policy

- Participant soft wait: 20 minutes.
- Large-task participant wait: 45 minutes.
- Lead/main hard wait: 90 minutes.
- Failure rule: Do not fail a model for slow response alone; fail only on terminal error, provider exhaustion/rate limit after controlled retry, empty/truncated retry output, or no progress after hard wait plus one retry.

## Risk Boundaries

- Hermes and Reasonix are advisory; Codex remains final authority.
- Codex owns visual/browser/PPT/PDF/rendered checks, live authority checks, final clinical/regulatory conclusions, and production writes.
- Do not mark a slow model failed solely due to latency.

## Loop Log

- 2026-07-11 10:27:13: Conference initialized by `hermes_workflow_guard.py init-conference`.
- 2026-07-11: Workspace has no existing archive app project and is not a Git repository. macOS 26.5.1 is installed; only Command Line Tools are selected, so full Xcode is a pre-implementation dependency.
- 2026-07-11: User approved the recommended format matrix, adding RAR creation only if an open-source/commercially lawful solution exists.
- 2026-07-11: Local route inspection found Hermes/aishuo MiniMax-M3 and GLM-5.2 available. Higher-priority workflow rules prohibit DeepSeek V4 Pro through Hermes/buddy; it must use Reasonix CLI `deepseek-pro`.
- 2026-07-11: Three independent source-bounded reviews completed with exit code 0. Codex rejected unsupported claims after source and current-system checks: ZIPFoundation has ZIP64 and UTF-8 bit-11 support but no encryption; libarchive has permissively licensed native RAR4/RAR5 readers; SimpleZip discloses and optionally installs proprietary RARLAB `rar`; sandboxed apps can embed signed command-line helpers.
- 2026-07-11: Current macOS 26.5.1 Simplified Chinese strings confirm Apple uses `归档`, `创建归档`, `解压缩`, `设置`, and `钥匙串`; model terminology must not override live OS evidence.
- 2026-07-11: Local Apple Silicon upstream validation passed minizip-ng 244/244 tests and libarchive 1005/1005 test targets with zero failures. The libarchive harness still disabled/skipped 63 platform, optional-filter, encoding, and fixture-gated cases; these are tracked as remaining coverage rather than silently counted as passes.
- 2026-07-11: Microsoft current documentation establishes two Windows receiver tiers: Windows 11 24H2 natively opens ZIP/RAR/7z/TAR but does not operate on encrypted archives; encrypted output requires 7-Zip/WinRAR. A W0/W1/W2 interoperability contract was drafted.
- 2026-07-11: User first clarified that immediate use is self-installation on their own Mac, which removed Mac App Store work and made local build acceptance the first target. A later clarification added website/OpenSource readiness; see the newer entry below.
- 2026-07-11: User clarified that “commercial” is the frontend/backend capability and quality benchmark, not a request to commercialize, sell or publicly distribute the app. Keep commercial-grade functional, stability, security, performance, visual and user-workflow acceptance; exclude sales, store review, public release operations and channel compliance.
- 2026-07-11: User added future website distribution and a possible GitHub open-source edition as architecture-compatibility requirements. Mac App Store remains excluded. No GitHub upload, remote-repository creation, website deployment or public release is authorized without a later explicit command. Maintain Local/Direct/OpenSource build profiles over one shared core.
- 2026-07-11: User authorized buddy/GLM-5.2 as fallback if aishuo/GLM-5.2 fails, and aishuo/Gemini-3.5-Flash plus buddy/Kimi-K2.7-Code as optional visual-QC peers. Codex retains final rendered acceptance.
- 2026-07-11: Architecture QC-2 aishuo/GLM-5.2 produced no output after three API retries and five consecutive stale-response checks; the CLI printed a provider-unresponsive terminal message despite exit code 0. Route is recorded failed and rerouted to buddy/GLM-5.2. MiniMax-M3 and Reasonix DeepSeek Pro completed; MiniMax read one extra prior-review file outside its task whitelist, so its content is advisory but its boundary gate failed.
- 2026-07-11: buddy/GLM-5.2 fallback completed successfully. Codex synthesized all QC-2 outputs, rejected unsupported/contradictory claims, and revised Option A to close deterministic routing, same-volume staging, split-set save semantics, source fingerprinting, helper lifecycle, preview isolation, nested-archive limits, RARLAB validation, build/license profiles and Windows filename-contract gaps. Revised Option A now awaits user approval.
- 2026-07-11: Product Design preflight found no saved user visual context. Codex generated three independent native macOS/Liquid Glass main-window directions: three-column workbench, content-first editor, and preview-driven browser. Visual selection remains pending; no UI code was scaffolded.
- 2026-07-11: Codex created `plans/mac_archive_app_requirements_traceability.md`, mapping the complete goal and later clarifications to functional, format, security, cross-platform, visual, accessibility, performance, model-QC and delivery evidence. It is the completion-audit source of truth and explicitly preserves all pending gates.
- 2026-07-11: User explicitly approved architecture Option A and selected a combined visual direction: Finder-native direction 1 for ordinary/mixed archives and direction 3 for image/video-heavy contents. The shell remains stable; view mode is manually controllable and locally remembered. Decision recorded in `design/2026-07-11_visual_direction_decision.md`; a revised combined visual is the final ideation gate before full specification.
- 2026-07-11: User waived further stage-by-stage approvals and authorized Codex to choose the most suitable in-scope route through research, specification, implementation, test and optimization. External upload/public release remains prohibited without explicit command. Codex will continue automatically after QC gates rather than stop for design-spec approval.
- 2026-07-11: Deeper mature-product design research completed across BetterZip, Bandizip, Keka, PeaZip, MacZip, Finder/Quick Look, ForkLift, QSpace, Commander One and the locally installed The Unarchiver. Adopt/reject decisions and required spec changes are recorded in `research/2026-07-11_mature_product_design_synthesis.md`.
