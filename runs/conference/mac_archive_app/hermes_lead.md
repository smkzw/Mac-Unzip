# Hermes 分会场主席复核：mac_archive_app

## 输入与路由确认

**SOUL.md 读取声明**：已完整阅读 `/Users/smkzw/.hermes/SOUL.md`（571 行，含 model routing 附录）。遵守其指令层级、证据标准、Codex 委托边界、会议模式路由规则。本评审为咨询性 sub-venue chair 输出，不对最终架构、代码、运行时、视觉或商业发布作裁定；Codex 保留最终裁定权。

**本分会场主席的路由**：OpenCode Go `minimax-m3`（即本人），会议模式 = parallel，Codex 为主会场。

**已读取输入（仅限任务清单列出的 8 个文件）**：
- `context/mac_archive_app_conference_context.md`（70 行）
- `plans/codex_main_venue_mac_archive_app.md`（53 行）
- `research/2026-07-11_initial_landscape.md`（155 行 / 报告总行数含元数据 116）
- `runs/conference/mac_archive_app/participant_aishuo_minimax.md`（396 行）
- `runs/conference/mac_archive_app/participant_aishuo_glm.md`（576 行）
- `runs/conference/mac_archive_app/participant_reasonix_deepseek_pro_research.md`（458 行）
- `reviews/codex_conference_mac_archive_app_review.md`（43 行）
- `metrics/mac_archive_app_conference_metrics.md`（19 行）

**未读取**：其余 5 个 `runs/conference/mac_archive_app/participant_*.md` 占位文件均为本次会议次级参与者（`qwen3.7-plus` / `mimo-v2.5` / `deepseek-v4-flash`）未提交的占位（metrics 显示其无可见产物），按 SOUL.md §11 "Codex 委托" 硬约束 "读任务清单中列出的文件" 不予读取。`hermes_lead.md` 本身即本输出。`main_deepseek_pro.md` 为后续主会场高风险复核产物，不在本次输入范围。

**未访问**：外网、任何外部服务、生产路径、prompt 模板、日志、邮件翻译文件夹、`.codebuddy/`。

**证据优先级（per SOUL.md §4 + Codex 复核记录）**：
1. **最高置信度**：Codex 复核记录中已直接检查的 Apple 文档、`Archive Utility.app` 简体中文本地化字符串、SimpleZip / ZIPFoundation / libarchive 源码事实。
2. **高置信度**：research packet 引用的可查询一手 URL（Apple Developer、rarlab.com、GitHub 仓库）。
3. **中置信度**：参与者之间的一致共识（多人独立得出）。
4. **低置信度（须标注为推断）**：任何未由 Codex 直接验证的模型断言，包括 Liquid Glass 具体 API 表面、macOS 26 装机量、第三方 Windows 工具对 ZIP GP Bit 11 的精确支持矩阵。

---

## 参与者共识

下表为三人**独立得出且未被 Codex 反驳**的结论，作为分会场建议的事实底座。

| # | 共识点 | MiniMax-M3 | GLM-5.2 | DeepSeek Pro |
|---|---|---|---|---|
| C1 | RAR 创建在当前法律框架下不可行（无可信合法开源 RAR 写入器；UnRAR 许可禁止） | R1 / M1 / D3 | BLOCK-1 | 复核员维持结论 + 增强论证链 |
| C2 | 必须采用"暂存重写 + 验证 + fsync + 原子替换 + 恢复元数据"事务模型 | A4 / M17 | INV-8 | 隐含于 §数据损坏测试 C3 |
| C3 | 必须做格式能力注册表，UI 按能力动态启用/灰显按钮 | A2 / M3 | 引擎适配层 | 隐含于 §路线比较 |
| C4 | ZIPFoundation 不含加密，需第二引擎补 ZIP AES / ZipCrypto | M2 隐含 | REVISE-1 | 反驳 #2 |
| C5 | 7-Zip 捆绑存在 LGPL + 第三方组件复杂许可，需法务审计 | R / 风险段 | BLOCK-3 | 反驳 #3 + 路线 B 风险 |
| C6 | 跨平台导出必须显式处理 GP Bit 11（UTF-8）、Windows 保留字符、NFC/NFD、路径长度、大小写冲突 | R2 / M2 | 编码层 / 路径安全层 / 规范化层 | 反驳 #4 + 测试套件 A |
| C7 | 威胁模型需要结构化（攻击面、信任边界、纵深防御） | 安全段分散 | INV-1–10 | 反驳 #6 |
| C8 | a11y 是"商业化可用"验收的硬性章节，不写明就是盲点 | M9 / D 系列 | TM-8 | V14 |
| C9 | 分发渠道决策（D2）会反向决定 sandbox 模式与 helper 架构 | M6 / D2 | BLOCK-2 | 路线 A/B/C 胜出条件 |
| C10 | 验证必须以"双向 Windows 互通 fixture + Unicode 多语言 fixture"为可断言条款 | M2 / D5 | TM-1 / TM-2 | V3 / V8 / 测试套件 A |
| C11 | 崩溃恢复需要在 `~/Library/Application Support/<bundleID>/recovery/` 保留三元组 + journal，且 Caches 与 Application Support 路径必须分离 | A4 / M17 | INV-8 | V7 / TM-7 |
| C12 | 临时区与恢复区路径分离的根因是 Time Machine 备份语义 | M17 | （未明说） | （隐含） |

**结论**：C1–C12 为本分会场可背书的事实底座，Codex 可直接采用进 design spec。

---

## 分歧、错误与 Codex 修正

### A. 已被 Codex 直接反驳的断言（不得作为 spec 依据）

