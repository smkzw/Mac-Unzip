# buddy GLM-5.2 技术架构 QC-2

> Provider route: Hermes `buddy` fallback, model `GLM-5.2`. The primary `aishuo/GLM-5.2` route failed after three API retries and five stale-response checks (per conference context loop log). This document is the fallback QC-2 pass. It does not claim the aishuo route succeeded.

## 已读取输入与边界

**SOUL.md 状态：** 已完整读取 `/Users/smkzw/.hermes/SOUL.md`（571 行）。确认遵守 Codex 委派规则：仅咨询角色，不执行生产写入，不执行可视化/浏览器/PPT 最终验收，分离证据与推断，标注不确定性。

**已读取任务文件（全部 6 个）：**

1. `context/mac_archive_app_conference_context.md` — 会议上下文、范围、成功标准、风险边界、循环日志。
2. `research/2026-07-11_initial_landscape.md` — 产品/框架/格式/许可证证据包。
3. `research/2026-07-11_engine_distribution_matrix.md` — 引擎能力矩阵与分发约束。
4. `research/2026-07-11_windows_interoperability_contract.md` — Windows W0/W1/W2 互操作合同。
5. `research/2026-07-11_architecture_options.md` — 三条架构路线 A/B/C 及推荐域架构。
6. `reviews/codex_conference_mac_archive_app_review.md` — Codex 主会场审查裁决。

**工作边界：**
- 工作目录限于 `/Users/smkzw/Documents/AI Products`。
- 不浏览网络、不调用外部服务、不编辑源码、不创建远程仓库、不上传/部署。
- 只写入一个输出文件：`runs/conference/mac_archive_app/qc_architecture_buddy_glm.md`。
- 不执行或授权任何发布动作。

**角色声明：** 本文是 Codex 主会场主持下的第二轮架构 QC 的敌对技术审查。所有结论为咨询性质，最终决策权归 Codex。

---

## 路线选择结论

### 推荐路线：Option A — 能力路由混合核心

**证据依据：**

- `architecture_options.md` 中 Option A 满足用户已批准的完整格式矩阵：ZIP 全工作流（含加密/编辑）、7z 全工作流（含加密）、TAR 家族创建/提取/浏览、RAR 提取/浏览、DMG/ISO 只读浏览、RAR 创建（通过可选外部 RARLAB）。
- `engine_distribution_matrix.md` 验证了 minizip-ng 244/244 测试通过、libarchive 1005/1005 测试目标通过，且 minizip-ng 原生支持 ZipCrypto + WinZip AES，libarchive 覆盖 TAR/Zstandard/ISO 流式读写，7zz 覆盖加密 7z 创建/提取和加密 RAR 提取。
- Option B（helper 中心）被 architecture_options.md 自身评估为"不适合产品级质量架构"，因为进程启动/文本解析/版本耦合影响所有常见操作，且流式预览/进度/取消/结构化错误较弱。
- Option C（纯进程内库）被明确拒绝，因为它无法满足加密 7z 创建/提取和加密 RAR 提取的已批准需求——这属于静默缩减用户已批准范围。

**推断：** Option A 是唯一不缩减已批准范围且不退化为单 helper 耦合的路线。

**不确定性：**
- 三引擎族的差异测试和依赖审计负担是真实的成本，尚无具体的差异测试计划。
- LGPL 合规计划在 Direct/OpenSource 构建配置下的具体实现路径尚需细化（见下文第 7 节）。
- 用户尚未就分发渠道做出最终决定（Codex 审查指出"分发渠道是下一个决策"），但这不改变架构路线选择，因为三种构建配置共享同一核心。

### 不接受任何静默缩减范围的替代路线

- Option C 的缺陷是根本性的（功能缺失），不能通过后续迭代弥补。
- Option B 的缺陷是架构性的（单点耦合、弱结构化反馈），在本地使用场景下可接受但不符合用户定义的"商业化前端/后端能力与质量"基准。
- 若未来发现 7zz helper 的 LGPL 合规成本不可接受，应先升级到 Codex 重新评估范围，而不是静默切换到 Option C。

---

## 模块与引擎边界缺陷

### D1. 引擎所有权重叠未被形式化

**证据：** `engine_distribution_matrix.md` 的能力路由表显示多个格式存在引擎重叠：
- ZIP 浏览/创建/编辑：minizip-ng（首选）+ libarchive/7zz（备选）
- ZIP AES/ZipCrypto：minizip-ng（首选）+ libarchive/7zz（备选）
- RAR 浏览/提取：7zz（首选）+ libarchive（备选，仅未加密/有限情况）
- ISO 浏览/提取：libarchive（首选）+ 7zz（备选）

**缺陷：** architecture_options.md 提到"重叠读取器可能产生分歧，因此路由必须确定性"，但没有定义确定性路由的决策规则。当 minizip-ng 和 7zz 都能处理同一个 ZIP 时，谁优先？当 libarchive 和 7zz 都能读取同一个 RAR 时，谁优先？这些决策不能留给运行时隐式行为。

