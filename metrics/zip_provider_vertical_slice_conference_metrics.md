# Conference Metrics: zip_provider_vertical_slice

Date: 2026-07-12

| Role | Provider | Model | Status | Duration / calls | Tokens | Result |
|---|---|---|---|---|---:|---|
| Chinese UX original | aishuo | MiniMax-M3 | Excluded | three rounds | not relied on | Read beyond allowlist and polluted output |
| Chinese UX bounded rerun | aishuo | MiniMax-M3 | Incorporated | 3 API calls | 90,227 total | No Chinese UX blocker; integrity belongs under `操作` |
| Architecture | aishuo | glm-5.2 | Incorporated with corrections | 18.386 s | unavailable in runner log | Several false positives; retained fingerprint and stress-test advice |
| Security | Reasonix CLI | deepseek-pro | Incorporated with corrections | 9 steps | 372,957 prompt; 17,759 completion | Four concrete hardening changes accepted; CRC finding rejected |
| Buddy GLM fallback | buddy | glm-5.2 | Not needed | — | — | Primary aishuo GLM completed |
| Visual advisory | aishuo / buddy | Gemini-3.5-Flash / kimi-k2.7-code | Not run | — | — | No current provider-state screenshot available |

## Timeout And Retry Evidence

- No model was failed for latency.
- MiniMax was rerun for boundary compliance, not provider failure. Rerun session: `20260712_040824_4c655b`.
- aishuo GLM session: `20260712_035503_25a05d`.
- Reasonix completed normally; its metrics are in `metrics/reasonix_zip_provider_security.json`.

## Verification Evidence

- `/tmp/zip-provider-post-review-swift-test.log`: SHA-256 `b6a21c0891ac3752da52b3e75478ad6e5425e8abbf457a6924e03a7828e6de12`.
- `/tmp/zip-provider-cbridge-regression.log`: SHA-256 `90fe0f4c674f5e40aafadd8763915934b087fd0f0479a27adf26968a6b01ec30`.
- `/tmp/zip-provider-post-review-xcode-unit.log`: SHA-256 `b222e09abc24cf823e12fed41e6cc15f1f4bba720693600dd5978c0ba20e30e2`.
- `/tmp/zip-provider-root-category-xcode-test.log`: SHA-256 `a107cb90347998ea3d401b0a525b4c7aee5774f059c121db64d8d6c438699e21`.
- `/tmp/zip-provider-real-ui-retry.log`: SHA-256 `092bceb9e6f79851435106161a0abb566293f719878344fe7b18cdbb5fdedf50`; failed before UI assertions at app activation (`Running Background`).

## Quality Decision

Non-visual ZIP provider milestone accepted. Rendered UI acceptance, physical-Windows testing, remaining archive workflows, previews, other formats, RAR, and distribution remain open.
