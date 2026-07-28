# Codex Main-Venue Plan: preview_visual_acceptance

Date: 2026-07-12
Objective: 审查 ArchiveWorkbench 默认和最小宽度真实窗口截图，聚焦工具栏重叠、标题溢出、省略号歧义、Finder 式预览布局与中文视觉层级；仅输出审查建议，不编辑源码

## Task Decomposition

1. Capture real app-window screenshots at default and enforced 900 pt minimum widths.
2. Review title overflow, toolbar overlap, ambiguous overflow controls, Chinese hierarchy, and Finder-like layout.
3. Compare independent participant reports with Codex original-resolution inspection and UI frame assertions.

## Source Packet

- `toolbar-default.png` and `toolbar-minimum.png` XCTest window attachments.
- DocumentToolbar, MediaPreviewView, and DocumentShellTests source.

## Participant Assignments

| Role | Provider | Model | Output |
|---|---|---|---|
| `visual_aishuo_minimax` | `aishuo` | `MiniMax-M3` | `runs/conference/preview_visual_acceptance/visual_aishuo_minimax.md` |
| `visual_buddy_kimi` | `buddy` | `kimi-k2.7-code` | `runs/conference/preview_visual_acceptance/visual_buddy_kimi.md` |
| `visual_opencode_qwen` | `opencode-go` | `qwen3.7-plus` | `runs/conference/preview_visual_acceptance/visual_opencode_qwen.md` |

## Sub-Venue Review

- No sub-venue chair. Codex leads the visual/design panel directly.

## Main-Venue Review

- Codex performs the final synthesis and acceptance.
- This conference mode has no Reasonix second-review role.

## Timeout And Retry Tracking

- Qwen completed three rounds on the first run.
- MiniMax completed after a slow vision path; its image interpretation contradicted the visible screenshot and was rejected.
- Kimi timed out after the 30-minute hard wait before a resumable session existed; one controlled same-route retry completed three rounds. Its final report was source-inference only.

## Codex Verification Checklist

- [x] Codex inspected both original-resolution window screenshots.
- [x] No title badge/rounded container remains.
- [x] No toolbar overlap at default or 900 pt minimum width.
- [x] No ambiguous ellipsis or unlabeled far-right control.
- [x] Title uses single-line middle truncation and preserves the extension.
- [x] “检测完整性” is absent from the primary toolbar and present only in “操作”.
- [x] UI frame/order/accessibility tests passed; real extraction later exposed and fixed the custom toolbar hit target.