**必须修订：** ArchiveCapabilityRegistry 必须为每个 (格式, 操作) 元组定义明确的优先级链和降级条件。优先级选择应基于：
1. 引擎对该格式的原生支持程度（创建 > 编辑 > 只读）；
2. 加密支持范围；
3. 测试覆盖率证据；
4. 性能特征（进程内库 vs 外部 helper）。

降级到备选引擎的条件必须显式记录（如"主引擎返回格式错误时降级"），而非隐式捕获所有异常。

### D2. 7z "编辑"语义未定义

**证据：** `engine_distribution_matrix.md` 能力路由表写"7z browse/create/edit/encrypt | embedded ARM64 7zz helper"，并在注释中写"7z edit is archive rebuild/update, not cheap in-place mutation"。`initial_landscape.md` 对 libarchive 明确指出"in-place modification and random access are explicitly outside libarchive's design"。

**缺陷：** architecture_options.md 的 ArchiveTransaction 层描述了通用的"staged rewrite + verify + fsync + atomic replace"事务模型，但没有区分不同格式的编辑成本层级。7z 的"编辑"实际上是完整重建归档，对于大型 7z 文件可能耗时数分钟。UI 层没有定义如何向用户传达这种成本差异——用户执行"删除一个文件"操作时，ZIP 和 7z 的时间复杂度可能差几个数量级。

**必须修订：**
- ArchiveCapabilityRegistry 必须为每个 (格式, 操作) 返回预估成本类别（如 `in-place-append`、`full-rebuild`、`streaming-rewrite`）。
- UI 层必须在执行高成本编辑操作前显示预估时间和临时空间需求。
- 事务层必须对 full-rebuild 操作设置可取消的进度反馈，且取消不会损坏源归档。

### D3. minizip-ng 编辑语义与 ZIPFoundation 不同，混合使用有风险

**证据：** `initial_landscape.md` 详细描述了 ZIPFoundation 的编辑语义（"adding writes before the existing central directory; removal writes a temporary archive then replaces the original"）。`engine_distribution_matrix.md` 评估 minizip-ng 支持"append/remove entries, raw entry copying"。

**缺陷：** 如果 ZIP 路径使用 minizip-ng 而非 ZIPFoundation，但 architecture_options.md 的引用仍以 ZIPFoundation 的编辑语义为参考，两者的事务模型可能不一致。minizip-ng 的 append 是否也写入中央目录之前？remove 是否也生成临时文件？这些语义差异直接影响 ArchiveTransaction 的包装方式。

**必须修订：** 如果 ZIPFoundation 仅作为"参考或可选简单 ZIP 读取器"（engine_distribution_matrix.md 评估），则 architecture_options.md 中引用 ZIPFoundation 编辑语义的部分应替换为 minizip-ng 的实际语义，或明确标注为通用模式参考。事务包装必须以实际使用的引擎行为为准。

### D4. Helper 隔离边界缺少进程生命周期定义

**证据：** `architecture_options.md` 安全层写"Helper runner uses no shell, explicit argv, `--` end-of-options, sanitized environment, bounded stdout/stderr, timeout/cancel and executable identity verification"。`engine_distribution_matrix.md` 写"7zz helper... All arguments must use end-of-options protection, controlled working directories, bounded output, cancellation, and structured error mapping"。

**缺陷：** 这些描述覆盖了单次调用的安全约束，但没有定义 helper 进程的生命周期管理：
- helper 是每次操作启动一个新进程，还是常驻？
- 常驻 helper 如何处理取消操作？进程内状态如何清理？
- 多个并发操作是否共享一个 helper 进程？如果是，如何隔离工作目录和状态？
- helper 崩溃后如何恢复？是否影响正在进行的 ArchiveTransaction？
- helper 的 stdout/stderr 有界缓冲区满后的行为是什么？阻塞、丢弃、还是终止？

**必须修订：** 定义明确的 helper 进程模型：
1. 每次操作启动独立进程（最简单、最安全，但启动开销大）；或
2. 常驻进程池 + 操作级隔离（性能好，但需要状态清理和崩溃恢复协议）。
无论哪种，都必须定义：取消信号传播机制、崩溃后事务回滚协议、并发限制、缓冲区满行为。

### D5. LGPL 合规假设未区分构建配置

**证据：** `engine_distribution_matrix.md` 写"7-Zip LGPL... closed commercial distribution still needs an LGPL-compliance plan and exact source/notice package"。`architecture_options.md` 定义三种构建配置：Local（ad-hoc 签名，可能发现本地 7zz）、Direct（Developer ID + 公证，可能捆绑签名 ARM64 7zz helper）、OpenSource（源码分发）。

**缺陷：** 三种构建配置的 LGPL 合规义务不同，但文档没有区分：
- **Local 配置：** 如果只是发现用户已安装的 7zz 而不捆绑，则不触发 LGPL 分发义务。但如果本地构建中链接了 minizip-ng 或 libarchive，这些库的许可证（zlib / BSD）仍然需要在 about/credits 中声明。
- **Direct 配置：** 捆绑 7zz 二进制 = LGPL 分发。需要：提供对应源码、声明修改（如有）、包含许可证文本。如果 7zz 静态链接了 UnRAR 受限代码（`7z.dll` mixes LGPL, BSD, and UnRAR-restricted decompression code — engine_distribution_matrix.md），则需要额外说明 UnRAR 仅用于解压缩、不用于逆向 RAR 压缩算法。
- **OpenSource 配置：** 源码分发需要确保所有依赖的许可证兼容，且 SPDX 组件清单完整。

