# Codex Main-Venue Plan: mac_archive_app

Date: 2026-07-11
Objective: 调研、设计、构建并多重验证原生 Apple Silicon macOS 压缩与压缩包内容查看编辑 App，确保 Windows 与多语言兼容并达到商业化可用状态

## Task Decomposition

1. Confirm scope and distribution constraints; keep RAR creation license-safe.
2. Collect current commercial, open-source, Apple platform, interoperability, security, and licensing evidence.
3. Run independent terminology/product/architecture critiques through required models.
4. Present 2–3 design routes and obtain user approval.
5. Write and self-review the design spec; obtain user approval again.
6. Create an implementation plan, provision full Xcode, then build in milestones.
7. Execute automated, Windows interoperability, security, performance, accessibility, and full visual workflow QC loops.

## Source Packet

- `context/mac_archive_app_conference_context.md`
- `research/2026-07-11_initial_landscape.md`
- User messages captured in the active goal.

## Participant Assignments

| Role | Provider | Model | Output |
|---|---|---|---|
| `participant_qwen_plus` | `opencode-go` | `qwen3.7-plus` | `runs/conference/mac_archive_app/participant_qwen_plus.md` |
| `participant_mimo` | `opencode-go` | `mimo-v2.5` | `runs/conference/mac_archive_app/participant_mimo.md` |
| `participant_ds_flash` | `reasonix-cli` | `deepseek-v4-flash` | `runs/conference/mac_archive_app/participant_ds_flash.md` |

## Hermes Sub-Venue Review

| Role | Provider | Model | Output |
|---|---|---|---|
| `hermes_lead` | `opencode-go` | `minimax-m3` | `runs/conference/mac_archive_app/hermes_lead.md` |

## Main-Venue DeepSeek Pro Review

- Agent/model: Reasonix CLI `deepseek-pro` alias for `deepseek-v4-pro`.
- Reasoning: maximum configured Reasonix effort. Verify stdout/metrics when possible.
- Forbidden: Hermes, OpenCode Go, Hermes custom providers, or direct DeepSeek provider `deepseek-v4-pro` for this main-venue high-risk review.
- Output: `runs/conference/mac_archive_app/main_deepseek_pro.md`

## Timeout And Retry Tracking

Record start/end time, pending/failed/incorporated status, retry reason, route identity from stdout, and whether late outputs were used in `metrics/mac_archive_app_conference_metrics.md`.

## Codex Verification Checklist

- Verify all current web and licensing claims against primary sources.
- Inspect shortlisted repositories at source level; do not accept README capability claims blindly.
- Verify model/provider identity in logs; do not silently substitute routes.
- Keep model output advisory; Codex owns architecture, code, runtime, visual, and release decisions.
- Do not begin project scaffolding before the written design is approved.
