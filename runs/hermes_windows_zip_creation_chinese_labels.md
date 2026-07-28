# Hermes Chinese Label Review: windows_zip_creation_chinese_labels

Audit date: 2026-07-13
Sources: `RootWindowView.swift`, `AppModel.swift`, `design/2026-07-11_full_design_spec.md` §7/§5.3/§13
Scope: buttons, panel labels, explanatory text, compatibility statement, progress/cancel/completion text, and creation-specific error messages added for the Windows ZIP slice. Excludes pre-existing labels (open, extract, etc.).

---

## Boundary Check

- Workspace: `/Users/smkzw/Documents/AI Products/.worktrees/foundation` — all reads within this root.
- Files read: exactly the four listed in the task prompt. No production paths, no unlisted files.
- No edits to source files; no web, browser, test, or visual operations performed.
- Output file: `runs/hermes_windows_zip_creation_chinese_labels.md` (this file).
- All claims are sourced to specific file:line references. No claims beyond the four read files.

---

## Must-Change Table

| # | File:Line | Current | Proposed | Severity | Rationale |
|---|---|---|---|---|---|
| 1 | `RootWindowView.swift:469` | `创建完成前会重新打开并核对全部文件。` | `创建完成后将重新打开并核对全部文件。` | **must** | **动作/结果时序混淆**。"创建完成前"在中文中自然解读为"在创建动作完成之前"，暗示校验与创建并行或提前发生；但实际流程是：写入ZIP → 重新打开核对 → 报告完成。从用户视角看，进度条走完、文件已写出，此时"重新打开"发生在创建之后，而非之前。改用"创建完成后"可以准确表达"全部写完后还会再检查一遍"的保障语义；与设计规格§13.4（`创建成功不只看进程退出码：重新打开、检测完整性、核对条目清单`）一致。 |
| 2 | `AppModel.swift:554` | `"\(name)"无法在 Windows 中安全使用，请重命名后再试。` | `"\(name)" 不符合 Windows 文件名规则，请重命名后再试。` | **must** | **硬翻译 / "安全"词义漂移**。"安全使用"对应英文 "safely used"，但文件名在中文里不是被"使用"的对象，而是"有效/合规"的问题。"安全"在此上下文中容易让用户误读为安全风险（恶意文件），实际含义是兼容性/合法性。设计规格§13.1 定义的是"Windows 保留名、非法字符"检查，改用"不符合...文件名规则"直接对应检查实质。 |
| 3 | `AppModel.swift:558` | `"\(name)"不是可安全归档的普通文件或文件夹。` | `"\(name)" 是特殊文件类型，无法归档。` | **must** | **硬翻译 / "可安全归档"不自然**。"可安全归档"直译 "safely archivable"，中文中文件不是"安全归档"的——它是普通文件/文件夹就可以归档，是符号链接/设备文件/套接字就不能归档。当前措辞不仅生硬，还模糊了拒绝原因（不是普通文件）。改用"特殊文件类型，无法归档"直截了当，与错误码 `unsupportedItem` 语义对齐。 |
| 4 | `AppModel.swift:566` | `创建后的校验未通过，未发布压缩包。` | `创建后的校验未通过，未生成压缩包。` | **must** | **动作夸大 / "发布"用词不当**。"发布"(publish)在软件语境中指向分发、上线、推送，这里是本地文件创建，校验失败后并没有走到"发布"阶段。同一文件中其他错误消息统一使用"未生成"（如 line 562 `未生成压缩包`、line 568 `未生成任何文件`），此处的"发布"破坏了消息体系的一致性。改用"未保存压缩包"或"未生成压缩包"均可；推荐"未生成"以保持与同类消息一致。 |
| 5 | `RootWindowView.swift:352` | `创建可直接发给 Windows 用户的 ZIP 压缩包` | `创建 Windows 用户可直接打开的 ZIP 压缩包` | **must** | **语义重心偏移 / "直接"修饰错误动词**。当前"直接"修饰"发给"（发送），核心价值主张变成了"不需要中间转换就可以发送"，而产品真正的差异化价值是"Windows 端无需安装额外软件即可打开"——"直接"应修饰"打开"而非"发送"。设计规格§7 术语基线明确将核心兼容性声明定为 `Windows 11 可直接打开`，此处副标题应与之对齐。 |

---

## Optional Polish Table

