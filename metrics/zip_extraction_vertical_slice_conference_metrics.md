# Conference Metrics: zip_extraction_vertical_slice

Date: 2026-07-12 (verification refreshed 2026-07-13)

| Role | Provider | Model | Status | Duration | API calls | Tokens | Result |
|---|---|---|---|---:|---:|---:|---|
| `general_aishuo_minimax` | `aishuo` | `MiniMax-M3` | completed, 3 rounds | 2m 26s | 7 | 511,354 | accepted with source corrections |
| `general_buddy_deepseek` | `buddy` | `deepseek-v4-pro` | completed, 3 rounds | 11m 57s | 14 | 1,155,646 | accepted with two read-path errors excluded |
| `general_opencode_mimo` | `opencode-go` | `mimo-v2.5` | completed, 3 rounds | 3m 42s | 10 | 800,742 | accepted with staging recommendation refined |
| `general_chair_glm` | `buddy` | `glm-5.2` | completed, 3 rounds | 4m 19s | 9 | 660,904 | synthesis accepted in part; stale source claims rejected |

## Timeout And Retry Evidence

Durations are measured from the first session log event to final cleanup. API calls and tokens are summed from `/Users/smkzw/.hermes/logs/agent.log`; token totals are provider-reported input plus output across calls and therefore include repeated context/cache traffic rather than unique semantic tokens. All four roles continued rounds 2 and 3 in the original session IDs. No timeout, provider exhaustion, rate-limit fallback, or replacement session occurred. DeepSeek produced two non-terminal `Path not found` tool warnings for a guessed package path and recovered in the same session.

## Quality Decision

Conference routing and three-round continuity passed. Backend recommendations were accepted only where current source/tests confirmed them. The overall vertical-slice gate remains `revise` solely because the fresh UI/accessibility run is stopped by a visible macOS UI Automation credential prompt before test execution; package, unit, Release architecture and signing gates pass.
