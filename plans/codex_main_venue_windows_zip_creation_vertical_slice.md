# Codex Main-Venue Plan: windows_zip_creation_vertical_slice

Date: 2026-07-13
Objective: 设计并审查 Windows 11 原生兼容 ZIP 创建的端到端垂直切片：原生中文创建面板、输入与保存选择、全树兼容预检、流式创建、进度取消、同目录事务发布、创建后重新打开并核对清单/大小/SHA-256、失败清理和真实 E2E

## Task Decomposition

1. Audit the existing Windows ZIP provider and lock the verification/transaction contract.
2. RED/GREEN provider progress, cancellation and post-create manifest/hash validation without weakening exclusive publish.
3. RED/GREEN App loader/model creation state, native input/save flow and Chinese error mapping.
4. RED/GREEN real provider E2E and UI workflow; then visual/Chinese label panels.
5. Run conference synthesis, package/unit/UI/accessibility, Release arm64/signing and Windows interoperability evidence gates.

## Source Packet

- The ten local source/spec files listed in `context/windows_zip_creation_vertical_slice_conference_context.md`.
- Existing fresh package/unit/Release evidence from the preceding extraction milestone.
- Participants are advisory and must not edit source or treat unverified Windows behavior as proven.

## Participant Assignments

| Role | Provider | Model | Output |
|---|---|---|---|
| `general_aishuo_minimax` | `aishuo` | `MiniMax-M3` | `runs/conference/windows_zip_creation_vertical_slice/general_aishuo_minimax.md` |
| `general_buddy_deepseek` | `buddy` | `deepseek-v4-pro` | `runs/conference/windows_zip_creation_vertical_slice/general_buddy_deepseek.md` |
| `general_opencode_mimo` | `opencode-go` | `mimo-v2.5` | `runs/conference/windows_zip_creation_vertical_slice/general_opencode_mimo.md` |

## Sub-Venue Review

| Role | Provider | Model | Output |
|---|---|---|---|
| `general_chair_glm` | `buddy` | `glm-5.2` | `runs/conference/windows_zip_creation_vertical_slice/general_chair_glm.md` |

## Main-Venue Review

- Codex performs the final synthesis and acceptance.
- This conference mode has no Reasonix second-review role.

## Timeout And Retry Tracking

Participants will launch in parallel after prompt preflight. Record original session IDs, three-round continuation, provider/model identity, duration, API calls/tokens, non-terminal tool errors, retries/fallbacks and archive status.

## Codex Verification Checklist

- [x] Every behavior-changing API is observed RED before production implementation.
- [x] Creation is bounded-memory, cancellable and cleans staging on every failure path.
- [x] The compatibility manifest is deterministic and post-create verification checks names, types, sizes and SHA-256.
- [x] Existing targets and input files are never overwritten or mutated.
- [ ] Native Chinese creation UI supports file/folder input, output selection, progress/cancel and completion. Source/build exists; UI E2E and Finder integration remain unaccepted.
- [ ] Package, App unit, UI/accessibility, Release arm64/signing and cross-platform artifact gates pass with fresh evidence.
