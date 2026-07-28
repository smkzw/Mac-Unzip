# Codex Main-Venue Plan: preview_backend_acceptance

Date: 2026-07-12
Objective: 复核 ArchiveWorkbench 压缩包内图片、视频、PDF、Word、Excel、PowerPoint 真实物化与预览后端链路，重点检查取消、缓存生命周期、加密条目、资源上限、跨格式真实性和测试覆盖；仅审查不编辑源码

## Task Decomposition

1. Trace selection to archive entry materialization and validated cache URL.
2. Audit cancellation, cache cleanup, encryption, budgets, and six-format routing.
3. Challenge participant findings against current source and Apple SDK declarations.
4. Apply only findings reproduced by Codex, then rerun focused and full regression gates.

## Source Packet

- Context and main-venue plan.
- AppModel, ArchiveDocumentLoader, ZIPArchiveProvider, PreviewRouting, RoutedPreviewViews, MediaPreviewView.
- SecureFileMaterializer, ResourceBudget, unit/UI tests, six real fixtures, and Quick Look verification script.

## Participant Assignments

| Role | Provider | Model | Output |
|---|---|---|---|
| `general_aishuo_minimax` | `aishuo` | `MiniMax-M3` | `runs/conference/preview_backend_acceptance/general_aishuo_minimax.md` |
| `general_buddy_deepseek` | `buddy` | `deepseek-v4-pro` | `runs/conference/preview_backend_acceptance/general_buddy_deepseek.md` |
| `general_opencode_mimo` | `opencode-go` | `mimo-v2.5` | `runs/conference/preview_backend_acceptance/general_opencode_mimo.md` |

## Sub-Venue Review

| Role | Provider | Model | Output |
|---|---|---|---|
| `general_chair_glm` | `buddy` | `glm-5.2` | `runs/conference/preview_backend_acceptance/general_chair_glm.md` |

## Main-Venue Review

- Codex performs the final synthesis and acceptance.
- This conference mode has no Reasonix second-review role.

## Timeout And Retry Tracking

- All three participants and the GLM chair completed three rounds in one session each.
- No participant fallback or retry was required. Session IDs and continuation evidence are recorded in their run files.

## Codex Verification Checklist

- [x] Reproduced six-format real ZIP materialization and display.
- [x] Verified encrypted entries do not materialize.
- [x] Verified cancellation does not surface a false failure.
- [x] Fixed request-root deletion race and added 64 KiB decompression-loop cancellation checks.
- [x] Removed the only Quick Look force-unwrap and added a system-unavailable fallback.
- [x] Rejected unsupported claims: current macOS SDK exposes no `QLPreviewViewDelegate`; startup/termination cache cleanup already exists.
- [x] Passed 34 package tests, 22 app unit tests, 12 app UI tests, six-format Quick Look script, and Release build/signature checks.