**必须修订：**
- 为每种构建配置生成明确的许可证义务清单。
- Direct 配置必须定义 7zz 二进制的精简构建方案（只编译需要的编解码器，避免不必要组件的许可证负担）。
- OpenSource 配置必须定义可复现构建脚本和 SPDX 组件清单格式。

### D6. RARLAB `rar` 外部 provider 的发现/验证/回退链不完整

**证据：** `engine_distribution_matrix.md` 写"RAR create | user-installed licensed RARLAB `rar` | none | Local provider only; never copy it into a distributable bundle without written rights"。`architecture_options.md` 写"optional external RARLAB `rar`: RAR creation after provider/license/live-probe checks"。

**缺陷：** "provider/license/live-probe checks"未被展开：
- 如何发现 `rar`？搜索 PATH？已知路径？用户手动指定？
- 如何验证许可证？RARLAB 许可证是 shareware，没有机器可读的许可证文件。是仅显示声明让用户确认，还是检查文件签名/版本？
- "live-probe"是什么？创建一个测试 RAR 然后验证？如果 probe 失败如何回退？
- 三种构建配置下的发现行为是否一致？Local 可能允许 PATH 搜索，Direct/OpenSource 是否也允许？
- 如果用户在操作过程中卸载了 `rar`，已创建的 RAR 文件的完整性如何保证（应该没问题，但 UI 状态如何更新）？

**必须修订：** 定义 RARLAB provider 的完整生命周期：
1. 发现策略（路径优先级：用户设置 > PATH > 已知安装路径）。
2. 验证步骤（版本检查 + 试创建 + 试读取）。
3. 失败回退（UI 明确告知 RAR 创建不可用，不静默降级）。
4. 三种构建配置下的行为差异。

### D7. DMG 操作边界与 macOS 机制耦合未定义

**证据：** `architecture_options.md` 写"public macOS disk-image mechanisms: DMG read-only browse/mount workflow"。`engine_distribution_matrix.md` 写"DMG browse/mount/extract | public macOS mechanisms and isolated system workflow | libarchive/7zz only where format support is proven | Mount and raw extraction are separate UX actions"。

**缺陷：** DMG 的 mount 操作涉及系统级 `hdiutil` 调用，其安全性和隔离性约束与 7zz helper 不同：
- mount 操作创建一个虚拟块设备，可能触发系统安全策略（Gatekeeper 对挂载镜像的隔离标记）。
- mount 的 DMG 可能包含可执行内容，与"never execute extracted content automatically"不变量冲突。
- mount 失败、权限不足、或 DMG 损坏时的错误处理未定义。
- "isolated system workflow"是什么？是一个独立的 XPC 服务？还是直接在主进程中调用 `hdiutil`？

**必须修订：** DMG 操作必须作为独立的安全审计项，定义 mount 的隔离策略（是否在独立进程中执行、是否对挂载内容应用 quarantine）、卸载协议（崩溃后自动卸载）、以及与 libarchive/7zz 的 raw 提取路径的降级条件。

---

## 操作与安全不变量

以下为每个已提出操作和威胁场景推导的不变量和故障处理。标注 [E] 表示有源文件证据支持，[I] 表示推断，[U] 表示不确定性。

### 操作不变量

**O1. 创建归档 [E]**
- 不变量：输出文件写入成功后必须是目标格式的有效归档；写入失败时不留部分文件。
- 故障处理：写入临时文件 → 验证完整性 → fsync → 原子替换目标路径。磁盘满时在临时文件阶段失败，不创建目标文件。
- 缺口：architecture_options.md 未定义"验证完整性"的具体方法——是重新打开并列出条目？还是逐条校验 CRC？后者对大文件成本高。

**O2. 提取归档 [E]**
- 不变量：提取前检查每个条目的目标路径在用户指定目录内（防 Zip Slip）；不自动执行提取的内容。
- 故障处理：遇到恶意路径 → 报告冲突并跳过或提示用户选择（隔离/重命名/跳过）；遇到符号链接逃逸 → 拒绝或剥离符号链接。
- 缺口：对于 Windows 保留设备名（CON、PRN、AUX 等）和非法字符，提取时的处理策略未定义。这在 macOS 上提取不会触发，但如果目标是外接 NTFS/ExFAT 卷则需要处理。

**O3. 浏览归档 [E]**
- 不变量：浏览只读取归档元数据和目录结构，不提取文件内容到用户可访问的位置。
- 故障处理：归档损坏 → 报告损坏位置和可恢复范围；加密归档 → 提示密码，不暴力尝试。
- 缺口：浏览超大归档（10 万+ 条目）时的内存策略未定义。是否流式加载目录树？

