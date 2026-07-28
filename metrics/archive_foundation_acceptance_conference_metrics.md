# Conference Metrics: archive_foundation_acceptance

Date: 2026-07-12

| Role | Provider | Model | Status | Duration | API calls | Tokens | Result |
|---|---|---|---|---:|---:|---:|---|
| terminology | aishuo | MiniMax-M3 | passed | 204.399 s / 3 rounds | 21 | provider total not exposed; 2,006 reasoning | accepted with Codex edits |
| technical primary | aishuo | GLM-5.2 | terminal failure | three provider retries | unavailable | unavailable | HTTP 503, no channel |
| technical fallback | buddy | GLM-5.2 | terminal failure | 5.676 s | 1 | unavailable | unsupported model |
| security first pass | reasonix | deepseek-pro | invalidated | completed | 3 steps | not accepted | read-boundary violation after erroneous paths |
| security corrected | reasonix | deepseek-pro | passed with gates | completed | 3 steps | 117,192 prompt / 10,478 completion | corrected fixed-allowlist review |
| visual primary | aishuo | Gemini-3.5-Flash | terminal failure | 12.196 s | 3 provider retries | unavailable | HTTP 503, no channel |
| visual secondary | buddy | kimi-k2.7-code | invalidated | 1,800 s timeout + 407.615 s same-session retry | 15 | 2,593 reasoning | vision timed out; output-boundary violation |

## Timeout and retry evidence

Kimi was kept pending through the 20-minute soft window. Its first turn reached the runner's 1,800-second hard limit; the runner then exposed a bytes/string exception while formatting the timeout. One controlled same-session retry completed but disclosed repeated vision timeouts and wrote `/tmp/comparison.html` outside the authorized output. The file was removed and the review invalidated. Aishuo GLM and Gemini are terminal provider errors, not latency failures. Buddy GLM is a terminal unsupported-model response. No silent route substitution occurred.

The generic conference validator returned `ok=false` because it expects the stock qwen participant and rejects the task's governing Reasonix-only DeepSeek route/user-specific override. The concrete Codex review/metrics gate returned `ok=true` with no warnings; both outcomes are preserved.

## Quality decision

The available valid model evidence is sufficient only for foundation handoff because Codex independently proved the code and rendered surface. Unavailable/invalid routes are retained as explicit QC gaps and must be retried at later feature milestones when available.
