# Conference Metrics: windows_zip_creation_vertical_slice

Date: 2026-07-13

| Role | Provider | Model | Status | Duration | API calls | Tokens | Result |
|---|---|---|---|---:|---:|---:|---|
| `general_aishuo_minimax` | `aishuo` | `MiniMax-M3` | completed | 75.582 s | 3 rounds | not exposed | usable with corrections |
| `general_buddy_deepseek` | `buddy` | `deepseek-v4-pro` | completed | 293.638 s | 3 rounds | not exposed | usable with one false reserved-name claim rejected |
| `general_opencode_mimo` | `opencode-go` | `mimo-v2.5` | completed after round-2 CLI error | 301.943 s | 3 rounds | not exposed | final artifact usable with actor-executor claim rejected |
| `general_chair_glm` | `buddy` | `glm-5.2` | completed | 276.813 s | 3 rounds | not exposed | useful synthesis; bit-11 uncertainty corrected by Codex |

## Timeout And Retry Evidence

- All roles preserved one session ID across three rounds: `20260713_063400_963743`, `20260713_063400_bb0354`, `20260713_063400_5e0333`, and `20260713_063918_f1c6b3`.
- MiniMax, DeepSeek and GLM returned `0,0,0`; Mimo returned `0,1,0`. The Mimo round-2 CLI error still left a resumable session and round 3 completed in the same session, so no fallback was activated.
- No round timed out. CLI cleanup emitted non-terminal MCP/asyncio shutdown warnings after artifacts were written; these did not alter the designated outputs.

## Quality Decision

Conference routing and continuity passed. Artifact quality required Codex correction, and product acceptance remains `revise` because UI/visual, latest Release and physical Windows Explorer gates are missing.