**O4. 预览条目 [E]**
- 不变量：预览仅提取选中条目到应用管理的隔离缓存，受字节/时间/类型限制；通过 Quick Look 或安全内置查看器展示。
- 故障处理：条目超过大小限制 → 拒绝预览并提示用户手动提取；Quick Look 不可用 → 降级到内置文本/图像查看器。
- 缺口：隔离缓存的清理策略未定义——预览结束后立即删除？还是保留到应用退出？缓存的物理位置（沙盒容器 vs 临时目录）未定义。

**O5. 编辑归档（添加/删除/重命名/替换）[E]**
- 不变量：编辑不直接写入源归档；通过 staged rewrite + verify + fsync + atomic replace 事务完成；取消或崩溃时源归档不受影响。
- 故障处理：磁盘空间不足 → preflight 阶段失败；源归档在编辑期间被外部修改 → 检测变更并中止或提示用户；验证失败 → 保留源归档，丢弃临时文件。
- 缺口：源归档变更检测的具体机制未定义——是文件修改时间？inode？哈希？编辑过程中持续监听还是仅在 commit 时检查？

**O6. 修复归档 [E]**
- 不变量：修复尝试恢复损坏的中央目录或结构，不覆盖源文件；输出为修复后的新文件。
- 故障处理：修复失败 → 保留源文件，报告可恢复范围。
- 缺口：minizip-ng 的"central-directory recovery"能力的具体行为和限制未在源文件中展开。哪些类型的损坏可修复、哪些不可修复？

**O7. RAR 创建 [E]**
- 不变量：仅在 RARLAB provider 通过发现/验证/probe 后可用；provider 永不捆绑到任何分发产物中。
- 故障处理：provider 不可用 → UI 明确禁用 RAR 创建选项，不静默降级到其他格式；probe 失败 → 报告具体失败原因。
- 缺口：RAR 创建过程中的取消行为未定义——`rar` CLI 是否支持中断后清理？部分写入的 RAR 文件如何处理？

### 威胁场景不变量

**T1. 嵌套归档（archive within archive）[I]**
- 不变量：浏览嵌套归档时不应自动递归解压；用户必须显式选择进入嵌套层。
- 故障处理：检测到嵌套归档 → 显示为可展开节点但不自动提取；递归深度超过限制（建议 10 层）→ 拒绝进一步展开并提示。
- 缺口：源文件未提及嵌套归档处理策略。这是一个真实的攻击向量（Zip bomb 的常见变体）。

**T2. 敌对路径（Zip Slip / path traversal）[E]**
- 不变量：所有提取路径必须规范化后验证在用户指定根目录内。
- 故障处理：检测到 `../` 或绝对路径 → 拒绝、剥离恶意前缀、或提示用户选择。
- 证据：`architecture_options.md` 安全层明确提到"Prevent Zip Slip/path traversal"。

**T3. 符号链接逃逸 [E]**
- 不变量：归档中的符号链接不得指向用户指定目录之外的路径。
- 故障处理：检测到逃逸符号链接 → 拒绝创建、剥离符号链接、或降级为普通文件。
- 证据：`architecture_options.md` 安全层明确提到"symlink escape"。

**T4. 解压炸弹 [E]**
- 不变量：提取操作必须有总输出大小限制和压缩比监控；超过阈值时暂停并提示用户。
- 故障处理：检测到异常压缩比（建议 > 100:1）或总输出超过可用磁盘空间 → 暂停提取，提示用户确认或取消。
- 缺口：源文件提到"decompression-bomb"防御但未定义具体阈值和检测机制。是预扫描归档元数据中的未压缩大小？还是在流式提取时实时监控？

**T5. 外部文件变更 [I]**
- 不变量：编辑事务 commit 前检测源文件是否被外部修改；检测到变更则中止 commit。
- 故障处理：变更检测 → 保留源文件不变，提示用户源文件已被修改，询问是否重新加载。
- 缺口：见 O5 的检测机制缺口。

**T6. 磁盘满 [I]**
- 不变量：所有写入操作在开始前进行可用空间 preflight；运行中持续监控剩余空间。
- 故障处理：空间不足 → 在 preflight 阶段拒绝操作；运行中空间耗尽 → 中止操作，清理临时文件，保留源文件不变。
- 证据：`architecture_options.md` 事务层提到"free-space preflight"。

**T7. 崩溃 [E]**
- 不变量：崩溃后源归档必须保持完整；临时文件和 staging 区域在下次启动时被识别和清理。
- 故障处理：启动时检测未完成的 staging 文件 → 清理并报告；源归档未被原子替换 → 保持原样。
- 缺口：staging 文件的位置和命名约定未定义，导致崩溃恢复的检测机制无法被验证。建议使用确定性命名（如 `{源文件名}.archivestaging.{UUID}`）并在应用启动时扫描。

**T8. 用户取消 [E]**
- 不变量：取消操作必须终止正在进行的写入，清理临时资源，保留源归档不变。
- 故障处理：用户取消 → 发送取消信号到引擎/helper → 等待引擎确认终止 → 清理临时文件 → 恢复 UI 到操作前状态。
- 缺口：7zz helper 的取消机制——是发送 SIGTERM？还是通过 stdin 发送 `q` 命令？取消后 helper 进程是否保证不留下锁文件或临时归档？minizip-ng/libarchive 进程内取消是否安全？流式写入中途取消是否留下半写文件？

