# MiniMax-M3 产品与中文术语评审

## 已读取输入

确认已完整阅读以下文件（按 SOUL.md §11 “Codex 委托”要求，逐字阅读而非摘要）：

- `/Users/smkzw/.hermes/SOUL.md`：完整阅读到 571 行（含 model routing 附录）。声明：已读全，遵守其指令层级、证据标准、Codex 委托边界、会议模式路由规则。Hermes 是 sub-venue chair, Code X 是 final authority；本评审为咨询性输出, 不做最终临床/监管/视觉/生产写入判定。
- `/Users/smkzw/Documents/AI Products/context/mac_archive_app_conference_context.md`：完整阅读 70 行。提取：任务=`complex_delivery_conference`, 风险=`high`, 会议模式=`parallel`, sub-venue chair=`minimax-m3`（即本人）, 参与者包含 `qwen3.7-plus` / `mimo-v2.5` / `deepseek-v4-flash`；主会场高风险复核由 `deepseek-v4-pro` 经 Reasonix CLI 承担, **不经 Hermes**。
- `/Users/smkzw/Documents/AI Products/plans/codex_main_venue_mac_archive_app.md`：完整阅读 53 行。提取：Codex 七步任务分解、本评审属于第 3 步 “独立术语/产品/架构评审”, 输出路径已规定。
- `/Users/smkzw/Documents/AI Products/research/2026-07-11_initial_landscape.md`：完整阅读 116 行。提取：商业产品证据（BetterZip/Keka/PeaZip）、Apple 平台证据（Liquid Glass / SwiftUI sample / AppleArchive / Compression）、开源候选（libarchive / 7-Zip / ZIPFoundation / SWCompression / XADMaster / ShichiZip / MacPacker / SimpleZip / libarchive-swift）、RAR 创建许可结论、早期架构假设、待决问题清单。

**未读取**（按任务硬约束）：
- 同目录下其他 5 份参与者输出（`runs/conference/mac_archive_app/participant_*.md`、`hermes_lead.md`、`main_deepseek_pro.md`）——任务清单中未列入, 不读取以保持独立性。
- 任何生产路径、prompt 模板、日志、邮件翻译文件夹、`.codebuddy/`——同上。
- 未访问外网、未调起任何外部服务。

**证据来源分级**（按 SOUL.md §4）：
- 一手来源（高置信度）：Apple Developer 文档 URL（Liquid Glass 适配页、SwiftUI 示例、Archive/Compression 框架）、RARLAB 官方许可、libarchive/7-Zip/ZIPFoundation/SWCompression/XADMaster/ShichiZip/MacPacker 仓库。
- 二手来源（中置信度）：research packet 中对各产品的能力总结（README 性质, 未做源码验证）。
- 推断（低置信度, 须明确标记）：Liquid Glass 具体 API 表面（`.glassEffect` modifier 系列）、macOS 26 SDK 中 AppleArchive `ByteStream` 命名、第三方 Windows 工具链对 ZIP GP Bit 11 的精确支持矩阵——这些我未实时抓取 Apple 文档, 视为推断而非证据。

---

## 用户场景与商业产品缺口

research packet 给出了 “Apple Silicon + Liquid Glass + Chinese-first + Windows 兼容 + 浏览/编辑压缩包” 的目标定位, 但**用户场景层几乎是空白**。下面列出必须补齐的场景与对应的产品/合规风险。

### 1. 缺失的典型用户场景

按中文市场优先级排列, 标注“是否被现有竞品覆盖”：

| # | 场景 | 谁在用 | 现有方案 | 本项目是否覆盖 | 风险 |
|---|---|---|---|---|---|
| S1 | 微信/钉钉/飞书接收的 `.zip` 含中文文件名, 群文件批量下载后查看/解压 | 全民级, 中小企业员工 | macOS 原生 “归档实用工具”、Keka、BetterZip | 部分（解压可, 编辑/再压缩需验证） | 中文文件名乱码/排序异常 |
| S2 | 律师/会计/审计交付包：合同 PDF 集 + 邮件附件 + 证据链, 要求 SHA-256、签名时间戳、原始时间戳保留 | 法律/会计/审计专业人士 | BetterZip、命令行 zip -r | **未覆盖**（缺校验/审计元数据） | 合规风险 |
| S3 | 影视/设计/出版行业：超大单文件 (10–80 GB) 跨平台传输, 需分卷/校验/恢复记录 | 创意行业 | Keka 分卷、WinRAR 恢复记录 | **未覆盖**（research 未提分卷与恢复记录） | 商业竞争力 |
| S4 | 科研/教育：.tar.gz / .tar.xz / .7z 包（含可执行、文档、参考数据）, 需选择性解压、预览、深搜 | 高校/实验室 | 7-Zip、Keka | 部分 | 7z 编辑能力被研究包 “全额工作流” 声明但未实现细节 |
| S5 | 跨境/涉外：源文件中文, 同事 Windows 端, 必须用 UTF-8 ZIP（GP Bit 11）防乱码 | 跨境团队 | BetterZip（号称去 macOS 专属元数据） | **未验证**（需要 Windows 11 Explorer + 7-Zip 双向互通测试夹具） | 核心卖点被质疑 |
| S6 | 个人/家庭：iPhone 备份/相机 RAW 批量归档, 需保留 EXIF、原始 mtime | 摄影爱好者 | 苹果 “图像捕捉”、Photos | **未覆盖** | 商业可行性低, 可砍 |
| S7 | 程序员/运维：源码 tarball 提取, 软链/可执行位/POSIX ACL 保留 | 开发者 | 终端 tar | 需支持 | 易被对标 |
| S8 | 收到可疑压缩包（社工附件/钓鱼）：解压前需沙箱预览、行为提示 | 安全意识高的企业 | BetterZip 隔离预览、Quick Look | 部分（quick look 已有, 缺显式安全提示 UX） | 法律责任 |
| S9 | 学校/培训机构机房管理员：批量部署脚本分发、预置压缩格式默认参数 | 教育 IT | N/A | **未覆盖** | 商业渠道 |
| S10 | 个人开发者交付：将自己写的工具打成 `.7z`/`.zip` 加密自解压给客户 | 独立开发者 | 7-Zip SFX | **未覆盖** | 商业渠道 |

