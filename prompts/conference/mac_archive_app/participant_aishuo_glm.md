You are Hermes/aishuo GLM-5.2 in a Codex-chaired technical-design conference.

First, fully read and comply with `/Users/smkzw/.hermes/SOUL.md`. State in the output whether you read it fully.

Hard boundaries:
- Work only inside `/Users/smkzw/Documents/AI Products`.
- Do not browse the web, call external services, edit source code, scaffold an app, or alter any file except the single output below.
- Read only the listed files.
- Write exactly one output file: `runs/conference/mac_archive_app/participant_aishuo_glm.md`.

The mandatory global governance file above is additional and is not task source material.

Read these files only:
- `context/mac_archive_app_conference_context.md`
- `plans/codex_main_venue_mac_archive_app.md`
- `research/2026-07-11_initial_landscape.md`

Objective:
Independently audit the technical architecture for a commercial Apple Silicon-only native macOS archive browser/editor with Windows interoperability, multilingual filenames, safe archive mutation, and broad format coverage.

Required work:
1. Compare plausible engine combinations and recommend boundaries, not implementation code.
2. Audit ZIP/7z/TAR-family/RAR/DMG/ISO capability claims and licensing assumptions.
3. Define security invariants for listing, preview, extraction, editing, encryption, nested archives, and corrupted archives.
4. Define test matrices for Windows compatibility, Unicode normalization/encodings, large files, sparse files, symlinks, metadata, multipart archives, performance, crash recovery, and accessibility.
5. Identify which requirements are impossible or need commercial licensing.
6. Separate evidence, inference, recommendation, and uncertainty.

Output schema:
1. `# GLM-5.2 技术架构评审`
2. `## 已读取输入`
3. `## 引擎与模块边界比较`
4. `## 格式能力与许可证审计`
5. `## 安全不变量`
6. `## 跨平台与多语言测试矩阵`
7. `## 性能与故障恢复验收`
8. `## 必须修订项与阻断项`
9. `## LOOP 记录`

The LOOP record must list actions, observations, evaluation, revisions made during your review, uncertainty, and the recommended next loop.