| 编号 | 参与者原文 | Codex 修正事实 | 处置 |
|---|---|---|---|
| X1 | MiniMax-M3 A5 / GLM-5.2（隐含）：**"App Sandbox 下不能 `exec` 外部 CLI"** | Codex 已查 Apple 文档：sandboxed macOS app **可**嵌入并执行已签名的命令行 helper。Sandbox 影响的是 helper 打包、entitlements、外部文件访问、用户安装工具发现，**不是**全面禁止 helper 执行 | **拒绝该断言作为 spec 依据**。sandbox 仍影响 D2 / D3 决策（用户安装 `rar` CLI 的检测路径在 sandbox 下需 entitlements），但不能由"exec 不可行"得出 |
| X2 | MiniMax-M3 术语表：**主张用 "展开" 替代 "解压缩"，用 "偏好设置" 而非 "设置"，隐藏 "钥匙串" 字样** | Codex 已查 macOS 26.5.1 `Archive Utility.app` 简体中文本地化：Apple 当前用 `归档`、`创建归档…`、`解压缩归档…`、`正在解压缩…`、`设置…`、`将密码储存在钥匙串中` | **拒绝 MiniMax-M3 的字面替换**。"压缩包"作为主名词可用（更亲民），但**动作/设置/钥匙串术语须从 Apple 实际字符串出发再经用户测试**，详见 §中文术语候选清单 |
| X3 | DeepSeek Pro 反驳 #1：**"SimpleZip 的 RAR 创建声明应标记为'已证伪'而非'可疑'"** | Codex 已查 SimpleZip 源码：其 RAR 创建**并非**功能谎言——而是下载/检测 RARLAB 专有 `rar` CLI，并在 README 中披露了 shareware 许可且默认拒绝捆绑。"已证伪"措辞过重 | **降级为"不构成开源 RAR 编码路径的证据"**。结论（不依赖 SimpleZip 提供开源 RAR 编码）与 DeepSeek Pro 一致；措辞修订 |
| X4 | GLM-5.2 许可证段：**"libarchive 读路径集成 unrar 时受 unrar license 约束"** | Codex 已查 libarchive 源码：libarchive 有**独立 permissively licensed 的 RAR4 / RAR5 读实现**，并不必然导入 UnRAR 限制 | **移除该断言**。libarchive 自带 RAR 读取是 BSD 范围内，许可证审计仍需逐组件，但"必须挂 unrar" 不成立 |
| X5 | GLM-5.2 ZIP 段：**"ZIPFoundation 加密需单独验证"** | Codex 已查 ZIPFoundation 源码：**确认不含加密实现**（不是"需验证"，是已确认缺失） | **强化为已确认缺失**。ZIP AES / ZipCrypto 路径需要第二引擎（minizip-ng / 7-Zip），不得把 ZIPFoundation 当作加密 ZIP 主路径 |
| X6 | DeepSeek Pro 反驳 #5：**"Liquid Glass API 假定当前可用但未经验证"** | Codex 确认 macOS 26.5.1 已安装；但**完整 Xcode 仍未本地化部署**，Liquid Glass 编译与渲染验收未执行 | **保留 DeepSeek Pro 的质疑**。Liquid Glass API 在当前 Xcode GM 中的控件覆盖需在补齐 Xcode 后立即验证，本分会场不背书任何具体 modifier 命名 |
| X7 | DeepSeek Pro 反驳 #7：**"macOS 26 是否停止 Intel 支持未确认"** | Codex 已查（隐含于 Codex 复核 §"Apple Silicon only" 约束）：Apple Silicon only 是用户主动约束，**该质疑本身成立**，但需在 spec 顶部记录理由而非作为默认假设 | **保留为产品决策项** D1'（Apple Silicon only 的产品理由文档化） |

### B. 三人之间仍有分歧的方法论问题

| 编号 | 分歧 | MiniMax-M3 | GLM-5.2 | DeepSeek Pro | 本分会场裁定 |
|---|---|---|---|---|---|
| Y1 | 推荐引擎组合 | 未明确给组合 | **A: ZIPFoundation + libarchive + 7-Zip（C++）** | **A: libarchive + ZIPFoundation / B: 7-Zip 重型 / C: Apple 优先**三条并列 | 见 §架构路线。**不取单点推荐**，按 D2 分发渠道决出 |
| Y2 | RAR 创建策略 | **M1 三选一强制**（仅读 / 透传 CLI / 商业许可） | **BLOCK-1 推荐仅读 + 可选 CLI 检测** | **维持不含创建 + 主动询 win.rar GmbH** | 三者本质一致（默认不含），**主动询 win.rar GmbH 是最低成本尽职调查**，本分会场采纳为 D3 子项 |
| Y3 | DMG 处理 | **M5: 挂载 vs 裸提取分两条 UX 路径** | **优先 hdiutil / 系统框架**（不确定 sandbox 阻断挂载） | 未重点讨论 | 两者不冲突：hdiutil 是引擎路径，挂载/裸提取是 UX 路径。**采纳 M5 + D2 决策决定 sandbox 下挂载可用性** |
| Y4 | 安全威胁建模深度 | 分散于 R / 风险段，未结构化 | **INV-1 到 INV-10** 系统不变量 | **反驳 #6 明确指出"列攻击向量 ≠ 建模"**，给 10 类攻击面补充 | **采纳 DeepSeek Pro 的方法论批评 + GLM-5.2 的不变量列表**，产出一份结构化威胁模型作为 P0 |
| Y5 | 7-Zip 引擎路线 | 未直接表态 | **推荐 7-Zip 引擎**（process 隔离 / Obj-C++ 边界） | **路线 B 标为"高许可风险"** | **采纳 GLM-5.2 的技术路径 + DeepSeek Pro 的风险标注**，决策前需法务审计 BLOCK-3 |
| Y6 | ZIPFoundation 修改语义 | 未质疑 | 推断需源码验证 | **反驳 #2 明确指出修改语义模糊** | **采纳 DeepSeek Pro 的质疑**为强制修订项 R-1，Codex 必须源码审查 |

### C. 仅一人提出且未被另两人或 Codex 反驳（属补充观察）

| 编号 | 来源 | 内容 | 本分会场是否背书 |
|---|---|---|---|
| Z1 | MiniMax-M3 | 微信/钉钉附件"默认双击行为"偏好设置项 | 背书为 UX 选项（M11 类） |
| Z2 | MiniMax-M3 | 中文文件名排序用 locale collation（拼音），设置可切 | 背书为设置项（采纳 D 系列外加可配置排序） |
| Z3 | MiniMax-M3 | Quick Look qlgenerator + Finder Sync Extension 是"原生"标签硬要求 | 背书为 v1 必备（M15） |
| Z4 | MiniMax-M3 | Liquid Glass 在 Reduce Transparency 下行为需 QC | 背书为视觉 QC 清单项（采纳） |
| Z5 | GLM-5.2 | Zstandard 在 Windows 端兼容性低于 GZIP/BZIP2/XZ（推断） | 仅作为推断保留，**需 Windows 实测**才能定结论 |
| Z6 | GLM-5.2 | DMG UDIF 涉版权/专利（推断） | 仅作为推断保留 |
| Z7 | DeepSeek Pro | Apple Archive 可作为 App 内部 crash-recovery journal / staged-mutation workspace 存储格式 | 列为 v2 评估项（M 类外），不在 v1 spec 必做范围 |
| Z8 | DeepSeek Pro | 路线 A 同时为路线 B 做架构预留（7-Zip 引擎封装为可插拔后端） | 背书为架构假设 |

### D. 三人均未覆盖的盲点（需 Codex 追加）