---

## Windows 与 Unicode 反证测试

### W0/W1/W2 审查

**证据核查：**

| 声明 | 源文件 | 证据状态 | 需要物理验证 |
|---|---|---|---|
| Windows 11 24H2 原生打开 ZIP/RAR/7z/TAR | `windows_interoperability_contract.md` 引用 Microsoft Support 文档 | [E] 文档级证据 | 是 — 需在实际 Windows 11 24H2 上验证 |
| Windows Explorer 不处理加密归档 | `windows_interoperability_contract.md` 引用 Microsoft 文档 | [E] 文档级证据 | 是 — 需验证加密 ZIP/7z 在 Explorer 中的行为 |
| 7z AES-256 + 加密头在 7-Zip 上可用 | `engine_distribution_matrix.md` 本地 7-Zip 26.01 ARM64 烟雾测试 | [E] 本地 macOS 端验证 | 是 — 需在 Windows 7-Zip 上验证跨平台读取 |
| ZipCrypto ZIP 兼容旧版解压软件 | `windows_interoperability_contract.md` W1 层定义 | [I] 基于格式标准的推断 | 是 — 需在 Windows Explorer + 旧版 WinZip 上验证 |
| UTF-8 bit-11 文件名在 Windows 上正确显示 | `initial_landscape.md` ZIPFoundation 源码验证 + `engine_distribution_matrix.md` minizip-ng 验证 | [E] 引擎级验证 | 是 — 需在 Windows Explorer/7-Zip 上验证中文/日文/阿拉伯文/emoji 文件名 |
| NFC 规范化避免 Windows 冲突 | `windows_interoperability_contract.md` W0 层定义 | [I] 基于文件系统语义的推断 | 是 — 需在 Windows NTFS/ReFS 上验证 NFC vs NFD 冲突行为 |
| TAR.ZST 在 Windows tar 上可用 | `windows_interoperability_contract.md` W2 层引用 Microsoft Learn tar 文档 | [E] 文档级证据 | 是 — 需验证 Windows 11 24H2 tar 是否实际支持 zstd |
| libarchive RAR 读取器可读取未加密 RAR4/RAR5 | `engine_distribution_matrix.md` + Codex 审查确认 | [E] 源码级验证 | 是 — 需在 Windows 上验证与 WinRAR 创建的 RAR 的互操作 |

**仍需物理 Windows 证明的声明清单：**

1. W0 ZIP（未加密 Deflate）在 Windows 11 24H2 Explorer 中的打开/列表/提取。
2. W0 ZIP 中多语言文件名（简繁中文/日文/韩文/阿拉伯文/emoji）在 Windows Explorer 中的正确显示。
3. W0 ZIP 中 NFC 规范化文件名在 NTFS 上不产生冲突。
4. W1 加密 7z（AES-256 + 加密头）在 Windows 7-Zip 中的列表/提取。
5. W1 ZipCrypto ZIP 在 Windows Explorer 中的行为（Explorer 是否提示密码？还是直接失败？）。
6. W1 AES ZIP 在 Windows 7-Zip/WinRAR 中的列表/提取。
7. W2 TAR.ZST 在 Windows 11 24H2 `tar` 命令中的提取。
8. RAR（7zz 创建或 RARLAB 创建）在 Windows WinRAR 中的列表/提取。
9. 分卷归档在 Windows 7-Zip/WinRAR 中的重组和提取。
10. macOS 创建的归档在 Windows 上提取后的文件哈希一致性。

**推断：** 当前所有 Windows 互操作声明均为文档级或引擎级证据。`windows_interoperability_contract.md` 自身也承认"A real Windows VM/device is not presently configured in this workspace, so the physical Windows rows remain open release gates"。这些是发布阻断项，不是设计阻断项——架构设计可以继续，但发布前必须完成物理验证。

### Unicode 字节保存与显示

**证据：** `architecture_options.md` 本地化和文件名层写"Preserve original entry bytes and decoded display name separately. Encoding heuristics never silently rewrite archive names; ambiguity is surfaced and user overrides are reversible"。`initial_landscape.md` 提到 Bandizip 有"explicit NFC/NFD filename-normalization controls"。

**审查发现：**

**U1. 字节保存不变量正确但缺少实现细节 [E+I]**
- 不变量"保留原始字节 + 分离显示名"是正确的。但实现需要定义：
  - 原始字节如何存储？在内存模型中作为 `[UInt8]` 保留？还是在归档中就地读取？
  - 显示名的解码尝试顺序？CP437 → UTF-8（bit 11）→ GBK → Shift-JIS → Big5？还是用户选择？
  - 当多种编码都能解码但结果不同时，如何呈现歧义？

**U2. NFC/NFD 显示策略不完整 [I]**
- `windows_interoperability_contract.md` W0 写"Normalize generated path names to NFC"，但 macOS HFS+ 默认使用 NFD，APFS 保留原始形式。
- 问题：如果用户在 macOS 上浏览一个包含 NFD 文件名的 ZIP（由 macOS 创建），显示名是否应该转换为 NFC？如果转换为 NFC 显示但原始字节是 NFD，用户重命名时应该写 NFC 还是 NFD？
- 推断：显示层应统一为 NFC（或用户系统规范化形式），但归档内字节保持原样。新建归档时统一写 NFC。重命名时写 NFC 并记录可逆映射。