| # | File:Line | Current | Proposed | Severity | Rationale |
|---|---|---|---|---|---|
| 1 | `RootWindowView.swift:98` | `创建可由 Windows 11 直接打开的 ZIP 压缩包` | `创建 Windows 11 可直接打开的 ZIP 压缩包` | optional | **被动句式略冗余**。"可由...打开的"被动结构在中文中不算错误，但比主动句式长且弱。Help tooltip 应精炼直接；设计规格§7 和 line 44 `compatibility` 字段均使用主动句式 `Windows 11 可直接打开`，tooltip 与之统一更好。当前版本可接受，不改不阻塞。 |
| 2 | `AppModel.swift:42` | `标准压缩` | 可维持，无需更改 | optional | **"标准"略模糊但可接受**。ZIP 上下文中"标准压缩"指向 Deflate（设计规格§13.1），属于 macOS 归档工具和 Finder"压缩"功能的惯用措辞。若未来有"无压缩(Store)"选项出现，再区分不迟。当前只有一种压缩方式，保持简洁即可。 |
| 3 | `RootWindowView.swift:233` | `创建前会检查 Windows 文件名兼容性。` | 可维持，无需更改 | optional | NSOpenPanel message 空间有限，"文件名兼容性"概括了保留名+非法字符+冲突检测，面板内部（line 414）有详细说明。不构成误导。 |
| 4 | `RootWindowView.swift:97` / `RootWindowView.swift:475` / `RootWindowView.swift:350` | `创建归档`（按钮/标题） | 可维持，无需更改 | optional | 与设计规格§7 术语基线完全一致。`归档`在 action/command 语境中使用，`压缩包`在 user-facing 指代产物时使用，分工清晰。 |
| 5 | `AppModel.swift:560` | `目标位置已存在同名压缩包，未覆盖原文件。` | 可维持，无需更改 | optional | 当前措辞信息完整：告知冲突（同名）+ 告知保护动作（未覆盖）。"原文件"指已存在的压缩包，不会与待归档的源文件混淆。 |

---

## Strings To Keep

以下字符串自然、准确、与设计规格术语基线一致，无需修改：

**按钮与操作标签**
- `"创建归档"` — `RootWindowView.swift:97,350,475`。与设计规格§7 一致。
- `"取消"` — `RootWindowView.swift:463,473`。标准 macOS 中文。
- `"选择…"` — `RootWindowView.swift:437`。标准 macOS 省略号按钮。

**面板与面板消息**
- `"选择要归档的项目"` — `RootWindowView.swift:231`。NSOpenPanel title，准确描述操作。
- `"继续"` — `RootWindowView.swift:232`。标准 prompt 按钮。
- `"保存压缩包"` — `RootWindowView.swift:244`。NSSavePanel title。
- `"选择"` — `RootWindowView.swift:245`。标准 prompt 按钮。
- `"选择保存位置和文件名；已有文件不会被静默覆盖。"` — `RootWindowView.swift:246`。信息完整，中文标点正确。
- `"可以选择多个文件和文件夹；创建前会检查 Windows 文件名兼容性。"` — `RootWindowView.swift:233`。面板级摘要，OK。

**面板区域标签**
- `"待归档项目 · N 项"` — `RootWindowView.swift:360`。GroupBox 标签，格式符合 macOS 中文习惯。
- `"创建设置"` — `RootWindowView.swift:384`。简洁明确。
- `"用途"` / `"格式"` / `"压缩方式"` / `"加密"` — `RootWindowView.swift:386-389`。settingRow 标签，标准术语。
- `"保存位置"` — `RootWindowView.swift:427`。标准 GroupBox 标签。
- `"尚未选择"` — `RootWindowView.swift:432`。标准 placeholder。

**兼容性声明**
- `"使用 UTF-8 文件名，自动排除 macOS 元数据；创建前检查 Windows 保留名、非法字符和名称冲突。"` — `RootWindowView.swift:414`。技术描述精确，与设计规格§13.1 的 W0 合同（UTF-8 + bit 11 + 排除 .DS_Store/._* /__MACOSX + 全树预检）完全对齐。

**预设值**
- `"发给 Windows 用户"` — `AppModel.swift:40`。与设计规格§5.3 和§13.1 的用途预设一致。
- `"不加密"` — `AppModel.swift:43`。明确。
- `"Windows 11 可直接打开"` — `AppModel.swift:44`。与设计规格§7 术语基线一字不差。

**进度与状态消息**
- `"正在准备创建归档…"` — `AppModel.swift:264`。自然。
- `"正在创建 · N/M 项"` — `AppModel.swift:281`。含计数，清晰。
- `"创建完成：name"` — `AppModel.swift:298`。含产物标识，可用。
- `"创建完成"` — `AppModel.swift:299`。简洁。
- `"已取消创建归档"` — `AppModel.swift:304`。状态明确。
- `"创建失败"` — `AppModel.swift:311`。状态明确。

**错误消息（已审无问题）**
- `"没有可归档的文件。"` — `AppModel.swift:552`。直接。
- `""X" 与 "Y" 在 Windows 中会发生名称冲突。"` — `AppModel.swift:556`。信息完整，中文标点正确。
- `"目标位置已存在同名压缩包，未覆盖原文件。"` — `AppModel.swift:560`。明确告知保护动作。
- `"无法写入目标位置，未生成压缩包。"` — `AppModel.swift:562`。原因+后果，完整。
- `"无法创建压缩包，未生成任何文件。"` — `AppModel.swift:568`。通用 fallback，格式与同类消息一致。

**弹窗标题**
- `"无法创建压缩包"` — `RootWindowView.swift:140`。与 `"无法打开压缩包"`(line 118)、`"无法解压缩"`(line 129) 形成统一的错误弹窗标题模式。

---

## Consistency And Overclaim Audit

