# Conference Metrics: preview_backend_acceptance

Date: 2026-07-12

| Role | Provider | Model | Status | Duration | API calls | Tokens | Result |
|---|---|---|---|---:|---:|---:|---|
| `general_aishuo_minimax` | `aishuo` | `MiniMax-M3` | completed, 3 rounds | recorded in run log | not captured | not captured | race/unwrap findings reviewed |
| `general_buddy_deepseek` | `buddy` | `deepseek-v4-pro` | completed, 3 rounds | recorded in run log | not captured | not captured | security and Quick Look review |
| `general_opencode_mimo` | `opencode-go` | `mimo-v2.5` | completed, 3 rounds | recorded in run log | not captured | not captured | cancellation and cache review |
| `general_chair_glm` | `buddy` | `glm-5.2` | completed, 3 rounds | recorded in run log | not captured | not captured | consolidated with two rejected claims |

## Timeout And Retry Evidence

No timeout, provider fallback, or controlled retry was needed. Each output records its same-session continuation ID.

## Quality Decision

Pass after Codex reproduced and fixed the cache race, cancellation granularity, and force-unwrap; unsupported model claims were rejected through SDK/source verification.