**U3. 传统编码检测缺少决策树 [I]**
- minizip-ng 支持 CP437/932/936/950 解码，libarchive 也有编码启发式。但如果一个 ZIP 条目没有设置 bit 11 且字节序列同时兼容 CP437 和 GBK（在 ASCII 范围内），如何决定？
- 推断：当 bit 11 未设置时，应优先尝试 UTF-8 解码（如果成功且无替换字符，则可能就是 UTF-8），然后按用户偏好地区设置回退到 CP936/CP932/CP950，最后 CP437。歧义情况应让用户选择并预览。

**U4. Windows 文件名冲突检测不完整 [I]**
- `windows_interoperability_contract.md` W0 写"detect normalization-equivalent and Windows case-insensitive collisions before creation"。但检测时机不明确：
  - 是在创建归档前扫描所有条目名？
  - 还是逐条目添加时检测？
  - 批量检测更可靠但无法处理流式添加。
- Windows 保留设备名（CON、PRN、AUX、NUL、COM1-9、LPT1-9）的检测列表是否完整？是否包括 `$MFT` 等 NTFS 元数据文件名？

**U5. 可逆重命名映射缺少持久化策略 [I]**
- `windows_interoperability_contract.md` 提到"reversible rename map"，但未定义映射的存储位置和生命周期：
  - 映射存储在归档内（作为注释或额外字段）？还是应用状态？
  - 如果存储在应用状态，重新打开归档时如何恢复映射？
  - 如果存储在归档内，是否会影响格式兼容性？
- 推断：映射应作为应用级会话状态存储，不修改归档格式。提取时根据映射恢复原始文件名。但用户关闭应用后映射丢失——这是可接受的，因为映射的目的是让用户在当前会话中理解并操作归档内容。

---

## 构建配置和许可证门禁

### 构建配置审查

**Local 配置 [E]**
- 签名：ad-hoc/本地签名。
- 7zz：可能发现本地安装的 7zz，也可能从项目内编译的 helper 调用。
- RARLAB：发现本地安装的 `rar`。
- 许可证义务：最小——不分发，不触发 LGPL 分发义务。但应包含 about/credits 声明。
- 缺口：如果 Local 构建从源码编译 7zz helper 并嵌入应用 bundle，即使不分发，也应在本地记录构建 provenance（版本、编译选项、链接的编解码器），为未来 Direct 构建做准备。

**Direct 配置 [E]**
- 签名：Developer ID + hardened runtime + notarization。
- 7zz：可捆绑签名 ARM64 7zz helper。
- RARLAB：保持外部。
- 许可证义务：
  - LGPL 分发义务触发：需提供 7zz 对应源码、修改声明、许可证文本。
  - `7z.dll` 混合 LGPL/BSD/UnRAR 受限代码：需明确声明 UnRAR 仅用于解压缩。
  - minizip-ng（zlib 许可证）和 libarchive（BSD 许可证）：需包含许可证声明。
- 缺口 [U]：hardened runtime 对 helper 进程的影响未评估——helper 是否需要独立的签名和 entitlements？embedded helper 的 hardened runtime 配置是否与主应用一致？

**OpenSource 配置 [E]**
- 分发：源码。
- 7zz：不预编译，构建脚本从上游获取。
- RARLAB：不包含，用户自行安装。
- 许可证义务：
  - 需要选择项目自身的开源许可证。
  - 如果选择 GPL，与 minizip-ng（zlib）/libarchive（BSD）兼容。
  - 如果选择 MIT/BSD，与所有依赖兼容。
  - 如果选择 Apache-2.0，与所有依赖兼容但需注意专利声明。
  - 7zz 的 LGPL 在源码分发下通过提供源码链接即可满足。
- 缺口：项目许可证选择是用户决策，文档应列出兼容选项但不替用户决定。

### 验收门禁审查

**现有门禁覆盖度（来自 `conference_context.md` 成功标准 + `architecture_options.md` 审批门禁）：**

