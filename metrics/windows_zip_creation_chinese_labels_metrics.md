# Metrics: windows_zip_creation_chinese_labels

Date: 2026-07-13

| Field | Value |
|---|---|
| Task type | `chinese_label_sentence_review` |
| Risk | `medium` |
| Selected provider | `buddy` |
| Selected model | `deepseek-v4-pro` |
| Selected effort | `high` |
| Duration | 3m 29s |
| API calls | 1 Hermes session; 14 messages total, provider call count not exposed |
| Artifact size | 14 KB review + 426 KB captured stdout |
| Result | Pass after Codex correction and RED-GREEN verification |

## Verification Burden

Two source-facing contracts were verified: visible creation-panel copy and public AppModel error output. Rendered visual quality, String Catalog coverage, and Windows-native physical acceptance are tracked by later gates and were not inferred from this review.

## Routing Decision

The current `chinese_label_sentence_review` rule selects Hermes buddy / deepseek-v4-pro as a single gate with no conference. Codex rejected the one recommendation that misstated the verification/publish order and retained final authority.