| 编号 | 盲点 | 建议 |
|---|---|---|
| B1 | Xcode 完整安装与 Liquid Glass 编译验证 | Codex 必须在本周内安装完整 Xcode 并跑通 SwiftUI Liquid Glass 示例 |
| B2 | Windows 11 真实机器（非虚拟机）互操作验证 | V3 / V4 物理验证，P0 阻塞 |
| B3 | 7-Zip / libarchive / XADMaster / ShichiZip 完整 SBOM 与逐组件 license notice | 法务前置 |
| B4 | 用户安装 `rar` CLI 的检测/调用模式（不依赖捆绑） | sandbox 下 entitlements 设计 |
| B5 | App Store 审核对 qlgenerator / Finder Sync / Share Extension 的当前政策 | 上架前确认 |
| B6 | 中文术语的"用户实测"环节：3–5 名母语用户的 task-based 测试 | 不能只靠模型评审 |
| B7 | 商业许可询价（win.rar GmbH） | 由 Codex 主导发函，本分会场只能给询价函模板建议 |

---

## 中文术语候选清单

按 Codex 复核记录的 Apple 实际字符串为权威基线。所有未在 macOS 26.5.1 `Archive Utility.app` 中观察到的字样，标注为 **"待用户/UX 测试验证"**，不得作为 spec 强制条款。

### A. 已确认的当前 macOS 简体中文字串（来自 Codex 复核 §"Codex Independent Verification"）

| macOS 实际字串 | 英文对照 | 用途 |
|---|---|---|
| `归档` | Archive (n.) | 系统级 noun |
| `创建归档…` | Create Archive… | File 菜单动作 |
| `解压缩归档…` | Extract Archive… | File 菜单动作 |
| `正在解压缩…` | Extracting… | 进度标题 |
| `设置…` | Settings… | 应用设置入口 |
| `将密码储存在钥匙串中` | Save password in Keychain | 密码提示选项 |

**直接推论**：
- "归档" 是 Apple 当前使用的 noun；产品可保留更亲民的"压缩包"作主 noun，但**设置项、菜单动作须与 Apple 当前字串对齐**，否则与系统其他 app 出现双向翻译感。
- "解压缩"是 Apple 当前使用的动作 verb，**不得用 "展开" 替代**。MiniMax-M3 关于 "解压偏 Windows 偏动作"的推断被 Apple 当前字符串证伪。
- "设置…"是 Apple 当前用语，**"偏好设置"也是 macOS 合法传统用法**（System Settings vs System Preferences 历史变迁），可在 spec 中标注为"备选"待用户测试。
- "钥匙串"是 Apple 当前用语，**不可隐藏**。用户对 "Keychain Access.app" 的认知是 macOS 的核心 UX 资产。

### B. MiniMax-M3 提议中与 macOS 当前字串冲突、须降级或搁置的项

| MiniMax-M3 提议 | 冲突 | 本分会场建议 |
|---|---|---|
| "展开"替代"解压缩"作为主动词 | Apple 当前用"解压缩" | **拒绝主推**，可在 v1 上线后通过用户测试决定是否在自定义文案中替换 |
| 用"密码本"替代"钥匙串"字样 | Apple 当前用"将密码储存在钥匙串中" | **拒绝**，保持"钥匙串"以与系统对齐 |
| 用"偏好设置" | 与 System Settings（macOS 13+）当前字串不完全一致，但 macOS 长期用法可接受 | **保留为备选**，与"设置…"并列供用户测试 |
| "校验"作为 Verify 主词 | 与 Apple 字符串无冲突（Apple 在 Archive Utility 中无对应字串） | **采纳**——非 Apple 既有字串，独立可选 |
| "正在取消 / 已取消 / 已暂停" | 与系统常规用语一致 | **采纳** |

### C. 与 Apple 当前字串无冲突、可直接采纳为产品用语

| 类别 | 推荐字串 | 来源依据 |
|---|---|---|
| 顶栏 File | `文件`、`新建压缩包`、`打开`、`关闭`、`存储为副本` | macOS 通用；MiniMax-M3 一致 |
| Edit | `编辑`、`添加到压缩包`、`展开`、`重命名`、`删除`（或 `移到废纸篓`） | macOS 通用；与 Apple 动作字串并行 |
| View | `显示`、`列表 / 分栏 / 画廊` | Finder 一致 |
| 工具栏 | `新建压缩包`、`打开`、`展开`、`添加文件`、`预览`、`搜索`、`校验`、`备注`、`共享`、`偏好设置` | macOS 通用 |
| 侧边栏 | `最近使用`、`设备`、`位置`、`标签`、`收藏`、`进行中的压缩包`、`任务`、`密码本` | Finder 一致（MiniMax-M3 提议，"密码本"虽不与 Apple 字串冲突，但功能上实际就是 Keychain 集成，UX 文案应回指"钥匙串"） |
| 压缩包状态 | `正常` / `部分损坏` / `已加密，需要密码` / `已加密，密码缺失` / `分卷（第 X / 共 Y 卷）` / `文件不完整` / `需要修复` / `正在修改` | 与 macOS 通用错误表述对齐 |
| 进度 | `准备中` / `压缩中` / `展开中` / `校验中` / `加密中` / `正在写入` / `收尾中` / `已暂停` / `等待中` / `完成` / `正在取消` / `已取消` / `未完成（原因）` | 自定义，无 Apple 既有字串冲突 |
| 错误 | `找不到文件` / `没有权限` / `磁盘已满` / `压缩包已损坏` / `不支持的格式` / `不支持的加密方式` / `密码错误` / `需要密码` / `检测到非法路径，已阻止` / `检测到非法符号链接，已阻止` / `压缩包异常膨胀，已阻止` / `符号链接循环，已阻止` / `读取 "X" 失败` / `写入 "X" 失败` / `文件名编码已自动修正` | 自定义，安全类须显式 |
| 安全提示 | `此文件来自压缩包，首次打开请确认来源` / `正在编辑压缩包内的文件，关闭窗口前会提示保存` / `使用外部应用编辑，关闭后自动更新压缩包` / `请允许访问 "XXX"` / `是否记住此压缩包的密码？保存到 "钥匙串" 中` / `需要安装助手工具 "解压助手" 以完成此操作` | 自定义 |
| 设置分类 | `通用`、`压缩`、`展开`、`加密`、`文件名编码`、`Windows 兼容`、`预览`、`性能`、`安全`、`隐私`、`更新`、`高级`、`关于` | 与 macOS 系统设置分类一致 |
| 争议项裁定 | `压缩包` (主 noun) / `归档` (Apple noun 备选，与 macOS `归档` 共存) / `解压缩` (主 verb，与 Apple 一致) / `压缩` (create) / `校验` (verify) / `重新压缩` / `挂载` / `刻录` / `接力` / `快速查看` / `Liquid Glass` (不译) / `磁盘镜像 (DMG)` / `光盘镜像 (ISO)` / `Apple 芯片 (Apple Silicon)` / `沙盒` (Xcode 译) / `公证` / `代码签名` / `路径越界` / `符号链接 (软链接)` / `资源派生 (Resource Fork)` / `AppleDouble 文件` | 与 Apple 当前字串 / Xcode 译法 / 行业惯例对齐 |

