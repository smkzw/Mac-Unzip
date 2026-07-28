# 归档工作台 QC-4 设计门禁综合判定

日期：2026-07-11  
Codex 主会场判定：**规格 GO；视觉目标 v3 待最后像素复核；可进入实施计划，不得提前宣称实现通过。**

## 独立审查结果

| 路由 | 实际模型证据 | 结论 | Codex 处置 |
|---|---|---|---|
| aishuo / MiniMax-M3 | 输出自报完整读取 3 个允许文件和 SOUL；模型标识与请求一致 | GO，既有 16 项产品/中文/工作流阻断均关闭 | 接受；P2 放入实施计划/String Catalog QC |
| aishuo / GLM-5.2 | 输出自报 aishuo 主路由、完整读取 3 个允许文件和 SOUL | GO，14 个技术维度无 P0/P1 | 接受；7 项 plan-time 风险必须落到任务/测试 |
| Reasonix / deepseek-pro | metrics 与 stdout 显示 `deepseek-pro`，非 Hermes/直接 DeepSeek | 条件性 GO；最初仅留 1 个密码跨进程 P1 | Codex 修订 §18 后执行 QC-4B |
| Reasonix / deepseek-pro QC-4B | 读取当前规格与自身 QC-4 输出 | `P1 CLOSED`，GO | 接受，规格安全阻断归零 |

Hermes 退出时出现的 event-loop/MCP 清理警告发生在目标文件成功写入之后，不改变模型输出完整性；保留为工具链噪声，不隐藏。

## Codex 逐项关闭

- 解压/预览炸弹阈值与不可覆盖边界：关闭。
- 7zz stdout 非安全权威、隔离暂存、fd-rooted 验证：关闭。
- RARLAB 签名/身份、双引擎结果验证和安全禁用：设计关闭，真实 signer/二进制仍是实施 spike。
- 钥匙串跨重命名/移动/复制/编辑关联：关闭。
- 单文件 TOCTOU、恢复 HMAC、分卷快照、helper/扩展边界：关闭。
- 密码传递：当前 §18 明确仅允许独占不可继承 stdin/PTY，禁止 argv/env/file/clipboard/shell；QC-4B 关闭。
- 转换、图标视图、RAR 修复等未完成入口：v1 明确不显示。
- 中文术语：MiniMax QC-4 通过；实现时仍必须进入 String Catalog 并用真实界面复核。

## 视觉门禁

v1 合并图被可靠 Gemini 路由判为 NO-GO；v2 已删除双侧栏、分页占位、日期历史、重复解压和文档态创建按钮。Codex 原始分辨率检查确认方向正确。Gemini 对 v2 只剩两项 P1：预览内联缩放条、检查器内部 `<<`；v3 将移除二者，并把窄窗口工具收纳到系统 overflow。Buddy 请求 `kimi-k2.7-code` 实际返回 `kimi-k2.7`，作为路线失败记录，不冒充指定模型通过。

## 实施前/实施中硬证据

1. 完整 Xcode 26.6 安装与 `xcodebuild -version`；当前 App Store 安装需要本机管理员认证。
2. App Sandbox + bookmark + bundled 7zz + external RARLAB + DMG spike。
3. RARLAB 官方二进制签名/Team ID 实测；不符合即保持 RAR 创建禁用。
4. Windows 11 24H2 Explorer、当前 7-Zip、当前 WinRAR 物理矩阵。
5. v3 视觉目标与真实运行截图同 viewport 对照。
6. 每里程碑自动测试、模型 QC 和 Codex 实机验收。

## LOOP 记录

- Objective：证明修订规格可安全转入实现计划。
- Observation：MiniMax/GLM 为 GO；Reasonix 唯一 P1 被修订并在 QC-4B 关闭；视觉结构已从 v1 到 v2 显著收敛。
- Evaluation：规格 P0/P1 为 0；视觉仍需一轮细节图，不影响非 UI 实施计划编写。
- Decision：开始分子系统实施计划；UI 代码以 v3 复核为门槛；完整 Xcode 为可执行构建门槛。
