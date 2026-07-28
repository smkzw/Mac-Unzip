# Codex Main-Venue Plan: zip_extraction_vertical_slice

Date: 2026-07-12
Objective: 设计并审查 ArchiveWorkbench 的真实安全流式 ZIP 全量解压切片，覆盖目标目录事务、路径与链接安全、资源预算、空目录、文件冲突、取消、进度、失败清理及用户可验证结果

## Task Decomposition

1. RED: define real provider/security tests for streaming bytes and directory preservation.
2. GREEN: implement descriptor-owned output and chunked minizip read with cancellation/progress.
3. RED/GREEN: add destination transaction with aggregate budget, cleanup, and conflict-free final folder.
4. RED/GREEN: bind native directory picker, progress/cancel state, completion feedback, and Finder reveal.
5. Run participant/chair review, full automated regression, real ZIP E2E, visual acceptance, and Release verification.

## Source Packet

- Current provider, security materializer/path/budget types, provider/security tests.
- Loader/model/toolbar binding and UI tests.
- Conference context success criteria and explicit user requirements.

## Participant Assignments

| Role | Provider | Model | Output |
|---|---|---|---|
| `general_aishuo_minimax` | `aishuo` | `MiniMax-M3` | `runs/conference/zip_extraction_vertical_slice/general_aishuo_minimax.md` |
| `general_buddy_deepseek` | `buddy` | `deepseek-v4-pro` | `runs/conference/zip_extraction_vertical_slice/general_buddy_deepseek.md` |
| `general_opencode_mimo` | `opencode-go` | `mimo-v2.5` | `runs/conference/zip_extraction_vertical_slice/general_opencode_mimo.md` |

## Sub-Venue Review

| Role | Provider | Model | Output |
|---|---|---|---|
| `general_chair_glm` | `buddy` | `glm-5.2` | `runs/conference/zip_extraction_vertical_slice/general_chair_glm.md` |

## Main-Venue Review

- Codex performs the final synthesis and acceptance.
- This conference mode has no Reasonix second-review role.

## Timeout And Retry Tracking

Participants launched in parallel after prompt preflight and all completed three rounds in the same session. No provider timeout, rate-limit fallback, or replacement session was used. DeepSeek encountered two non-terminal reads against a wrong guessed package path; the session continued and corrected its output. Session evidence and measured totals are recorded in `metrics/zip_extraction_vertical_slice_conference_metrics.md`.

## Codex Verification Checklist

- [x] Every new API first observed failing in a focused test.
- [x] No per-entry full-memory buffering in extraction path.
- [x] Aggregate budget, path/link rejection, empty directories, collision policy, cancellation, and cleanup are directly tested.
- [x] Real UI extraction previously opened a test-selected destination, published exactly one complete folder, and exposed Finder reveal; current-source rerun is pending the macOS UI Automation authorization gate.
- [ ] Package, unit, UI, accessibility, Release arm64, and signing gates pass. Package 28 XCTest + 34 Swift Testing, App unit 29, Release arm64 and signing are green; current UI/accessibility full suite is blocked before test execution by the system authorization dialog.