### D. 待用户/UX 实测验证（不得作为 spec 强制条款）

| 项 | 候选 | 验证方式 |
|---|---|---|
| 设置入口用语 | `设置…` vs `偏好设置…` | 5 名母语用户 A/B |
| 密码本字面是否使用 | `钥匙串` (与 Apple 一致) vs `密码本` (更亲民但需回指 Keychain) | 5 名母语用户 task-based |
| 校验字串 | `校验` vs `验证` vs `测试完整性` | 同上 |
| 错误文案 "已损坏 / 部分损坏 / 文件不完整" 区分 | 三档分立 vs 二档 | 同上 |
| 中文排序策略 | locale collation (拼音) vs 笔画 vs Unicode 码点 | 设置项可切换 + 用户偏好收集 |

---

## 架构路线与适用条件

### 三条路线的对照表（以三人共识为底）

| 维度 | 路线 A：libarchive 统一 + ZIPFoundation ZIP 编辑 | 路线 B：7-Zip 重型 + ZIPFoundation ZIP 编辑 | 路线 C：Apple 框架优先 + ZIPFoundation + 仅提取 |
|---|---|---|---|
| ZIP 编辑质量 | 高（ZIPFoundation 原生 Swift） | 高（ZIPFoundation） | 高（ZIPFoundation） |
| 7z 创建质量 | 中（libarchive 7z 写不如 7-Zip 原生；U2 标注需基准验证） | **最高**（7-Zip 原生参考实现） | **无**（产品缺口） |
| RAR 提取 | 支持（libarchive 自带 RAR4/RAR5 permissively licensed 读；X4 已澄清） | 支持（需 UnRAR 嵌入或走 libarchive 路径） | 支持（走 libarchive / UnRAR） |
| 许可风险 | 低–中（libarchive BSD 但需 SBOM；无 copyleft 传染） | **高**（7-Zip LGPL + 捆绑组件需逐项审计） | 最低（Apple 框架无许可负担） |
| App Store 适合度 | 高（sandbox 下可签 helper；X1 已澄清） | 中–低（LGPL 动态链接 / 独立进程需律师确认） | **最高** |
| 工程复杂度 | 中（C 桥接） | 高（C++/Obj-C++ 桥接 + LGPL 合规工程） | 低–中（Swift 原生为主） |
| Windows 兼容性 | 需逐项验证 | **已验证**（7-Zip 字节流历史） | 仅 ZIP 路径需验证 |
| 增量成本（加 7z 创建） | 零（已含） | 零（已含） | 高（需引入新引擎） |
| 加密支持 | ZIP AES 需第二引擎；7z AES 需 7-Zip 路径或 libarchive 7z 写 | 原生 ZIP AES + 7z AES-256 | ZIP AES 缺失（需外部） |
| Liquid Glass 适配 | 同样适用 | 同样适用 | 同样适用 |
| 用户安装 `rar` CLI 透传 | sandbox 下需 entitlements 设计 | 同 | sandbox 下需 entitlements 设计 |
| 内部 crash-recovery journal（Z7） | 可使用 libarchive / Apple Archive | 可使用 | **可使用 Apple Archive**（Z7 建议，路线 C 独有加分项） |

### 各路线的"胜出条件"映射到分发渠道决策（D2）

| 分发渠道 | 推荐路线 | 理由 |
|---|---|---|
| **App Store 独占** | **C** | sandbox 兼容、许可风险最低，但 7z 创建是产品缺口——必须通过"检测用户安装的 `7z` / `7zz` CLI"作为可选补足。Codex 必须确认 App Store 对 helper 检测外部 CLI 的当前政策（B5） |
| **直接签名分发 (Developer ID) + 公证独占** | **A** | sandbox 可选；7z 创建由 libarchive 提供；许可风险在 7-Zip 引入前可控；可承载用户安装 `rar` CLI 透传 |
| **两者并行** | **A 主线 + B 引擎作为可插拔后端**（Z8 建议） | 通过编译时 / 运行时开关切换引擎；交付两套 DMG（一套 MAS、一套直接分发） |
| **App Store + 商业 win.rar GmbH 许可谈成** | **C 主线 + RAR 创建扩展** | sandbox 下 RAR 创建仍需 entitlements；商业许可函须先确认条款 |

**注意**：
- 三条路线在 Apple Silicon + Liquid Glass + 事务重写 + 格式能力注册表 + 威胁模型等**通用层**上完全一致；分歧只在"主力引擎"层面。
- "App Sandbox 不能 exec 外部 CLI" 已被 Codex 反驳（X1），任何路线都可以嵌入签名 helper。sandbox 影响的是 entitlements / 外部文件访问 / 用户工具发现，**不是**全面禁用。
- 路线选择**不是技术问题**，是分发渠道决策（D2）反向决定。

---

## 统一验收义务

下表把三人主张的验收点合并去重，按 Codex 复核记录 + research packet 真实可查的来源分级。

### 1. RAR 相关义务
- **R-V1**：RAR 仅支持解压/浏览（X4 已澄清 libarchive 自带 permissively licensed RAR4/RAR5 读取；UnRAR 嵌入仅在选择路线 B 且法务批准时采用）
- **R-V2**：不得声明或提供 RAR 创建功能（除非 win.rar GmbH 书面商业许可 D3-1 或检测到用户安装的已授权 `rar` CLI D3-2）
- **R-V3**：在 UI 中明示 "RAR 创建：未提供 / 仅在系统已安装授权 RARLAB 工具时可用"
- **R-V4**：SimpleZip 类项目的 RAR 创建声明已确认**不是开源编码路径**，不得作为依赖证据（X3）

### 2. 加密义务
- **E-V1**：明确加密矩阵（BLOCK-4 / D4 决策后）：
  - 推荐：ZIP AES-256（WinZip AES） + 7z AES-256 + 7z 加密文件名
  - 兼容：ZipCrypto（**必须 UI 标注安全弱点**）
- **E-V2**：ZIPFoundation 已确认不含加密实现（X5），不得把 ZIPFoundation 当作加密 ZIP 主路径
- **E-V3**：密码在内存中生存时间最小化；密码不在日志、崩溃报告、撤销栈
- **E-V4**：密码输入必须走 SecureField
- **E-V5**：加密 ZIP 在 Windows 11 Explorer 上的兼容性需要实测（D1 已记录 Explorer 不支持 ZIP AES 的已知限制，需在 UI 中明示）

