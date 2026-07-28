# Conference Metrics: mac_archive_app

Date: 2026-07-11

| Role | Provider | Model | Status | Duration | API calls | Tokens | Result |
|---|---|---|---|---:|---:|---:|---|
| `participant_aishuo_minimax` | `aishuo` | `MiniMax-M3` | complete | 3m15s | 4 | final call 70,756 | output written; route verified in stdout |
| `participant_aishuo_glm` | `aishuo` | `glm-5.2` | complete | 3m23s | 4 | final call 68,935 | output written; route verified in stdout |
| `participant_reasonix_deepseek_pro_research` | `reasonix-cli` | `deepseek-v4-pro` | complete | 4m40s | 6 visible steps | final visible context 33,608 | output written; route fixed by CLI alias |
| `hermes_lead` | `aishuo` | `MiniMax-M3` | complete | 4m29s | 18 | final call 100,783 | chair package written; actual route verified in stdout |
| `main_deepseek_pro` | `reasonix-cli` | `deepseek-v4-pro` | pending | — | — | — | final design-stage review after chair package |

## Timeout And Retry Evidence

All three participant routes and the chair completed inside the 20-minute soft wait. Hermes emitted non-fatal asyncio cleanup warnings after writing its files; all Hermes processes still returned exit code 0. No route was silently substituted and no retry was required. The chair's own narrative mislabeled itself as OpenCode Go, but stdout proves the actual provider/model was aishuo/MiniMax-M3; Codex records stdout as authoritative.

## Quality Decision

Participant completion does not equal acceptance. Codex source checks found material factual errors, recorded in `reviews/codex_conference_mac_archive_app_review.md`; a chair comparison and user decision on distribution remain required.

## Architecture QC-2 route status

| Route | Status | Evidence |
|---|---|---|
| aishuo / MiniMax-M3 | output complete; boundary gate failed | Wrote `qc_architecture_minimax.md` but self-reported reading one unlisted prior-review file |
| aishuo / GLM-5.2 | failed | Three API retries plus five stale-response checks ended with no output; terminal failure text overrides process exit 0 |
| buddy / GLM-5.2 | complete | Wrote `qc_architecture_buddy_glm.md`; 7 API calls; route metrics record model `glm-5.2`, provider `custom`, and completed=true |
| Reasonix / deepseek-pro | complete | Wrote `qc_architecture_reasonix_deepseek_pro.md`; route and model verified |

The first QC-2 attempt was deliberately interrupted when the user changed the installation/distribution scope. Its partial metrics are retained and must not be counted as a model failure or accepted review. The second attempt is authoritative for the current scope.

Codex synthesis and adjudication are recorded in `reviews/2026-07-11_architecture_qc2_synthesis.md`. The revised design closes the shared architecture blockers but still awaits user approval before a full design specification or implementation work begins.

## Full-spec QC-3/QC-4 route status

| Route | QC-3 | QC-4 | Final gate |
|---|---|---|---|
| aishuo / MiniMax-M3 | NO-GO; product/Chinese contradictions found | GO; 16 blockers verified closed | accepted for plan |
| aishuo / GLM-5.2 | NO-GO; 7 technical blockers found | GO; 14 required dimensions closed | accepted for plan |
| Reasonix / deepseek-pro | NO-GO; 5 security P0 found | conditional GO; one password-transport P1 | QC-4B `P1 CLOSED`, GO |
| aishuo / Gemini-3.5-Flash visual | first Hermes image route failed; direct verified v1 NO-GO | v2 image route verified; two visual P1 remain | v3 pending |
| buddy / Kimi-K2.7-Code visual | Hermes image route failed | direct request returned `kimi-k2.7`, not requested model | route failure; observations non-authoritative |

Reasonix usage evidence is stored in `metrics/qc4_spec_reasonix_deepseek_pro.json` and `metrics/qc4b_password_reasonix.json`. Hermes QC-4 output files and session IDs are retained; post-write event-loop cleanup warnings are non-fatal but recorded.