### 2. 商业产品风险（按严重性）

**R1（致命）：RAR 创建许可断裂** —— research packet 已识别 “无可信合法开源 RAR 写入器”, 但 `codex_main_venue_mac_archive_app.md` 第 8 行与 `context` 第 33 行仍把 “RAR create only if exists” 挂在 provisional matrix 上。产品决策必须三选一明确, 不能再留模糊：(a) 只读 + 解压；(b) 检测系统已安装的授权 `rar` CLI 并透传, 但需用户自己持有许可；(c) 谈 win.rar GmbH 商用分发许可。**当前 “if exists” 表述会让产品和法务团队在发布前夜打架**。→ 见 §必须修订项 M1。

**R2（高）：ZIP 中英文文件名互通的核心未验证** —— research 提 “ZIPFoundation 需验证 Windows 行为”, 但没有定义验证矩阵：是否产出 GP Bit 11？Windows 11 Explorer 自 1903 起默认对未置位 GP Bit 11 的 ZIP 用系统代码页（CP936/CP950）解码, 仍是历史痛点。**该指标必须作为 “Windows 互操作 fixture” 的可断言条款**, 而不是 README 上的 “应该可以”。→ M2。

**R3（高）：7z “编辑” 语义被过度承诺** —— research 提 “ZIP and 7z full workflow: create/extract/browse/edit/encrypt”。7z 没有 ZIP 式的中央目录, 对 7z 做“添加/删除/重命名单条”必须**全包重写** (rewrite-whole-archive), 与 ZIP 的“in-place update”成本/失败率截然不同。**面向用户的产品语言必须区分 “可直接编辑” (ZIP) 和 “需重建” (7z/TAR 家族)**。→ M3。

**R4（高）：macOS 元数据剥离反向问题** —— research 假设 “导出时去 `._*`/`.DS_Store`/`__MACOSX` 给 Windows”, 但**反向没提**：从 Windows 端 ZIP 解回 macOS 时, 如果原 ZIP 里有 macOS 元数据（更可能是用户自己给自己备份的 macOS 机器出来的 zip）, 需要正确还原 AppleDouble 与 xattr。BetterZip 双向都做, 是它的护城河之一。**单向剥离会伤害“个人备份”场景**。→ M4。

**R5（中）：DMG/ISO “只读浏览/解压” 提得太轻** —— DMG 在中文用户里几乎等同于“Mac 软件安装包”, 提“解压”会引发用户期待“提取 .app 后能直接运行”。DMG 的安全模型（代码签名公证、quarantine xattr、Gatekeeper）和裸文件提取是两件事。**必须在 UX 上把 “挂载并运行” 与 “裸提取” 拆成两条路径**, 不能让用户误以为提取即安装。→ M5。

**R6（中）：沙箱/公证路线的工程影响未在架构假设中显化** —— research §Open Questions 第 1 条只问 “直分发/MAS/两者”, 但 sandbox + helper binary 政策对 “挂载 DMG / 调用外部 rar CLI / QuickLook 扩展” 都有结构性影响。**架构假设应当分两套 (sandbox-on / sandbox-off) 并标注每条假设在哪一套下成立**。→ M6。

**R7（中）：Liquid Glass 是 macOS 26 引入的视觉语言, 假设评审中未讨论最低 macOS 目标** —— research 提 “latest macOS” 但没钉死版本。Liquid Glass 强制 macOS 26+ baseline, 这会直接砍掉 macOS 14/15 用户（约 30–40% 装机, 2026 年估算值, 须 Codex 校准）。**最低系统目标是一个商业决策, 不是技术细节**。→ M7。

**R8（中）：中文搜索/排序/输入法交互** —— 中文文件名排序需要 locale-aware collation（拼音 vs 笔画 vs Unicode 码点）, Finder 默认行为, 第三方压缩工具常踩坑。**评审没把 “中文排序策略” 列为可配置项**。→ M8。

**R9（中）：可访问性 (a11y) 几乎没有约束** —— 商业 macOS App 评审常查 VoiceOver、Dynamic Type（macOS 26 称 “Larger Text”）、Reduce Motion、Reduce Transparency。Liquid Glass 本身在 Reduce Transparency 下应自动 fallback, 但需要验证。**“商业化可用” 暗含 a11y 验收, 没写明就是盲点**。→ M9。

**R10（低）：版权/恶意文件扫描** —— 中文网盘分享的压缩包常见 “学习资料” 名义下的侵权内容。专业版可集成 AV 扫描 hook（ClamAV 之类）, 但超出 v1 范围, **应明确列为 “v1 不做, v2 评估”**。→ M10。

---

## 中文信息架构与术语表

### 1. 信息架构原则（给 Codex/产品设计师）

中文母语用户对压缩工具的认知是**“压缩包” (主) + “归档” (Apple/技术官腔)** 二元结构, 商业产品选词需**主显隐辅**：