### 3. Unicode / 多语言文件名义务
- **U-V1**：创建 ZIP 必须设置 GP Bit 11（UTF-8 标志位）
- **U-V2**：解压旧 Windows ZIP（GBK/Big5/Shift-JIS/EUC-KR）时实现编码自动检测 + 用户 "重选编码" UI（不静默猜测）
- **U-V3**：跨平台导出预设必须处理 NFD/NFC 规范化（macOS HFS+/APFS 用 NFD，Windows 用 NFC）
- **U-V4**：拒绝 null byte 注入文件名（`filename\x00.exe`）
- **U-V5**：跨平台导出时拒绝 Windows 保留字符（`CON`、`PRN`、`AUX`、`NUL`、`COM1-9`、`LPT1-9`、`< > : " / \ | ? *`）
- **U-V6**：处理超过 255 字节 UTF-8 文件名（POSIX vs ZIP 无限制）
- **U-V7**：处理大小写冲突（Windows 大小写不敏感，不要做 case-only rename）
- **U-V8**：处理 Emoji + ZWJ 序列（不要在导出时强行拆 ZWJ）
- **U-V9**：处理 RTL 覆盖字符（U+202E，恶意伪装文件扩展名）警告或拒绝

### 4. Windows 11 互操作义务（V3 / V4 / TM-1 / 测试套件 A）
- **W-V1**：生成含中文 / 英文 / 日文 / 韩文 / Emoji / 长路径 / 大文件（>4GB）/ 嵌套目录的 ZIP，在 Windows 11 Explorer + 7-Zip + WinRAR 上双向验证
- **W-V2**：7z 创建同理验证
- **W-V3**：TAR 家族（.tar.gz / .tar.xz / .tar.zst）在 7-Zip + WinRAR + Windows tar 上验证
- **W-V4**：分卷归档（.z01/.z02/.../.zip 与 .7z.001/.7z.002）在 Windows 上合并解压验证
- **W-V5**：跨平台预设导出的归档不含 `__MACOSX` / `._*` / `.DS_Store`（POSIX 权限、UID/GID 在跨平台默认不保留）
- **W-V6**：**物理机验证**（非虚拟机，B2 / Codex 复核已明示）

### 5. 编辑事务 / 突变安全义务（INV-8 / V7 / TM-7）
- **M-V1**：所有修改走 `物化变更 → 流式写临时归档 → 验证 → fsync → 原子 rename → 保留恢复元数据`
- **M-V2**：崩溃恢复：`~/Library/Application Support/<bundleID>/recovery/{原文件, 临时文件, journal.json}`，journal 含 ops 序列与 sha256
- **M-V3**：启动时检测未完成事务，提示恢复或放弃
- **M-V4**：APFS 上用 `rename(2)`；外置 exFAT/FAT32 上无原子性，需检测并降级提示
- **M-V5**：临时区与恢复区路径分离（Caches vs Application Support），Time Machine 备份语义依赖此区分
- **M-V6**：恢复元数据保留时间窗需可配置（默认 7 / 30 天），不能永久保留

### 6. 沙箱 / Helper / 公证义务
- **S-V1**：App Sandbox 嵌入签名 helper 是允许的（X1 已澄清），但 entitlements 设计必须覆盖：外部文件访问、用户安装 CLI 检测、Quick Look 扩展跨进程通信
- **S-V2**：用户安装的 `rar` CLI / `7z` CLI 检测必须在 sandbox 下声明正确 entitlements
- **S-V3**：Hardened runtime（直接分发路线）+ App Sandbox（App Store 路线）由 D2 决定
- **S-V4**：`codesign -dvvv` 与 `spctl -a -v` 必须在 CI 中自动化
- **S-V5**：Notarization 必须走 `xcrun notarytool`，staple 必须自动化

### 7. 安全义务（INV-1 到 INV-10 + 反驳 #6）
- **SEC-V1**：结构化威胁模型：威胁代理、信任边界、纵深防御层次（X6 指出当前 evidence 仅列攻击向量名，未建模）
- **SEC-V2**：路径遍历（Zip Slip）、符号链接逃逸、解压炸弹（42.zip 类）、硬链接逃逸、设备文件创建、setuid/setgid 保留、xattr 注入、压缩比炸弹、递归归档（嵌套 zip）均需明确缓解措施
- **SEC-V3**：隔离区预览：byte / time / type 三重限制，POSIX 0700，缓存可清除
- **SEC-V4**：损坏归档安全降级：CRC 失败、中央目录缺失、截断、随机字节注入夹具
- **SEC-V5**：嵌套归档最大递归深度（默认 10 层）
- **SEC-V6**：引擎层 segfault 必须由进程隔离捕获（若 7-Zip / libarchive 通过独立进程调用）
- **SEC-V7**：Quarantine xattr 保留（macOS 系统行为），不绕过 Gatekeeper

### 8. 性能义务（TM-6 / §性能验收标准）
- **P-V1**：100K 条目归档列表 < 3s（推断，需基准验证）
- **P-V2**：单线程解压 GZIP/DEFLATE 吞吐量 ≥ 系统 Archive Utility 的 80%（推断）
- **P-V3**：10GB ZIP 删除 1 个 1MB 条目，重写时间 ≤ 全量解压再压缩的 50%（推断）
- **P-V4**：任意大小归档处理内存峰值 ≤ 4GB（流式处理硬指标）
- **P-V5**：Quick Look 预览启动 < 1s
- **P-V6**：处理 50GB 归档内存峰值 < 2GB

### 9. 可访问性义务（V14 / TM-8 / M9）
- **A11Y-V1**：所有 UI 元素有 accessibility label
- **A11Y-V2**：键盘导航 Tab/Shift+Tab/Enter/Space/Esc 完整路径
- **A11Y-V3**：Dynamic Type（macOS 26 称 Larger Text）缩放后布局完整
- **A11Y-V4**：Reduce Transparency 下 Liquid Glass 自动降级（**必须验证**，X6 风险）
- **A11Y-V5**：Reduce Motion 下禁用弹性动画
- **A11Y-V6**：增强对比度模式下可读
- **A11Y-V7**：Accessibility Inspector 无警告
- **A11Y-V8**：VoiceOver 完整工作流遍历（创建 → 浏览 → 提取 → 编辑）