| 门禁类别 | 覆盖状态 | 缺口 |
|---|---|---|
| 正确性 | 部分覆盖 — 格式能力矩阵需用生成的测试夹具验证 | 缺少差异测试计划（多引擎对同一格式的输出对比） |
| 性能 | 未覆盖 — 无性能预算定义 | 需定义：大文件提取时间、10万条目归档浏览响应时间、编辑事务延迟目标 |
| 无障碍 | 部分覆盖 — architecture_options.md 提到 VoiceOver 和 Full Keyboard Access | 缺少无障碍测试矩阵和验收标准（如 VoiceOver 导径完整性、动态字体支持、对比度） |
| 构建配置 | 部分覆盖 — 定义了 Local/Direct/OpenSource 三种配置 | 缺少每种配置的具体构建脚本和验证步骤 |
| 签名/公证就绪 | 未覆盖 — 仅提到 Local 用 ad-hoc 签名 | Direct 构建的签名/公证流程未定义（Developer ID 证书管理、notarization 提交脚本、stapling） |
| 扩展打包 | 部分覆盖 — 提到 Quick Look Preview Extension | 缺少扩展的沙盒/ entitlement /签名配置定义；Action Extension 和 App Intents 未展开 |
| 组件清单 | 未覆盖 | 需要 SPDX/SBOM 格式的完整组件清单：minizip-ng + libarchive + 7zz + RARLAB（外部）+ 系统框架 |
| 许可证义务 | 部分覆盖 — 识别了 LGPL/UnRAR/BSD/zlib/MIT/GPL 风险 | 缺少每种构建配置的具体许可证义务清单和 NOTICE 文件模板 |
| 安全测试 | 部分覆盖 — 列出了 Zip Slip/symlink/bomb/password/quarantine | 缺少资源限制测试（内存/CPU/文件描述符）和 fuzzing 计划 |
| Windows 互操作 | 部分覆盖 — 定义了 W0/W1/W2 和物理测试矩阵 | 全部物理 Windows 测试未执行（见上文清单） |
| Unicode/编码 | 部分覆盖 — 定义了测试夹具（多语言/emoji/NFC-NFD） | 缺少传统编码（CP936/CP932/CP950）的解码验证和歧义处理测试 |

**必须新增的门禁：**

1. **性能预算门禁**：定义关键操作的性能基线（如 1GB ZIP 提取 < 30s、10万条目浏览 < 2s 首屏、编辑事务 < 5s 提交延迟），在验收测试中测量。
2. **差异测试门禁**：对每个有多引擎覆盖的格式，用同一输入测试所有引擎，比较输出一致性和行为差异。
3. **fuzzing 门禁**：对归档解析路径进行模糊测试（使用 libFuzzer 或类似工具），覆盖损坏/敌对归档输入。
4. **SBOM 门禁**：每种构建配置生成 SPDX 组件清单，包含组件名、版本、许可证、源码 URL、修改状态。
5. **签名/公证门禁**：Direct 构建通过 `codesign --verify --deep --strict` 和 `spctl --assess --type execute` 验证；notarization 提交后 stapling 验证。
6. **无障碍门禁**：VoiceOver 完整导航测试、Full Keyboard Access 路径测试、动态字体/对比度/减少动效适配测试。

**发布授权声明：** 本审查不授权任何发布动作。所有门禁为设计规范的一部分，不是发布指令。用户未授权上传、远程仓库创建、网站部署或公开发布。

---

## 必须修订项

按优先级排列。每项标注严重性（阻断/高/中）和负责方（建议）。

### M1 [阻断] 定义确定性引擎路由规则
ArchiveCapabilityRegistry 必须为每个 (格式, 操作) 元组定义明确的优先级链和降级条件，消除重叠引擎的隐式行为。见 D1。

### M2 [阻断] 定义 7z 编辑成本语义和 UI 交互
为 full-rebuild 操作定义预估成本类别、临时空间需求预检、可取消进度反馈。见 D2。

### M3 [阻断] 定义 helper 进程生命周期模型
定义 helper 是每操作独立进程还是常驻池，以及取消/崩溃/并发的处理协议。见 D4。

### M4 [阻断] 补全崩溃恢复的 staging 文件命名和检测约定
定义 staging 文件的确定性命名规则和应用启动时的扫描/清理协议。见 T7。

### M5 [高] 区分三种构建配置的许可证义务
为 Local/Direct/OpenSource 分别生成许可证义务清单和 NOTICE 文件模板。见 D5。

### M6 [高] 展开 RARLAB provider 的发现/验证/回退链
定义发现策略、验证步骤、失败回退和三种构建配置下的行为差异。见 D6。

### M7 [高] 定义 DMG mount 的隔离策略
将 DMG mount 操作作为独立安全审计项，定义隔离、quarantine、卸载协议。见 D7。

### M8 [高] 补全 Windows 保留设备名和冲突检测列表
完整列出 Windows 保留设备名（含 NTFS 元数据文件名），定义批量检测和逐条目检测的策略。见 U4。

### M9 [高] 定义嵌套归档处理策略
定义嵌套归档的展开策略、递归深度限制和不自动递归解压不变量。见 T1。

### M10 [高] 定义解压炸弹检测的具体阈值和机制
定义压缩比阈值、总输出大小限制、预扫描 vs 实时监控策略。见 T4。

### M11 [高] 定义源归档变更检测机制
定义检测方法（mtime/inode/hash）、检测时机（commit 前 vs 编辑期间持续监听）和检测到变更后的用户交互。见 O5/T5。

### M12 [中] 定义预览隔离缓存的生命周期
定义缓存位置、清理策略（预览结束 vs 应用退出）、大小限制。见 O4。

### M13 [中] 定义性能预算和验收基线
为关键操作定义性能目标并在验收测试中测量。见构建配置审查。

### M14 [中] 定义差异测试计划
为多引擎覆盖的格式定义同一输入的交叉测试方案。见构建配置审查。

### M15 [中] 定义 Unicode 编码检测决策树
当 bit 11 未设置时的编码尝试顺序、歧义呈现和用户覆盖策略。见 U3。