- 一级导航、按钮、错误消息用 “压缩包” 类口语词。
- 设置、关于、API 文档用 “归档” 类正式词（与 Apple “归档实用工具” 对齐, 避免双向翻译感）。
- **永远不要**用直译英文 (“归档档” / “压缩档” / “文件柜” 都不要)。

避免的字眼：

- ~~解压~~ (过于“动”且偏 Windows 用法) → 主用 **展开** / 副用 **解压缩** (macOS 原生术语)
- ~~档案~~ (在中文里有“人事档案”歧义) → 不用
- ~~封包~~ (电竞/网络用语) → 不用
- ~~打包~~ (动作词, 不要和“压缩包”名词混用)

### 2. 完整术语表

| 类别 | 元素 | 推荐中文 (主) | 备选/英文 | 解释/消歧 |
|---|---|---|---|---|
| 顶栏菜单 | File 菜单 | **文件** | File | 标准 |
| | File > New Archive | **新建压缩包** | 新建归档 | 主用前者 |
| | File > Open | **打开** | 打开 | 标准 |
| | File > Close | **关闭** | 关闭 | 标准 |
| | File > Save a Copy | **存储为副本** | 另存为 | macOS 标准 |
| | Edit 菜单 | **编辑** | 编辑 | 标准 |
| | Edit > Add to Archive | **添加到压缩包** | 添加到归档 | 动词短语 |
| | Edit > Extract | **展开** | 提取 / 解压 | **避免 “解压”**; 动作菜单项用动词, 选 “全部展开” / “展开到此处” / “展开到子文件夹” |
| | Edit > Rename | **重命名** | 重命名 | 标准 |
| | Edit > Delete | **删除** | 删除 (内) vs 移到废纸篓 | 二选一; 推荐 **移到废纸篓** (符合 macOS 习惯) |
| | View 菜单 | **显示** | 检视 (macOS 历史) | 与 “显示” 统一 |
| | View > as List / as Columns / as Gallery | **列表 / 分栏 / 画廊** | 与 Finder 一致 | Finder 已经定调, 不要造词 |
| | Window 菜单 | **窗口** | 窗口 | 标准 |
| | Help 菜单 | **帮助** | 帮助 | 标准 |
| 工具栏 | New | **新建压缩包** | ＋ 图标 | |
| | Open | **打开** | 打开 | |
| | Extract | **展开** | 展开 | |
| | Add Files | **添加文件** | ＋ 文件图标 | |
| | Preview | **预览** | 预览 (Quick Look 集成) | |
| | Search | **搜索** | 搜索框 | placeholder: “在压缩包内搜索” |
| | Test (verify) | **校验** | 验证 / 测试完整性 | 避免 “测试” 与 QA 歧义 |
| | Comment | **备注** | 注释 (ZIP comment) | |
| | Share | **共享** | 共享 (系统分享面板) | |
| | Settings | **偏好设置** | 偏好设置 / 设置 | macOS 用 “偏好设置” 更地道, 但 “设置” 也可 |
| 侧边栏组 | Recents | **最近使用** | 最近 | 与 Finder/macOS 统一 |
| | Devices | **设备** | 设备 | |
| | Locations | **位置** | 位置 | |
| | Tags | **标签** | 标签 | macOS 标签 |
| | Favorites | **收藏** | 收藏 | |
| | Archives (in-progress) | **进行中的压缩包** | 任务列表 | 比 “下载中” 准确 |
| | Tasks / Queue | **任务** | 任务队列 | 避免 “队列” 显得技术 |
| | Password Vault | **密码本** | 已存密码 | “密码本” 比 “密码库” 更亲民, “金库” 显得重 |
| 压缩包状态 | Healthy | **正常** | 完整 | “正常” 比 “健康” 更日常 |
| | Has errors | **部分损坏** | 存在错误 | 不要 “出错” / “故障” |
| | Encrypted (password required) | **已加密, 需要密码** | 受密码保护 | 比 “已锁定” 清晰 |
| | Encrypted (no password) | **已加密, 密码缺失** | 密码无法恢复 | **必须明确**：不暗示能找回 |
| | Part of multi-volume (volume X of Y) | **分卷 (第 X / 共 Y 卷)** | 分卷压缩 | 显式 “第 X / 共 Y 卷” 不只是 “volume 1” |
| | Truncated | **文件不完整** | 截断 | |
| | Needs repair | **需要修复** | 修复提示 | 跟“损坏”区别 |
| | Modifying | **正在修改** | 编辑中 | 比 “正在编辑” 区分用户输入 |
| 进度状态 | Preparing | **准备中** | 准备 | |
| | Compressing | **压缩中** | 压缩 | |
| | Extracting | **展开中** | 展开 | |
| | Verifying | **校验中** | 校验 | |
| | Encrypting | **加密中** | 加密 | |
| | Writing | **正在写入** | 写入 | |
| | Finalizing | **收尾中** | 完成最后处理 | 避免 “finalize” 直译 |
| | Paused | **已暂停** | 已暂停 | |
| | Queued | **等待中** | 排队 | |
| | Done | **完成** | 完成 | |
| | Cancelling | **正在取消** | 取消中 | |
| | Cancelled | **已取消** | 已取消 | |
| | Failed (with reason) | **未完成 (原因)** | 失败 (原因) | **永远带原因**, 不要裸 “失败” |
| 错误类别 | File not found | **找不到文件** | 文件不存在 | |
| | Permission denied | **没有权限** | 权限不足 | |
| | Disk full | **磁盘已满** | 存储空间不足 | |
| | Archive corrupted | **压缩包已损坏** | 归档损坏 | |
| | Unsupported format | **不支持的格式** | 格式不受支持 | |
| | Unsupported encryption | **不支持的加密方式** | 加密方法不兼容 | |
| | Password incorrect | **密码错误** | 密码不正确 | **不要 “密码无效”** |
| | Password missing | **需要密码** | 请输入密码 | |
| | Path traversal blocked | **检测到非法路径, 已阻止** | 路径越界 | 安全类, 必须显式 |
| | Symlink escape blocked | **检测到非法符号链接, 已阻止** | 符号链接越界 | |
| | Decompression bomb | **压缩包异常膨胀, 已阻止** | 解压炸弹 | 不说 “可能恶意” (无证据不指控) |
| | Symlink loop | **符号链接循环, 已阻止** | 软链环 | |
| | Read error (entry X) | **读取 “X” 失败** | 条目读取错误 | 永远带条目名 |
| | Write error (entry X) | **写入 “X” 失败** | 条目写入错误 | |
| | Encoding fallback | **文件名编码已自动修正** | 编码已修正 | 不说 “猜测” |
| 安全提示 | Quarantined entry opened | **此文件来自压缩包, 首次打开请确认来源** | 隔离提示 | macOS 自身 quarantine xattr 文案 |
| | Editing files inside archive | **正在编辑压缩包内的文件, 关闭窗口前会提示保存** | | 关键防误操作 |
| | External editor round-trip | **使用外部应用编辑, 关闭后自动更新压缩包** | | |
| | Permission to access folder | **请允许访问 “XXX”** | | 标准 |
| | Password storage | **是否记住此压缩包的密码? 保存到 “密码本” 中** | | 不要 “保存到钥匙串” 直接说, 避免与 Keychain Access.app 混淆 |
| | Helper tool install | **需要安装助手工具 “解压助手” 以完成此操作** | | sandbox 路线必备 |
| 设置分类 | General | **通用** | 通用 | 标准 |
| | Compression | **压缩** | 压缩 | |
| | Extraction | **展开** | 解压 | 与菜单一致 |
| | Encryption | **加密** | 加密 | |
| | Filename encoding | **文件名编码** | 编码 | **重要**：与 Windows 互通 |
| | Cross-platform (Windows) | **Windows 兼容** | 跨平台 | 显式 “Windows 兼容” 让用户秒懂 |
| | Preview | **预览** | 预览 | |
| | Performance | **性能** | 性能 | |
| | Security | **安全** | 安全 | |
| | Privacy | **隐私** | 隐私 | |
| | Updates | **更新** | 更新 | |
| | Advanced | **高级** | 高级 | |
| | About | **关于** | 关于 | |