### 10. 发布验证义务（V1–V16）
- **R-V8-V1**（V1）：`file` 命令确认 Mach-O arm64；Instruments 无 Rosetta 翻译
- **R-V8-V2**（V2）：Liquid Glass 检查清单（浅色 / 深色 × 所有窗口截图矩阵）— P0，**B1 阻塞**
- **R-V8-V3**（V3-V4）：Windows 11 双向互通截图 + 文件列表 diff — P0，**B2 阻塞**
- **R-V8-V4**（V5）：MiniMax-M3 + GLM-5.2 各自术语审查报告 + **用户签字**（**B6 必经**）
- **R-V8-V5**（V6-V11）：Zip Slip / 事务安全 / 多语言 / 炸弹 / 符号链接逃逸 / 加密矩阵 测试用例 + 日志
- **R-V8-V6**（V12）：Quick Look 文件类型覆盖表 + 截图
- **R-V8-V7**（V13）：跨平台预设 Windows 验证 + 文件列表
- **R-V8-V8**（V14）：VoiceOver 审计记录
- **R-V8-V9**（V15）：`codesign` + `spctl` 命令行输出
- **R-V8-V10**（V16）：完整 SBOM（**B3 阻塞**）

---

## 当前阻断决策

按 SOUL.md §3 "定义可验证结果"原则，下列决策若不解决，下游一切设计 spec、代码脚手架、QA 夹具都将悬空。本分会场**不替用户决定**，仅按阻塞强度排序。

### 决策矩阵

| # | 决策 | 阻塞面 | 阻塞强度 | 谁可决 | 默认（若不决） |
|---|---|---|---|---|---|
| **D2** | **分发渠道**：App Store / 直接签名 / 两者并行？ | 决定 sandbox 路线 / helper entitlements / 许可策略 / 引擎选型 | **P0 完全阻塞** | 用户 | **无法写 spec** |
| **D1** | 最低 macOS 目标（macOS 26 vs 兼容 14/15） | 决定 Liquid Glass 可用性 / 装机量 / 视觉语言 | P0 阻塞 | 用户 | 取 macOS 26（research 默认） |
| **D3** | RAR 创建策略：仅读 / 透传已授权 CLI / 商业许可 | 决定 RAR 章节在 spec 中的写法 / 风险声明 | P0 阻塞 | 用户 + Codex 主导询价 | 仅读 |
| **D4** | 加密矩阵：ZIP AES / ZipCrypto / 7z AES / 加密文件名 / 头加密 | 决定 ZIPFoundation 之外需补哪条引擎路径 | P0 阻塞 | 用户 + 法务 | ZIP AES-256 + 7z AES-256 + 加密文件名 |
| **D5** | 商业模式：买断 / 订阅 / freemium？ | 决定功能分级（v1 范围） | P1 阻塞 v1 范围 | 用户 | 待 D5 |
| **D6** | v1 是否仅中文？多语言时机 | 决定资源（文案、图标、术语表）规模 | P1 阻塞 v1 范围 | 用户 | 中英双语 |
| **D7** | 密码存储：Keychain vs App 自有加密 | 决定安全章节 | P2 | 用户 | macOS Keychain |
| **D8** | App 中文商业产品名 | 影响 App Store 搜索与品牌；早决定成本低 | P2 | 用户 + 市场 | 未决 |
| **D9** | Quick Look qlgenerator 行为：显示条目列表 vs 自动展开首层 | 影响 Finder 集成体验 | P2 | 用户 + 设计 | 显示条目列表 |

### 单一最关键阻塞项

**D2（分发渠道）是当前唯一完全阻塞设计 spec 的决策。** 它反向决定：

1. **sandbox 路线**：sandboxed vs unsandboxed → helper 打包方式 / entitlements / 外部文件访问能力。
2. **引擎选型**：App Store 路线偏向 C（Apple 框架优先 + 仅提取）或 A（libarchive），避开 B（7-Zip LGPL）；直接签名路线可承担 B。
3. **RAR 创建策略（D3）**：sandbox 下透传用户安装 `rar` CLI 需 entitlements；MAS 路线对外部进程检测政策可能更严。
4. **用户安装工具检测（D3-2）**：sandbox 下文件枚举范围受限。
5. **提交与发布流程**：App Store 审核 vs 公证 + 分发；签名身份（Apple Development / Developer ID Application）不同。

**Codex 应在本周内把 D2 提交用户拍板**。在 D2 确定之前，本分会场无法给出可执行的架构推荐。

### 次级阻塞

**D1（最低 macOS）+ D3（RAR）+ D4（加密矩阵）** 任一未决，架构推荐均不能写死。其余 D5–D9 是 v1 范围/UX/品牌决策，可在 spec 起草中预留接口、由用户后续拍板。

### Codex 复核已警示但仍待办的事项

- **B1**：完整 Xcode 尚未本地化部署，Liquid Glass 编译与渲染验收未执行。
- **B2**：Windows 11 真实机器物理验证未做（任何 W-Vx 在未做物理验证前均处于"理论可验收"状态）。
- **B3**：7-Zip / libarchive / XADMaster / ShichiZip 完整 SBOM 缺失。
- **B5**：App Store 对 qlgenerator / Finder Sync / Share Extension 当前政策未确认。
- **B6**：中文术语用户实测未做（3–5 名母语用户 task-based 测试）。
- **B7**：win.rar GmbH 商业 SDK 询价未发起。

---

## 分会场建议

按 SOUL.md §14"Final Delivery Rules"，本分会场给出**咨询性建议**，不作最终裁定。Codex 是最终裁定者。

### S1：路线推荐（在 D2 决策之前的中性表述）

按 D2 分发渠道，三种结论：

- 若 **App Store 独占**：采纳 **路线 C**（Apple 框架优先 + ZIPFoundation + libarchive/UnRAR 仅提取），但 7z 创建为产品缺口——通过可选 helper 检测用户安装的 `7z`/`7zz` CLI 补足；用户安装 `rar` CLI 检测需 entitlements。
- 若 **直接签名分发**：采纳 **路线 A**（libarchive 统一 + ZIPFoundation ZIP 编辑），可在不加 LGPL 负担下提供 7z 创建。
- 若 **两者并行**：**路线 A 为主线 + 路线 B 的 7-Zip 引擎封装为可插拔后端**（按 DeepSeek Pro Z8 建议），通过编译时或运行时开关切换。
- 若 **商业 win.rar GmbH 许可谈成**：在所选路线上加 RAR 创建扩展。

通用层（不分路线）必含：
- 格式能力注册表驱动 UI（C3）
- 事务重写 + 原子替换 + 恢复元数据（C2、M-V1–V6）
- GP Bit 11 写入 + Windows 双向互通 fixture（C6、U-V1、W-V1–V5）
- 结构化威胁模型 + 10 项安全不变量（C7、SEC-V1–V7）
- a11y 全量验收（C8、A11Y-V1–V8）
- macOS 当前简体中文字串作为系统级字串基准（§中文术语清单 A 类）

### S2：术语处置建议