### M16 [中] 定义可逆重命名映射的持久化策略
明确映射为应用级会话状态、不修改归档格式、提取时恢复。见 U5。

### M17 [中] 补全无障碍验收矩阵
VoiceOver 导径、Full Keyboard Access、动态字体、对比度、减少动效的测试标准。见构建配置审查。

### M18 [中] 定义 SBOM 格式和组件清单
SPDX 格式、每种构建配置的组件清单生成流程。见构建配置审查。

---

## LOOP 记录

### 目标 (Objective)
对三条架构路线和 Option A 模块边界执行敌对技术架构 QC，覆盖引擎所有权/重叠能力/变异语义/helper 隔离/LGPL 合规/构建配置行为、操作和安全不变量、W0/W1/W2 审查、Unicode 保全、验收门禁审计。

### 动作 (Actions)
1. 完整读取 SOUL.md（571 行）——确认遵守 Codex 委派规则。
2. 依次读取 6 个任务文件：会议上下文、初始证据包、引擎矩阵、Windows 互操作合同、架构选项、Codex 审查。
3. 验证输出目录存在，确认不读取目录中其他 QC 文件（不在读取白名单内）。
4. 逐节执行敌对审查：路线选择 → 模块/引擎边界 → 操作/安全不变量 → Windows/Unicode → 构建配置/许可证/门禁。
5. 撰写输出文件。

### 观察 (Observations)
- 三条路线中 Option A 是唯一不缩减已批准范围的路线，但文档对其重叠引擎路由、编辑成本差异、helper 生命周期和 LGPL 合规细节的描述不足。
- 操作不变量框架（事务层）方向正确，但崩溃恢复的 staging 命名/检测、源变更检测机制、取消信号传播到 helper 的细节存在缺口。
- W0/W1/W2 合同的文档级证据充分，但全部物理 Windows 验证未执行——这是发布阻断项。
- Unicode 字节保存不变量正确，但 NFC/NFD 显示策略、传统编码检测决策树、可逆重命名映射持久化需要补全。
- 验收门禁在正确性和安全方面有基本覆盖，但性能预算、差异测试、fuzzing、SBOM、签名/公证就绪和无障碍矩阵缺失。

### 评估 (Evaluation)
- 路线选择结论（Option A）与 Codex 审查的推荐方向一致，且不缩减用户已批准范围。
- 18 项必须修订项中，5 项阻断、7 项高、6 项中。阻断项必须在设计规范定稿前解决。
- 本审查未发现需要推翻架构路线选择的证据——缺陷集中在实现细节和规范补全层面，不在架构方向层面。

### 修订建议 (Revisions Proposed)
见"必须修订项"M1–M18。所有修订为设计规范层面的补全要求，不涉及源码编辑（超出本任务授权范围）。

### 不确定性 (Uncertainty)
- helper 进程模型（每操作 vs 常驻池）的选择影响 D4/T8 的具体实现，但源文件未提供足够的性能数据来判断哪种更优。[U] 建议在设计规范阶段做原型基准测试。
- hardened runtime 对 embedded helper 的影响 [U] 需要实际 Xcode 签名配置验证——当前 Full Xcode 未安装（Codex 审查确认）。
- Windows 11 24H2 对 TAR.ZST 的原生支持程度 [U] — Microsoft Learn 文档提到 tar 支持，但 zstd 压缩的具体支持需物理验证。
- libarchive 63 个跳过的测试目标 [E] 中与产品需求重叠的部分（加密/实体/分卷 RAR、RAR5 Unicode、Windows 传统代码页、ISO/UDF 变体）需要替代测试夹具——这些跳过是显式覆盖缺口。

### 推荐下一轮 (Recommended Next Loop)
1. **Codex 审查本 QC 输出**，与其他 QC-2 参与者输出（MiniMax-M3、Reasonix DeepSeek Pro）交叉比较，识别共识和分歧。
2. **解决 5 项阻断修订项**（M1–M4 + staging 命名），在设计规范中形式化。
3. **生成完整设计规范**，覆盖 M1–M18 全部修订项，提交 MiniMax-M3 / GLM-5.2 / Reasonix DeepSeek Pro 审查循环。
4. **安装 Full Xcode** 后验证 Liquid Glass SDK 编译、扩展打包、签名配置。
5. **配置 Windows 测试环境**（VM 或物理设备），执行物理互操作测试矩阵的 10 项测试。
6. **生成 SBOM 组件清单**和每种构建配置的许可证义务文档。

### 路由声明
本输出由 Hermes `buddy` provider、模型 `GLM-5.2` 生成。主路由 `aishuo/GLM-5.2` 在三次 API 重试和五次连续 stale-response 检查后无输出，CLI 打印了 provider-unresponsive 终端消息（exit code 0）。本回退路由不声称主路由成功。建议 Codex 在主会场审查中记录此路由失败并评估是否影响 GLM-5.2 路由的后续可靠性评级。

### 会话归档
本任务为 Codex 委派的临时 QC 审查。输出文件自包含，Codex 可在验证后归档本会话。无理由保持会话活跃。