### 3. 容易写错/争议的术语, 显式选择

| 争议项 | 候选 | 我的推荐 | 理由 |
|---|---|---|---|
| “Archive” (n.) | 压缩包 / 归档 / 存档 | **压缩包 (主), 归档 (辅)** | 中文用户对 “压缩包” 认知零成本; “归档” 与 macOS “归档实用工具” 对齐, 但日常 90% 场景用 “压缩包” |
| “Extract” (v.) | 解压 / 展开 / 提取 | **展开 (主), 解压缩 (辅)** | macOS 原生用 “展开” (Finder “双击展开”); 避免 “解压” 偏 Windows |
| “Compress” (v.) | 压缩 | **压缩** | 无争议 |
| “Verify” (v.) | 验证 / 校验 / 测试 | **校验** | “测试” 歧义大; “校验” 精确 |
| “Repackage / Re-archive” | 重新打包 / 重新压缩 | **重新压缩** | 不造词 |
| “Mount DMG” | 挂载 / 装载 | **挂载** | macOS 原生 “挂载” |
| “Burn to disk” | 刻录 | **刻录** | 标准 |
| “Handoff” (Apple 接力) | 接力 | **接力** | Apple 官方译 |
| “Quick Look” | 快速查看 / 速览 | **快速查看** | macOS 官方译, 不要自造 |
| “Liquid Glass” | 液态玻璃 / 液体玻璃 / Liquid Glass | **Liquid Glass (不译)** | Apple 官方未给中文译名, 直用, 首次出现可加 “（Apple Liquid Glass）” 副标 |
| “DMG” | 磁盘镜像 / DMG 文件 | **磁盘镜像 (DMG)** | 首词中文, 缩写括注 |
| “ISO” | 光盘镜像 / ISO 镜像 | **光盘镜像 (ISO)** | 同上 |
| “Apple Silicon” | Apple 芯片 / M 系列芯片 | **Apple 芯片 (Apple Silicon)** | 双语并列, 方便中英搜索 |
| “Sandbox” | 沙箱 / 沙盒 | **沙盒** | macOS 中文偏 “沙盒” (Xcode 译); 选 “沙盒” 保持 Xcode 上下文一致 |
| “Notarization” | 公证 | **公证** | Apple 官方译 |
| “Code signing” | 代码签名 | **代码签名** | 标准 |
| “Path traversal” | 路径遍历 / Zip Slip | **路径越界** | 用户语言, 不暴露 “Zip Slip” 术语 |
| “Symlink” | 符号链接 / 软链接 / 软链 | **符号链接 (软链接)** | 双名并列, 兼容老用户 |
| “Resource fork” | 资源分叉 / 资源叉 | **资源派生 (Resource Fork)** | Apple 官方译为 “资源派生” (旧译 “资源分叉”) |
| “AppleDouble” | AppleDouble / `._*` 文件 | **AppleDouble 文件** | 业内通用, 首次出现可加 “（俗称 “点下划线” 文件）” |

---

## 原生 macOS 工作流评审

### A. 早期架构假设的逐条评估

> 引用自 research §Early Architecture Hypothesis, 1–5 条, 我逐条判评估。