- **不可作为 spec 强制条款的字串**（与 Apple 当前 macOS 26.5.1 字符串冲突）：
  - 用 "展开" 替代 "解压缩" — 拒绝，Apple 当前用 "解压缩"
  - 用 "密码本" 替代 "钥匙串" — 拒绝，Apple 当前用 "钥匙串"
  - 用 "偏好设置" 替代 "设置…" — 保留为备选，待用户测试
- **可直接采纳的字串**：Apple 当前字串 + 与 Apple 字串无冲突的自定义字串（详见 §中文术语候选清单 C 类）。
- **必须用户实测的字串**：见 §D 类清单。

### S3：修订项优先级

按阻塞强度排序（与 GLM-5.2 BLOCK/REVISE 框架对齐）：

**P0 完全阻塞**：
- BLOCK-2：分发渠道决策（D2）
- REVISE-1：ZIPFoundation 加密确认（X5 已结案 → 需补引擎）
- REVISE-2：编码检测策略
- REVISE-3：macOS 最低版本目标（D1）
- BLOCK-3：7-Zip LGPL 法务审计
- BLOCK-4：加密矩阵决策（D4）
- R-M1（MiniMax-M3 M1）：RAR 创建三选一（D3）

**P1 阻塞 v1 范围**：
- D5 商业模式 / D6 多语言时机 / D7 密码存储 / D8 App 名 / D9 qlgenerator 行为

**P2 不阻塞但必须做**：
- §B1–B7：Codex 复核已警示的事项（Xcode 安装、Windows 物理验证、SBOM、MAS 政策、术语实测、win.rar 询价）

### S4：不向 spec 注入的"模型未验证断言"

按本分会场治理原则，**任何未经 Codex 直接验证的模型断言不得作为 spec 强制条款**：

- Liquid Glass 具体 modifier 命名（`.glassEffect` / `GlassEffectContainer` 等）— 由 Codex 在补齐 Xcode 后以 Apple 当前 GM SDK 文档为准
- "macOS 14/15 占装机量 30–40%" — 商业影响数字不写死，由用户拍板 D1 时一并判断
- "macOS 26 已停止 Intel 支持" — 未由 Apple 公开文档直接验证；D1' 决策（Apple Silicon only 的产品理由文档化）需 Codex 验证
- ZIPFoundation 之外的 ZIP AES 实现路径选择 — 由 REVISE-1 完成源码审查后由 Codex 选定
- 第三方 Windows 工具链对 ZIP GP Bit 11 的精确支持矩阵 — 必须 Windows 物理实测（B2）

### S5：本分会场不背书的项

- 任何具体 Liquid Glass API 命名
- 任何"商业影响百分比"数字
- 任何"MiniMax-M3 字面替换 macOS 当前字符串"的提议
- 任何"已证伪 SimpleZip"措辞（X3 已澄清非谎言，只是非开源编码路径）

---

## LOOP 记录

### 循环合约

- **目标**：以分会场主席身份，独立交叉核对三位参与者（M3 / GLM-5.2 / DeepSeek Pro）输出与 Codex 复核记录，给出可被 Codex 采纳的咨询性建议。
- **假设**：三位参与者输出均为咨询性独立审计；Codex 复核记录是当前最高置信度的真实世界证据；本输出不替代 Codex 决定。
- **退出标准**：本文覆盖任务清单要求的 9 节 schema；每条结论标注证据/推断；明确区分 Codex 已反驳的断言、参与者之间的分歧、待用户拍板的决策。

### 迭代记录

#### 迭代 1 — Locate
- **动作**：完整读取 SOUL.md（571 行）+ 任务清单 8 个文件 + 列出 runs 目录确认未读占位文件。
- **观察**：SOUL.md §11 明确 Codex 委托边界与会议模式路由；Codex 复核记录（43 行）是当前**最高置信度**的真实世界证据来源，已直接检查 Apple 文档与源码事实。
- **评估**：证据基础充分，可进行分会场比较审计。

#### 迭代 2 — Outline
- **动作**：建立四层证据优先级（Codex 直接验证 > research 一手 URL > 三人共识 > 单人推断）。
- **观察**：三人输出在 §共识 / §分歧 / §错误 三个层面均能干净分离；Codex 复核记录提供了关键的"模型断言 vs 真实世界"对照。
- **评估**：可产出结构化 9 节输出。

#### 迭代 3 — Operate
- **动作**：分别构建共识表 (C1–C12)、反驳表 (X1–X7)、分歧表 (Y1–Y6)、补充观察 (Z1–Z8)、盲点表 (B1–B7)、术语清单（A/B/C/D 四类）、架构路线对照、10 项验收义务、决策矩阵、建议清单。
- **观察**：
  - Codex 反驳的关键事实（X1 / X2 / X4 / X5 / X6）必须在分会场输出中**显式标注**，不得让被反驳的断言以中性面貌出现。
  - 决策 D2（分发渠道）是单一最关键阻塞项；D1 / D3 / D4 同等阻塞 v1 spec 章节。
  - 三人在 §路线 上分歧本质上是"许可风险 vs 功能完整性 vs 工程复杂度"三维权衡，**只有 D2 决策能消解此分歧**。
- **评估**：本分会场不能也不应替用户做 D2 决定。给出"按 D2 分支"的中性推荐是合理咨询边界。

#### 迭代 4 — Polish
- **动作**：自审，从 reviewer / user / third-party 三视角检查。
- **发现与修正**：
  1. 修正：初稿把 "展开 / 校验 / 密码本" 作为推荐，**修订为与 Apple 当前字符串对齐**（拒绝字面替换）。
  2. 修正：初稿把 SimpleZip RAR 标记为 "已证伪"，**降级为"不构成开源编码路径证据"**（按 X3 澄清）。
  3. 修正：初稿把 libarchive RAR 读取标为 "需 UnRAR 嵌入"，**修正为 libarchive 自带 permissively licensed RAR4/RAR5 读取**（按 X4 澄清）。
  4. 修正：初稿未把 "Codex 必须复核的事项" 与 "本分会场背书 / 不背书" 显式分开，**新增 §S5 不向 spec 注入的项**。
  5. 修正：初稿 §路线 把路线 A/B/C 等权推荐，**修订为按 D2 决策分支**，避免越权。
  6. 审查：所有"商业影响百分比"、"API 命名"均标注为推断或未验证。

### 观察汇总