### 术语一致性：通过

设计规格§7 规定了四项关键术语，全部落实：

| 概念 | 规格要求 | 实际使用 | 文件:行 |
|---|---|---|---|
| archive noun (user-facing) | `压缩包` | `压缩包` | `RootWindowView.swift:140`, `AppModel.swift:560,562,566,568` |
| create archive | `创建归档` | `创建归档` | `RootWindowView.swift:97,350,475` |
| Windows native | `Windows 11 可直接打开` | `Windows 11 可直接打开` | `AppModel.swift:44` |
| archive noun (system/format context) | `归档` | `归档` | `AppModel.swift:264,304`, `RootWindowView.swift:360` |

### "Windows 11" vs "Windows" 使用：合理，非问题

- 兼容性**声明**使用 `Windows 11`（`AppModel.swift:44`、`RootWindowView.swift:98`）：因为物理验收目标为 Windows 11 24H2 Explorer（设计规格§19）。这是有验证支撑的承诺，用具体版本号是审慎的。
- 兼容性**检查/错误**使用 `Windows`（`RootWindowView.swift:233,414`、`AppModel.swift:554,556`）：因为文件名保留字、非法字符、大小写冲突规则在 Windows 全系中一致，用泛指"Windows"更准确。若在检查逻辑中说"Windows 11"反而暗示 Windows 10 下可能有不同行为，引入不必要的不确定性。

### "直接" 语义归属：已列入 must-change #5

工具提示 line 98 和副标题 line 352 的核心问题是"直接"修饰了"发送"而非"打开"。must-change #5 修正了 line 352；line 98 的工具提示作为可选润色单独列出。设计规格§7 明确核心兼容性声明的主体是"Windows 可直接打开"，"发给 Windows 用户"是用途预设名，两者分工清晰：用途回答"为什么创建"，兼容性回答"对方能否打开"。副标题混合两者时应保持语义重心在兼容性上。

### "发布" vs "生成/保存"：已列入 must-change #4

`AppModel.swift:566` 的"未发布压缩包"是唯一使用"发布"的位置；同类消息（line 552, 560, 562, 568）均使用"生成"或"覆盖"等本地文件操作术语。设计规格未定义"发布"作为创建流程的术语（§7 和§13 均无此词），此处为孤立措辞，应统一。

### Windows 兼容性承诺范围：适度，无过度承诺

- line 98 tooltip: "创建可由 Windows 11 直接打开的 ZIP 压缩包" — 按钮关联的默认预设确实产生符合 W0 合同的 ZIP（设计规格§13.1）。tooltip 描述的是 feature intent，不是无条件的输出保证。面板内部会显示真实的兼容性预检结果。
- line 44 compatibility: "Windows 11 可直接打开" — 仅对"发给 Windows 用户"预设显示；分卷/加密等偏离预设会触发设计规格§13.2 的降级提示。
- line 414 description: 描述了实际执行的检查项，与技术实现一致。

### macOS 术语对齐：通过

- 未使用"偏好设置"（旧称），未出现相关字符串，无需修正。
- "钥匙串"未在创建流程中出现，无需修正。

### 中文标点：通过

- 面板消息中的分号使用全角 `；`（`RootWindowView.swift:233,246,414`），符合中文排版规范。
- 省略号使用 `…`（`RootWindowView.swift:437`），符合 macOS 中文界面惯例。

### 可访问性标签

- `accessibilityIdentifier: "Windows 兼容性摘要"`（`RootWindowView.swift:424`）：非用户可见文本，仅用于 VoiceOver 和 UI 测试。作为 VoiceOver 标签准确描述了兼容性区域的语义。无需更改。

---

## Codex Verification Notes

1. **交付物**：本文件即为唯一输出 `runs/hermes_windows_zip_creation_chinese_labels.md`。未写入任何源文件。

2. **已识别未解决问题**：无。所有 must-change 项均有具体 proposed wording 和 rationale。

3. **不可验证项**（需 Codex 接手）：
   - 本审查不涉及视觉渲染、布局或截图的验证。
   - 未检查 `String Catalog` 配置或 `.xcstrings` 文件——任务限定为源文件中的硬编码中文字符串审查。如存在 String Catalog，Codex 需独立核对源文件字符串与 Catalog 条目的一致性。
   - 未验证 `AppModel.swift:548-569` 的 `creationMessage(for:)` 是否在运行时被正确路由到——这是代码逻辑问题，不属于文案审查范围。

4. **推荐下一步**：
   - Codex 确认 must-change 项后，授权编辑轮次。
   - 同步更新 String Catalog（如有），为每个条目补充使用场景注释（设计规格§7 末尾要求）。
   - 创建面板的 `accessibilityIdentifier` 值（如 `"创建归档面板"`、`"确认创建归档"`、`"选择保存位置"`）与可见文本的一致性可做一轮快速交叉核对（本次未列入 scope）。

5. **Session 归档**：本任务为 Codex 分派的临时审查会话。输出已自包含，Codex 可从本文件恢复状态。Hermes Desktop session 可在 Codex 验证输出后归档。
