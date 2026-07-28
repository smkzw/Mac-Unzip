# Codex Conference Review: mac_archive_app

Date: 2026-07-11

## Verdict

Current stage: **revise before design recommendation**. The three requested independent reviews completed successfully and materially expanded the threat, test, and terminology surface, but several model claims were contradicted by current source inspection or Apple documentation. No implementation decision is accepted yet.

## Boundary Compliance

- Hermes/aishuo MiniMax-M3 and GLM-5.2 each read the global SOUL plus the three allowed task files and wrote exactly one run file.
- Reasonix `deepseek-pro` read only the three task files and wrote exactly one run file.
- All three prompts passed workflow preflight. All three exit codes were 0.
- DeepSeek V4 Pro did not run through Hermes/buddy because the governing route explicitly forbids that provider path; it ran through Reasonix CLI.

## Participant Outputs Reviewed

- `runs/conference/mac_archive_app/participant_aishuo_minimax.md`: strong user-scenario expansion and comprehensive Chinese terminology proposal; terminology claims still require verification against current macOS Simplified Chinese strings.
- `runs/conference/mac_archive_app/participant_aishuo_glm.md`: useful four-layer architecture, security invariants, and test matrices; several engine/license statements were over-broad.
- `runs/conference/mac_archive_app/participant_reasonix_deepseek_pro_research.md`: strong skeptical threat/verification matrices; incorrectly treated SimpleZip's RAR claim as deceptive before inspecting its source.

## Hermes Sub-Venue Review

Second-pass chair review completed in `runs/conference/mac_archive_app/hermes_lead.md`. It correctly adopted most Codex corrections and identified distribution channel as the next decision. Its self-description incorrectly says OpenCode Go `minimax-m3`; stdout proves aishuo `MiniMax-M3`, so the metrics record overrides that narrative error. Its route-C/App-Store proposal would omit required 7z creation and is therefore not an acceptable final route without an embedded lawful 7z writer/helper.

## Main-Venue DeepSeek Pro Review

Initial independent review complete. A final main-venue review remains pending until the Hermes chair package and user distribution decision exist.

## Codex Independent Verification

- Current Apple documentation confirms sandboxed macOS apps can embed and execute a signed command-line helper. Therefore the participant claim "App Sandbox cannot exec external CLI" is false as a categorical statement; sandboxing affects helper packaging, entitlements, external-file access, and external/user-installed tool discovery, not all helper execution.
- Current Apple distribution documentation confirms App Store distribution requires App Sandbox; direct Developer ID distribution requires hardened runtime and notarization, with sandbox optional.
- SimpleZip source inspection confirms its RAR creation is not an open-source encoder: it downloads/detects RARLAB's proprietary `rar` CLI, discloses the shareware license, and refuses to bundle it by default. The feature is not deceptive in its current README, but it is unsuitable as evidence of an open-source RAR writer.
- ZIPFoundation source inspection confirms UTF-8 entry writing with bit 11, explicit ZIP64 tests, and no encryption support. It is not sufficient alone for the approved encrypted ZIP scope.
- libarchive source inspection confirms independent permissively licensed RAR4/RAR5 readers. Statements that libarchive's RAR reader necessarily imports UnRAR restrictions are unsupported and should be removed.
- Local upstream builds add material feasibility evidence: minizip-ng completed 244/244 tests with zero failures, and libarchive completed all 1005 configured test targets with zero failures. Libarchive's 63 skipped/disabled platform, optional-filter, encoding, and RAR-fixture cases remain explicit product test obligations.
- Current macOS 26.5.1 `Archive Utility.app` Simplified Chinese localization was inspected directly. Apple currently uses `归档`, `创建归档…`, `解压缩归档…`, `正在解压缩…`, `设置…`, and `将密码储存在钥匙串中`. Therefore MiniMax-M3's categorical recommendations to replace `解压缩` with `展开`, use `偏好设置`, or hide the Keychain name are not native-current macOS wording. Product-facing labels may still use the more familiar noun `压缩包`, but native action/setting terminology should start from Apple's actual strings and be user-tested.
- Full Xcode is still unavailable locally, so Liquid Glass SDK/API compilation and rendered acceptance have not yet been performed.
- Windows 11 interoperability remains unverified and is a release-blocking requirement, not a documentation inference.

## Final Decision

Keep research/design active. Immediate use is local self-installation, while the architecture must remain ready for a future notarized website build and possible GitHub open-source edition; no upload/release is authorized. Recommended direction is a capability-routed native SwiftUI/AppKit shell with transaction-safe mutation, minizip-ng, libarchive, isolated 7zz and a separately licensed/user-installed RARLAB provider. RAR creation still cannot be provided by open source under current evidence.