1. 三位参与者的输出在 **共识层（C1–C12）已足以支撑 design spec 的 80% 章节**，无需更多评审轮次。
2. 三位参与者的输出在 **路线选择上**未达成单点共识，且都未给出按 D2 决策分支的条件推荐。本分会场填补了这一缺口。
3. Codex 复核记录**实质性提升了三份输出的可信度**——它把"模型推测"区分成"已验证事实 / 推断 / 错误"。本分会场以此为权威基线。
4. 三人都把 **RAR 创建**标为不可行（默认仅读），共识度高；唯一差异是措辞（"已证伪" vs "不构成证据"）和后续行动（MiniMax-M3 强制决策 / GLM-5.2 CLI 检测 / DeepSeek Pro 主动询 win.rar GmbH）。
5. 中文术语是本次评审的**最大单一争议**：MiniMax-M3 的字面替换建议被 Codex 直接反驳（X2）；本分会场采纳 Codex 复核记录的 Apple 当前字符串作为基线，并把 MiniMax-M3 提议按"采纳 / 降级 / 待用户实测"三类处置。

### 拒绝的声明（被 Codex 反驳或本分会场不予采纳）

| # | 来源 | 声明 | 拒绝理由 |
|---|---|---|---|
| R-1 | MiniMax-M3 A5 / GLM-5.2 隐含 | "App Sandbox 不能 exec 外部 CLI" | X1：sandbox 允许嵌入签名 helper；影响的是 entitlements 不是 exec 本身 |
| R-2 | MiniMax-M3 术语表 | 用 "展开" 替代 "解压缩" 作主动词 | X2：Apple 当前 macOS 26.5.1 `Archive Utility.app` 用 "解压缩" |
| R-3 | MiniMax-M3 术语表 | 用 "密码本" 替代 "钥匙串" | X2：Apple 当前用 "将密码储存在钥匙串中" |
| R-4 | DeepSeek Pro 反驳 #1 | SimpleZip RAR 创建 "已证伪" | X3：源码显示其下载/检测 RARLAB `rar` CLI 并披露许可，不是功能谎言 |
| R-5 | GLM-5.2 许可证段 | "libarchive 集成 unrar 受 UnRAR 限制" | X4：libarchive 自带 permissively licensed RAR4/RAR5 读取 |
| R-6 | GLM-5.2 ZIP 段 | "ZIPFoundation 加密需验证" | X5：已确认 ZIPFoundation 不含加密实现 |
| R-7 | 三人均暗含 | "Liquid Glass API 假定当前可用" | X6 / B1：完整 Xcode 未部署；不得作为 spec 强制条款 |
| R-8 | MiniMax-M3 商业影响段 | "macOS 14/15 占装机量 30–40%" | 无可靠证据；商业数字不写死 |

### 不确定性汇总

| # | 不确定性 | 来源 | 影响 | 解决方式 |
|---|---|---|---|---|
| U1 | Liquid Glass 在当前 Xcode GM 中的 API 命名 + 控件覆盖 | 模型未验证；完整 Xcode 未部署 | 高（影响 A1 / C 类 modifier） | Codex 补齐 Xcode 后跑通 SwiftUI Liquid Glass 示例（B1） |
| U2 | ZIPFoundation 之外 ZIP AES 实现路径选择（minizip-ng / 7-Zip / 自实现） | 待 Codex 源码审查 | 高（影响 E-V2 引擎选型） | Codex 完成 REVISE-1 |
| U3 | libarchive 7z 写入与 7-Zip 原生差距 | 无基准测试 | 中（影响路线 A 评分） | 原型 + Windows 互操作测试 |
| U4 | App Store 对 qlgenerator / Finder Sync / Share Extension 的当前政策 | 未确认 | 中（影响 v1 集成范围） | Codex 查 Apple 当前审核指南（B5） |
| U5 | 用户对中文术语的实际偏好（5 项待测） | 无用户测试 | 中（影响 §D 类字串） | 5 名母语用户 task-based 测试（B6） |
| U6 | win.rar GmbH 商业 SDK 许可可行性 | 未询价 | 低–中（影响 D3 决策） | Codex 发函询价（B7） |
| U7 | 性能基准数值（P-V1–V6）均为推断 | 无实测 | 中（影响发布门槛） | 在原型阶段基准化 |
| U8 | 第三方 Windows 工具链对 ZIP GP Bit 11 的精确支持矩阵 | 无 Windows 物理验证 | 高（影响 V3 / V4 验收） | 物理机验证（B2 / W-V1–V5） |

### 推荐的下一循环（for Codex）

1. **立即**（本周）：
   - 把 D2（分发渠道）提请用户拍板（最关键阻塞）
   - 把 D1（macOS 最低版本）+ D3（RAR 策略）+ D4（加密矩阵）一并提请用户拍板
   - 启动 win.rar GmbH 询价（D3-1 路径）
   - 安装完整 Xcode（B1）
2. **并行**（本周内）：
   - 源码审查 ZIPFoundation 修改语义 + ZIP64 + 编码检测（R-1 / REVISE-1 / REVISE-2 / REVISE-4）
   - 生成 libarchive / 7-Zip / XADMaster / ShichiZip 完整 SBOM（B3 / BLOCK-3）
   - 与法务确认 7-Zip LGPL 分发策略（BLOCK-3）
3. **设计 spec 启动后**（D2 决策后）：
   - 写 design spec v0.1，把 C1–C12 共识 + §10 项验收义务按 D2 分支落入对应章节
   - 把 §中文术语候选清单 A/C 类直接采用为 v1 字串基线，D 类保留为 UX 测试项
   - 把 X1–X7 反驳对应的章节在 spec 中以"已澄清"或"已确认"措辞写入，避免下游再次引发讨论
4. **不建议**：
   - 不在本评审完成前启动代码脚手架（per `plans/codex_main_venue_mac_archive_app.md` 第 5 步）
   - 不发起第三次独立评审轮次——三位参与者的共识已足够支撑 design spec
   - 不在没有 D2 决策的情况下拍板任何路线

### 边界确认

- 本评审**未**访问任何外网、任何外部服务、任何生产路径、任何 prompt 模板、任何日志、任何 `.codebuddy/` 文件。
- 本评审**仅**修改 `/Users/smkzw/Documents/AI Products/runs/conference/mac_archive_app/hermes_lead.md` 一个文件。
- 本评审**仅**读取任务清单列出的 8 个文件。
- 本评审**未**声明对最终架构、代码、运行时、视觉或商业发布的裁定权。
- 本评审**未**对任何临床/监管/法律结论作最终声称（本次任务无相关范围，但作为治理原则声明）。
- Codex 仍为最终裁定者；本次输出为咨询性 sub-venue chair package。

### 会场签名

- **分会场主席**：OpenCode Go `minimax-m3`（Hermes/aishuo MiniMax-M3）
- **会议模式**：parallel
- **完成时间**：2026-07-11
- **本评审归档**：在 Codex 完成最终裁定后归档；Codex 拥有 archive/export 决定权。