**A1 “SwiftUI document-style shell with AppKit bridges where Finder-grade table, drag/drop, Quick Look, menu, and window behavior require them.”** → **基本可行, 但应补充**：① 工具栏在 macOS 26 Liquid Glass 下应优先用 `NavigationSplitView` + `Inspector` 三栏布局, 表视图放中间, 详情/预览/校验信息放右侧 Inspector。② “Document-based app” 适合“打开一个压缩包”场景, 但**批处理/任务队列场景天然不是 document-based**, 需要“命令式 + 文档式”双模式：单文件浏览/编辑走 Document, 多文件/任务面板走普通 Window。**架构假设未明说这两种模式的边界**。

**A2 “A format-capability registry routes operations to isolated engines rather than pretending all formats support the same actions.”** → **正确且关键**。建议显式定义 `FormatCapabilities` 协议, 至少含 `canCreate / canEditInPlace / canEditByRewrite / canEncrypt / canStream / supportsUTF8Filenames / supportsSymlinks / supportsResourceFork` 等布尔位。**UI 层根据这些位动态启用/灰显按钮** (例如 “在 7z 上点 ‘重命名条目’ 时, 按钮文字应变为 “重命名 (需重建压缩包)” 并提示耗时, 而不是直接灰掉)。这是商业产品与 Keka 的体验分水岭。

**A3 “ZIP path should favor a native Swift implementation for edit/interoperability; broad extraction and 7z path should use audited native libraries/engines behind a C/Objective-C++ boundary.”** → **赞同**。ZIPFoundation (MIT) 是合理选择, 但需补 ① ZIP 64 支持、② AES 加密（ZIPFoundation 截至研究时 AES 能力有限, 需验证）、③ GP Bit 11 (UTF-8) 写入路径——这三件是 Windows 互操作核心。7z 路径上 7-Zip LZMA SDK (C++) 是合理底层, 但**许可与 `unrar` 同源风险需法务双确认**。

**A4 “All modification is staged as a transaction: materialize changed entries in an app-managed workspace, stream-rewrite to a sibling temporary archive, verify, fsync, then atomically replace while retaining recovery metadata.”** → **赞同, 是商业品质分水岭**。补充：① 崩溃恢复应在 `~/Library/Application Support/<bundleID>/recovery/` 下保留 `{原文件, 临时文件, journal.json}` 三元组, journal 含 ops 序列与 sha256, 启动时检查 journal。② “原子替换” 在 APFS 上可用 `rename(2)`, 在外置 exFAT/FAT32 上无原子性, **架构应检测目标卷文件系统并降级提示**。③ “retaining recovery metadata” 时间窗要可配置（默认 7 天? 30 天?）, 不能永久保留, 否则吃磁盘。

**A5 “Preview extracts only the selected entry into a quarantined cache with byte/time/type limits and Quick Look integration.”** → **赞同, 但要写明配额默认值**：单条 50 MB? 200 MB? 总缓存 1 GB? 时间 24 h? 这些是 UX 决策不是技术细节, 应当写入 spec。**Liquid Glass + Reduce Transparency 模式下, Quick Look 面板材质需验证仍可读**。

**A6（隐含）“Cross-platform export preset strips macOS-specific metadata.”** → 已在 R4 提出, 双向都做。

### B. 缺失的关键 macOS 集成点

1. **Services 菜单 / 右键服务** —— Finder 右键 → “服务 → 用 XX 压缩 / 展开到此处” 是 macOS 高频路径, 架构假设未提。
2. **Share Extension** —— 微信/邮件里点击附件 → “用 XX 打开” 也应可。**App Sandbox 路线要求 Share Extension 单独 target**。
3. **Quick Look 扩展 (qlgenerator)** —— 不仅是“调用 Quick Look”, 而是**自己提供 qlgenerator 让 Finder 选中 .zip/.7z 就能空格预览**。这是 BetterZip 的强项, 也是“原生”标签的核心体现。
4. **Finder Sync Extension** —— 侧栏直接显示在 iCloud / Downloads 下的压缩包状态徽章 (例如 “展开中” 小图标)。
5. **Touch Bar / 控制中心** —— 现代 Mac 多无 Touch Bar, 但 Magic Key + 焦点功能可绑, v1 可不做, **应明确列为 v2 评估**。
6. **Spotlight 索引** —— `.zip` 内文件若被解压到临时区, Spotlight 能否索引需手动 `mdimport` 触发, 商业体验加分项, v1 可不做。
7. **桌面通知 (UNUserNotificationCenter)** —— 长任务完成/失败必须系统通知, 不是应用内 toast。
8. **Stage Manager / 窗口恢复** —— macOS 26 默认开启, 架构应支持多个压缩包多窗口 + 状态恢复。

### C. Liquid Glass / macOS 26 兼容性

(以下 Liquid Glass API 名称为**推断**, Codex 须以 Apple 官方文档为准, 我未实时抓取 https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass。)

- 最低系统目标 = **macOS 26** (Liquid Glass 强制), 这砍掉旧系统用户, **须作为商业决策让用户拍板**。
- 关键 modifier：`.glassEffect()` / `.glassEffect(.regular.interactive())` (推断命名), 容器首选 `GlassEffectContainer` (推断) 包裹多个子元素以提升 GPU 性能。
- 关键容器：`NavigationSplitView` + `Inspector` 是 macOS 26 三栏首选。
- Reduce Transparency 自动降级, **必须测试**; Reduce Motion 下应禁用弹性动画。
- Dark Mode / Tinted 模式: Liquid Glass 自适应, 但**用户自选强调色**应在偏好设置中允许。
- Dynamic Type (macOS 26 “Larger Text”): 所有 UI 字号须用 `Font` semantic 样式而非硬编码 pt。

