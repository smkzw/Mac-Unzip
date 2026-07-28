# Conference Metrics: preview_visual_acceptance

Date: 2026-07-12

| Role | Provider | Model | Status | Duration | API calls | Tokens | Result |
|---|---|---|---|---:|---:|---:|---|
| `visual_aishuo_minimax` | `aishuo` | `MiniMax-M3` | completed, 3 rounds | slow; recorded in run | not captured | not captured | source/pixel inference rejected where contradicted |
| `visual_buddy_kimi` | `buddy` | `kimi-k2.7-code` | completed on controlled retry, 3 rounds | first run timed out at 30 min | not captured | not captured | source-only fragility review |
| `visual_opencode_qwen` | `opencode-go` | `qwen3.7-plus` | completed, 3 rounds | recorded in run | not captured | not captured | screenshot PASS at both widths |

## Timeout And Retry Evidence

Kimi first run timed out after 1800 seconds and the runner exposed a bytes/string timeout-reporting bug. One controlled retry on the same provider/model completed with session `20260712_104909_d2c967`. No fallback route was used.

## Quality Decision

Pass. Codex original-resolution inspection and UI geometry tests overrode contradictory model inference.