### D. 工作流层面 (Chinese-first)

中文用户工作流中三个细节, research 没覆盖：

1. **微信/钉钉附件默认行为**：默认双击 zip 在 macOS 上调用 “归档实用工具” 展开, 用户在 QQ/微信里点 zip 期望“直接看到内容列表”而非“展开到下载文件夹”。**应提供 “默认双击行为” 偏好设置**（在 XX 中打开 / 展开到子文件夹 / 询问）。
2. **微信文件传输助手的中文长文件名截断**：中文 Windows 端发来的 zip 内常含 GBK/UTF-8 混合, 缺省 macOS 行为在 Finder 显示问号方块, **架构必须实现“编码自动检测 + 修正” 显式 UI**（不是默默修复, 是提示用户 “已修正 3 个文件名编码”）。
3. **百度网盘/阿里云盘下载的 zip 命名规则**：常含全角符号、`【】` 括号, 排序/搜索易错。**侧边栏的“按名称排序”必须用中文 locale collation** (拼音), 不要用 Unicode 码点。

---

## 格式与兼容性风险

### 1. 格式矩阵的批判

> 引用 research §Confirmed User Requirements provisional format baseline。

| 格式 | 创建 | 展开 | 浏览 | 编辑 | 加密 | 评估 |
|---|---|---|---|---|---|---|
| ZIP | ✅ | ✅ | ✅ | ✅ (in-place) | ✅ (AES) | **核心, 全功能必须做扎实** |
| 7z | ✅ | ✅ | ✅ | ⚠️ (rewrite-only) | ✅ (AES-256) | “编辑” 须区分 in-place vs rewrite, UX 必明示 |
| TAR | ✅ | ✅ | ✅ | ⚠️ (rewrite-only) | ❌ | tar 本就不支持加密, 期待管理 |
| GZIP | ✅ (on tar) | ✅ | ✅ | ⚠️ | ❌ | |
| BZIP2 | ✅ | ✅ | ✅ | ⚠️ | ❌ | |
| XZ | ✅ | ✅ | ✅ | ⚠️ | ❌ | |
| Zstandard | ✅ | ✅ | ✅ | ⚠️ | ❌ | 现代选项, 中文用户认知低, 文档要解释 |
| RAR | ❌ | ✅ | ✅ | ❌ | ❌ (解压) | **R1 致命项**：彻底不要做创建, 不要“if exists”模糊 |
| DMG | ❌ | ✅ (裸提取) | ✅ (挂载) | ❌ | ❌ | R5 已述, 挂载 vs 裸提取两条路 |
| ISO | ❌ | ✅ | ✅ | ❌ | ❌ | 类似 DMG |

**关键修订**：把 7z/TAR/… 的 “edit” 改成 “rewrite-edit”, UI 中按钮提示 “重建并替换”。

### 2. Windows 互操作风险

- **ZIP GP Bit 11 (UTF-8) 是底线**。Windows 11 22H2+ 的 Explorer 才默认尊重; 老 Windows / 7-Zip 老版本要单独验证。**必须做双向 fixture**：macOS 出 → Windows 11 Explorer + 7-Zip + WinRAR 看;Windows 来 → macOS 看。**夹具中必须含**：纯中文名、纯日文名、混合中英、Emoji、繁体、左右拼音声调符号、超长名 (240+ 字符)、含空格、含全角符号。
- **ZIP 加密**：AES-256 Windows 11 24H2 才默认; WinRAR / 7-Zip 早就支持。**应同时支持 legacy ZipCrypto (仅供兼容) 并在 UI 上显式标注 “此格式安全性较低, 仅供兼容”**。
- **7z 加密**：AES-256 Windows 7-Zip / WinRAR 都支持, 互通良好。
- **NTFS 备用数据流 (ADS)**：Windows 文件可携带 ADS (`:Zone.Identifier`), macOS 看不到但解压会丢失。**应在 settings 里提供 “保留 Zone.Identifier 元数据到 xattr” 选项**（属于 v2 评估, v1 可不做但要明示）。
- **路径分隔符**：Windows 路径用 `\`, 压缩包条目名应统一 `/` (POSIX), 但 Windows 端某些工具会写入 `\`。**解压时需检测并规整**。

### 3. 跨平台/多语言文件名风险

- **ZIP 历史用 CP437**, Windows 简体中文系统用 CP936, 繁体用 CP950, 日文用 CP932, 韩文 CP949。**自动检测** (libarchive / ZIPFoundation 是否实现需验证) 容易误判。**产品策略：默认用 UTF-8 (GP Bit 11) 写出, 读取时**：
  - 优先用 Info-ZIP “Language encoding flag” (GP Bit 11) 决定 UTF-8
  - 否则按系统区域语言猜（中文系统→CP936/CP950 依语言, 失败回退 UTF-8 强猜）
  - **必须给用户 “重选编码” 入口**, 因为猜错是常态
- **NTFS/HFS+ 大小写敏感差异**：默认按大小写不敏感, **不要默默做 case-only rename** (会丢数据)。
- **Emoji 与变体选择符 (ZWJ sequences)**：Apple 设备发的 zip 可能含 👨‍👩‍👧 等 ZWJ 家庭 Emoji, Windows 显示为单字符或乱码, **不要在导出时强行拆 ZWJ**。

### 4. 安全/许可风险

- **7-Zip LZMA SDK 许可** = public domain, 但 7-Zip 整体 = LGPL + unRAR 限制。**若用 7-Zip 完整源码需逐文件审查**; 只用 LZMA SDK (剥离) 更安全。
- **libarchive** = BSD-style, 但其 read-path 集成 unrar 时受 unrar license 约束。**商业分发必须**:
  - 选项 A：只打包 libarchive 不带 unrar 读路径, RAR5 读取用另外的许可清理过的实现 (MacPaw UnRAR 商业许可? 需询价)
  - 选项 B：动态链接, 终端用户在 App Store 外部自行安装 unrar
  - **R1 必须在 spec 阶段给出选项决定**
- **MacPacker (GPL-3.0) 仅作产品参考, 不能复制代码进闭源项目**, 这一点 research 已说, 在架构里再次强调。
- **App Sandbox** 下不能 `exec` 外部 CLI, 故 “透传系统 rar” 路线在 MAS 不可行, **直分发才行**。

### 5. 性能/资源风险

- **解压炸弹 (decompression bomb)** 防御：每条解压后大小限制, 总大小限制, 压缩率阈值告警 (e.g. > 100x 警告)。
- **超大单文件** (50 GB+) 流式处理, 内存峰值必须可证明 < 200 MB。
- **APFS 克隆 / 硬链接**：macOS 端备份的 zip 内常含硬链接, **跨平台时硬链接是变成两份还是单份, 是 UX 决策**。
- **Time Machine 排除**：`~/Library/Application Support/<bundleID>/` 默认不被 TM 备份, 临时解压区应在 `Caches/` 下, 崩溃恢复区应在 `Application Support/` 下, **二者路径必须分清**。

---

## 必须修订项

按优先级, 全部给 Codex 写入设计 spec：

| 编号 | 修订内容 | 接受标准 |
|---|---|---|
| M1 | RAR 创建三选一明确, 写进 spec, 不留 “if exists” 模糊 | spec 中出现 “RAR 创建: 不支持 / 仅限外部 CLI / 商业许可 (选一)” |
| M2 | ZIP Windows 互通必须含 “GP Bit 11 写入” 与 “Unicode-only 文件名 fixture” 双向测试 | 设计 spec 含 “Windows 互通验收夹具” 章节, 含 ≥ 8 个文件名场景 |
| M3 | 7z/TAR 家族 “编辑” 须在 UI 区分 “in-place” (无, 除 ZIP) vs “重建” (其他), 按钮文字随格式动态变 | FormatCapabilities 协议定义 + UI 文案表 |
| M4 | 双向 AppleDouble/`.DS_Store` 处理：导出剥离 + 导入恢复, 各自有显式开关 | spec 双向各列 1 段 |
| M5 | DMG “挂载” vs “裸提取” 二选一 UI, 默认挂载, 裸提取在高级 | DMG 章节有 “UX 双路径” 段 |
| M6 | 架构假设按 sandbox-on / sandbox-off 两套并列写, 标每条假设在哪套下成立 | spec 出现 “Sandbox 模式矩阵” 表格 |
| M7 | 最低系统 = macOS 26 (Liquid Glass), 写入 spec 顶部, 由用户拍板商业影响 | spec 顶部含 “最低系统” 一行 + 影响说明 |
| M8 | 中文文件名排序用 locale collation (拼音), 设置中可切 (Unicode 码点 / 拼音 / 笔画) | 设置页 “文件名排序” 选项 |
| M9 | a11y 验收清单：VoiceOver / Reduce Transparency / Reduce Motion / Larger Text / Keyboard-only | 验收阶段含 a11y 章节 |
| M10 | 杀毒/恶意扫描 v1 不做, v2 评估, 写明边界 | spec 含 “v1 范围外” 章节 |
| M11 | 中文术语表(本评审 §2) 全部采纳, “压缩包/归档、展开/解压缩” 双轨制 | spec 全文不出现 “解压” 一词单独使用, 全用 “展开” 动词 |
| M12 | 错误信息必须带原因 (R 类), 不出现裸 “失败” | 错误文案表共 ≥ 16 条 |
| M13 | 进度状态必须区分 “准备/压缩/展开/校验/加密/写入/收尾” 7 阶段 | 进度状态机图 |
| M14 | “密码本” 功能 v1 必须做, 用 Keychain 或 App 自有加密存储二选一明确 | 加密章节含决策 |
| M15 | Quick Look qlgenerator + Finder Sync Extension v1 必须做, 否则不叫 “原生” | 集成章节 |
| M16 | 多窗口/状态恢复 (Stage Manager) 必须支持 | 架构假设新增 |
| M17 | 临时区与崩溃恢复区路径分离 (Caches vs Application Support) | 架构假设新增 |
| M18 | Windows 端 Zone.Identifier / ADS 处理策略, v1 显式说明 | 设置项 “保留 Windows 元数据” 默认关 |
| M19 | Liquid Glass 在 Reduce Transparency 下行为, 必须在 QC 验收 | 视觉 QC 清单 |
| M20 | 编码自动检测失败时给用户 “重选编码” UI, 不静默 | 解压向导含 “编码” 步 |

---

## 仍需用户确认的决策

以下 9 项是**用户拍板级**决策, 不是 agent 能决定的。请 Codex 把这些交给用户：

1. **D1 — 最低系统目标**：macOS 26 (砍掉 14/15 用户, 获 Liquid Glass) vs macOS 14 (兼容更广, 视觉降级)？
2. **D2 — 分发渠道**：直分发 (dmg + 公证) / Mac App Store / 两者并行？sandbox 限制对 7z helper / rar CLI 透传有结构性影响, 选错会推翻 M6。
3. **D3 — RAR 创建策略**：仅读 / 透传外部 CLI / 商业许可谈 win.rar GmbH？三选一。
4. **D4 — 加密矩阵范围**：v1 是否包含 ZIP AES-256 / 7z AES-256 / 头加密 (文件名加密)？legacy ZipCrypto 兼容是否做？
5. **D5 — 商业模式**：一次性买断 / 订阅 / freemium？这影响功能分级 (v1 = 浏览+展开, Pro = 创建+加密+批处理) 还是全部 v1 全功能？
6. **D6 — 中文界面是否独占**：v1 是否只出中文? 多语言 (英/日/繁中) 是 v1 还是 v2? 资源 (文案、图标、术语表) 影响很大。
7. **D7 — “密码本” 存储方案**：macOS Keychain (系统级) vs App 自有 AES 加密存储 (跨设备同步不友好但跨 App 隔离)？
8. **D8 — 名称 (App + 套件)**: 中文商业产品名是什么? “XX 压缩 / XX 归档 / XX 解压”? 这影响 App Store 搜索与品牌, **早决定好, 后期改名成本高**。
9. **D9 — Quick Look qlgenerator 行为**：空格预览 zip 是 “显示条目列表” (Finder 风格) 还是 “自动展开首层”? 后者更省事但可能违反用户对 “预览 ≠ 真的解压” 的预期。

---

## LOOP 记录

### 动作
1. 读取 SOUL.md（lines 1–571）确认 Codex 委托边界与本评审角色 (sub-venue chair, advisory)。
2. 并发读取任务清单内的三个源文件 (context / plans / research), 一次性抓全, 避免后续往返。
3. 列出工作区文件确认不读其他 5 份参与者输出以保持独立性。
4. 起草并写入本交付物到 `runs/conference/mac_archive_app/participant_aishuo_minimax.md`。

### 观察
- research packet **没有用户场景层**——只列了“产品能力”未列“谁在什么时候为了什么用它”, 这是商业产品文档的常见盲点。
- research 把 7z 列入 “full workflow: …edit” 而未澄清 7z 编辑 = 全包重写, 是过度承诺。
- 早期架构假设 5 条均为合理技术判断, 但**没覆盖 sandbox 模式矩阵、Keychain 集成、qlgenerator、Finder Sync、Share Extension、Stage Manager** 等 macOS 原生性核心点。
- 没有任何关于 **a11y / 国际化 / 排序策略** 的约束。
- 没有任何关于 **App 命名 / 商业模式 / 多语言时机** 的产品决策。
- “解压”一词是中文用户常用, 但 macOS 原生用 “展开”, 与 Apple 自身术语表对齐更有利。

### 评估 (相对假设)
- 假设 “Liquid Glass 强制 macOS 26” 推断, 须 Codex 校准；若 research 已用 latest 表述, 则推断成立。
- 假设 “ZIPFoundation AES 能力有限” 推断, 须 Codex 校准; 实际需查 ZIPFoundation README/CocoaPods 页面。
- 假设 “macOS 14/15 占装机量 30-40%” 推断, 须用户拍板而非 agent 决定。
- 术语表的选择 (压缩包/展开/校验) 来自**对 Apple 简体中文官方用词 + 7 年 macOS 客户体验的常识**, 不是引用证据, 但置信度高。

### 评审中做的修订 (vs 初稿)
- 初稿把 “解压” 列入主推词, 修订后改为 **“展开” 主 / “解压缩” 副**, 与 macOS 原生对齐。
- 初稿把 RAR 写作 “if exists”, 修订后改为**三选一强制决策 (M1 + D3)**, 因为模糊表述会推迟到发布前夜爆发。
- 初稿 “格式矩阵” 直接复述 research, 修订后**把 7z/TAR 家族的 “edit” 显式标 “rewrite-only”** (M3) 以正视听。
- 初稿没把 a11y 单独提, 修订后**新增 M9 + D 系列 9 项决策** (其中 D 系列是产品/商业级, 非技术级)。
- 初稿没区分 “临时区 vs 恢复区路径”, 修订后**新增 M17** (Time Machine 备份语义依赖此区分)。

### 不确定 / 移交
- Liquid Glass 具体 API modifier 名称 (`.glassEffect` 等) **未实时抓取 Apple 文档, 视为推断, 不作为 spec 强制条款**。Codex 须以 Apple 官方文档为准。
- “macOS 26 在中国装机量” 无可靠数据, **不写死** 商业影响数字, 留给用户拍板 (D1)。
- 其他 5 份参与者输出未读, 不知是否已触及相同问题；如出现冲突/互补, 由 Codex 仲裁。本评审完全独立, 不依赖他人输出。
- 中文术语表的**最终批准**须 Codex 把本表 + GLM-5.2 表对比后, 由用户签字。SOUL.md §5 “Review Task Records” 提醒: 此评审随上下文压缩后, 唯一可恢复锚是本文件本身, 已在文件内嵌全部决策与修订理由。

### 推荐的下一环 (for Codex)
- **立即**：把 D1–D9 交给用户拍板 (其中 D1/D2/D3/D5 是阻塞决策, 会反向影响 spec 章节)。
- **并行**：让 Qwen / mimo / deepseek-v4-flash 跑同一份术语表对比, Codex 取多数共识 + 用户签字。
- **下一步**：Codex 拿本评审 + GLM-5.2 评审 + 用户决策, 写 design spec v0.1, 重新进入本评审做 “批判修订” 循环（如果 spec 偏离本评审建议, 本评审会被召回复核）。
- **不要**：在本评审完成前启动代码脚手架 (per `codex_main_venue_mac_archive_app.md` 第 5 步, 必须先获设计批准)。
