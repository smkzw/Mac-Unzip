# GLM-5.2 修订规格技术门禁 QC-4

日期：2026-07-11
角色：GLM-5.2（aishuo 主路由）
输入文件：`design/2026-07-11_full_design_spec.md` v0.10、`plans/mac_archive_app_requirements_traceability.md`、`research/2026-07-11_engine_distribution_matrix.md`
任务边界：仅技术门禁审计，不重开已批准的用户产品决策

---

## 0. SOUL.md 声明

已完整读取 `/Users/smkzw/.hermes/SOUL.md` 全部 571 行。遵守 Codex 委托规则：只读指定文件、只写指定输出、不编辑源文件、区分证据与推断、标注不确定性、附 LOOP trace。

---

## 1. 必检项逐条审计

### 检查组 A：引擎边界与事务完整性

#### A-1. ZIP unsupported-method 所有权

**规格 §8**（行 243）明确：ZIP 中出现 minizip-ng 不支持的条目级压缩/加密方法时，minizip-ng 仍保持文档所有权——可安全列举的条目继续浏览，不支持条目标记为`压缩方式暂不支持`并禁用预览/解压/替换；不得在同一编辑事务中暗中切换到 `7zz`。

**结论：已闭合。** 所有权归属、降级行为、引擎切换禁止范围均显式定义。7zz 仅作为用户主动`用诊断引擎检查`时的独立诊断源，不改变文档能力快照或保存引擎。

**残留风险（P2 plan-time）：** 规格未定义"minizip-ng 可安全列举但 7zz 诊断后声称可解压"这一矛盾的仲裁规则。当前措辞"即使诊断引擎声称可读，也不自动用它发布解压结果"隐含了仲裁（诊断不覆盖所有权），但实现计划应显式写入该仲裁逻辑的测试用例。

#### A-2. 7z rebuild failure cleanup

**规格 §14.5**（行 383）明确：取消、provider 失败、校验失败或崩溃后的重建暂存一律视为不可发布；可安全识别时自动删除，删除失败则进入恢复记录供用户显示/清理，绝不改变源或把部分结果改名为正式压缩包。**§15**（行 402-407）补充崩溃恢复日志语义。

**结论：已闭合。** 清理路径三态覆盖：成功删除 → 自动删除失败 → 恢复记录。源保全不变式贯穿 §4 原则 4。

#### A-3. RAR create pass/fail

**规格 §16.1**（行 435）定义了四步通过条件全部满足：`rar` 返回成功；`rar t` 完整性检测无错误；RARLAB 自身解压到隔离目录后条目清单/大小/SHA-256 一致；固定版本 `7zz` 独立列举并解压比对一致。任何一步失败都不发布输出。

**结论：已闭合。** 通过条件完备，失败行为（不发布）明确。Windows WinRAR 物理验收正确地被定义为 Direct/OpenSource 发布门槛，而非本机单次创建的静默替代项。

#### A-4. libarchive umask isolation

**规格 §16**（行 421）明确：libarchive 写盘不在主进程修改全局 umask；每个 libarchive 写入任务在独立短生命周期 helper 中以固定 `077` umask 启动，再由显式权限策略发布。

**引擎矩阵**（行 69）从上游确认：`archive_write_disk_header()` 必须串行，因 POSIX umask 行为是进程级的。

**结论：已闭合。** 规格方案（helper 级 umask 隔离）与引擎证据（进程级 umask）一致，设计正确绕过了竞态。

#### A-5. DMG degradation

**规格 §17**（行 441）明确：原始提取只有在夹具矩阵证明 UDZO/UDBZ/UDRW、加密与损坏 UDIF、sparse/sparsebundle、资源叉、符号链接、超大文件、取消和校验失败都不会越权或损坏数据后才启用；未通过时只提供只读挂载浏览。App Sandbox/hardened runtime spike 不能可靠挂载时，能力注册表标为`此构建仅支持识别，无法浏览磁盘映像`，不放宽全局权限。

**结论：已闭合。** 降级链清晰：全功能提取 → 只读挂载浏览 → 仅识别。降级触发条件（夹具矩阵通过/spike 通过）显式定义，不静默放宽。

#### A-6. v1 conversion removal

**规格 §6.2**（行 186）明确：v1 不显示尚未完整设计和实现的转换入口。**需求矩阵 F-013**（行 71）明确：Deferred beyond v1；no menu, toolbar or contextual entry may be shown until a loss matrix and transaction design are approved。

**结论：已闭合。** 规格与需求矩阵一致。验收证据为 UI absence scan + later design gate。

#### A-7. Extension entitlement/IPC boundaries

**规格 §30**（行 638）明确：Quick Look 与 Finder/App Intents 扩展使用各自独立 App Sandbox、只读/用户选择授权和独立容器；扩展不得执行 7zz/RARLAB、不得获得主应用任意文件权限，也不通过共享可执行代码绕过沙盒。主应用与扩展只经版本化、类型化的 App Group 请求/结果文件或系统 extension API 交换最小元数据；请求含随机 ID、输入书签/只读文件协调信息、期限和签名/HMAC，主应用重新授权并重新验证后才执行。扩展失败只回退为`在归档工作台中打开`，不放宽 entitlement。

**结论：已闭合。** IPC 协议（版本化 + 类型化 + HMAC + 期限 + 重新授权）、扩展能力限制（无 7zz/RARLAB 执行）、失败回退行为均显式定义。

---

### 检查组 B：预览、编辑、并发与密码生命周期

#### B-1. Preview cleanup

**规格 §11**（行 306-307）明确：每个窗口创建随机 `0700` 缓存根目录；窗口关闭时删除缓存；启动时在没有任何窗口活跃的阶段删除所有遗留窗口子目录，不依赖条目映射表或压缩包路径判断"过期"；清理失败记录诊断并在下一次启动重试。

**结论：已闭合。** 清理策略覆盖三个时间点（窗口关闭/启动/清理失败重试），且明确不依赖可变状态（映射表/路径）判断过期——这是一个正确的安全设计决策。

#### B-2. External-editor snapshot race

**规格 §14.6**（行 386-394）明确定义了不可变快照协议：

1. 提取副本到受控编辑目录，记录初始 SHA-256。
2. 检测到外部变化后显示原/新对比，询问用户。
3. 用户接受时重新读取，把当前内容快照复制到事务暂存区，计算 SHA-256 后与 `replace` 更改绑定。
4. **关键防竞态条款**："之后外部编辑器再次保存会产生新的变化提示，不会悄悄改变已暂存版本。"

**结论：已闭合。** 快照在用户接受时刻冻结（copy-on-accept + SHA-256 绑定），后续外部编辑器保存产生新提示而非覆盖暂存。这正确解决了编辑器持续写入与用户接受之间的 TOCTOU 竞态。

#### B-3. Quiet helper output

**规格 §16**（行 420）明确：外部工具默认使用 quiet/机器可控模式；stdout/stderr 环形缓冲只收集异常诊断，不承载条目清单或安全关键进度。正常进度来自 provider 的结构化回调、受控进度通道或文件系统计量；意外输出超限仍终止任务。**§16**（行 416）补充：stdout/stderr 并发读取到有界环形缓冲；溢出终止任务，不以截断输出判断成功。

**结论：已闭合。** 输出协议分层正确：结构化回调承载进度/结果，stdout/stderr 仅做异常诊断，溢出即终止。

#### B-4. Multipart validation

**规格 §20**（行 478）明确分卷发现协议：先按格式明确规则生成候选（ZIP `.zNN`/`.zip`、7z `.7z.NNN`、RAR `.partNN.rar`/旧式 `.rNN`），再为每卷记录文件资源标识、大小、修改时间和 SHA-256 快照；操作开始前全部复核。发现同名身份变化、编号缺口、重复卷或越出已授权目录即停止并要求用户确认/重新选择。

**结论：已闭合。** 分卷发现是主动构造+全量复核，不是被动收集目录中"名字像"的文件。**§12**（行 294）打开失败分类中也包含了 `missingVolume`，**§22** 错误表中有对应的 `缺少分卷文件` 分类和用户动作。

#### B-5. Read/write locks

**规格 §16**（行 422）明确：浏览/搜索/预览/解压可共享同一已打开快照；保存获取排他锁，期间新的只读任务提示`正在保存，请稍后`，既有只读任务先完成或取消后才提交替换。

**结论：已闭合。** 锁模型是 read-shared / write-exclusive，与 §10 步骤 6（SHA-256 完成前可浏览但不得保存事务）和 §14.2 步骤 6-7（协调写入块内源复核）协调一致。

#### B-6. RAR diagnostic fallback

**规格 §8**（行 243）明确：RAR 的 libarchive 回退同样只用于诊断；即使诊断引擎声称可读，也不自动用它发布解压结果。**引擎矩阵**（行 66-67）确认 libarchive 有独立 RAR4/RAR5 reader，但不能读加密 RAR payload。

**结论：已闭合。** libarchive 在 RAR 场景的定位明确：unencrypted/limited 只读诊断，不作为解压结果发布源。**需求矩阵 F-008** 也标注"libarchive fixture gaps open"作为残留证据缺口（P2）。

#### B-7. Password memory lifecycle

**规格 §18**（行 446-453）明确定义了密码全生命周期：

- 默认只在当前操作内存中使用。
- 不出现在日志、命令显示、错误详情或分析信息中。
- 钥匙串项使用随机 UUID 主键，本地元数据不保存密码。
- 密码以可控字节缓冲传递，避免长期 Swift String 副本；C/CLI 适配器只在最短作用域创建本地缓冲，使用后显式清零。
- 不得把密码放进 argv。
- 不承诺对已被系统/框架复制的内存绝对擦除，但 crash/诊断收集必须排除密码字段。
- **§15**（行 402）崩溃恢复日志不记录密码。

**结论：已闭合。** 生命周期覆盖传递（字节缓冲/非 argv）、存储（钥匙串 UUID + 无密码元数据）、清除（显式清零 + 诚实声明不保证绝对擦除）、隔离（日志/诊断/crash 排除）。规格诚实地标注了"不承诺绝对擦除"这一系统限制，是正确的工程诚实。

---

## 2. 矛盾审计

### 2.1 P0 矛盾（阻断实施计划编写）

**无。**

在检查组 A（7 项）和检查组 B（7 项）的 14 个必检维度中，所有 P0 级别的技术闭合性问题已在 v0.10 规格中解决。规格内部一致性检查（交叉引用 §8↔§16.1、§14.5↔§15、§16↔引擎矩阵、§17↔§30、§18↔§15）未发现矛盾。

### 2.2 P1 矛盾（需修复但不阻断实施计划框架）

**无未闭合项。**

以下两个边界问题经过审查后认定为 P2（plan-time 任务），而非 P1：

1. **minizip-ng unsupported-method 的诊断仲裁测试用例** — 规格 §8 末句"即使诊断引擎声称可读，也不自动用它发布解压结果"已经隐含了仲裁规则，但缺少显式的负面测试用例描述（如：minizip-ng 标记某条目不支持 → 7zz 诊断声称可解压 → 系统应仍禁用解压）。这是实现计划层面的任务，不构成规格矛盾。

2. **libarchive RAR fixture gap** — 引擎矩阵行 71 确认 63 个 skipped targets 中包含"fixture-gated RAR edge cases"。需求矩阵 F-008 标注"libarchive fixture gaps open"。这是证据缺口（P2 plan-time），不是规格矛盾：规格已正确地将 libarchive 限定为诊断角色，fixture gap 不改变设计决策。

### 2.3 P2 plan-time 任务（实施计划编写时必须纳入，但不阻断门禁）

| 编号 | 任务 | 规格依据 | 具体要求 |
|---|---|---|---|
| P2-1 | minizip-ng unsupported-method 诊断仲裁负面测试 | §8 行 243 | 构造 minizip-ng 不支持但 7zz 可解的 ZIP 条目，验证系统仍禁用解压/预览/替换，仅允许诊断 |
| P2-2 | libarchive RAR fixture 补全 | 引擎矩阵行 71；F-008 | 为 63 skipped targets 中与 RAR 相关的 edge case 编写替代 fixture |
| P2-3 | Xcode 安全 spike 协议设计 | §30 行 636 | 在实施计划中编写 spike 的具体验证矩阵：App Sandbox + 安全作用域书签 + 内嵌 7zz + 外部 RARLAB 的组合测试，以及沙盒内不可靠时的降级方案（hardened runtime 非 sandbox） |
| P2-4 | App Group IPC HMAC 密钥管理 | §30 行 638 | 实施计划需定义 App Group 共享密钥的生成、轮换和密钥环方案，规格只说"签名/HMAC"但未定义密钥生命周期 |
| P2-5 | umask helper 的权限发布策略 | §16 行 421 | 规格说"由显式权限策略发布"但未定义权限策略的具体规则（哪些条目获得什么权限）；实施计划需定义默认权限矩阵 |
| P2-6 | 性能预算基准化协议 | §23 行 519 | 规格标注"必须在目标 Mac 上用 Instruments/signpost 实测"；实施计划需定义基准化的具体里程碑和 fail/pass 阈值 |
| P2-7 | 钥匙串密码指纹更新边界 | §18 行 449 | "编辑保存成功后在同一密码项上追加新指纹并淘汰旧的'当前位置'关联"——实施计划需定义指纹列表上限和淘汰策略（避免无限增长） |

---

## 3. 交叉一致性验证

### 3.1 规格 ↔ 需求矩阵

- F-013（conversion deferred）↔ §6.2（v1 不显示转换入口）：一致。
- F-009（RAR create via RARLAB）↔ §16.1（RAR 创建通过条件）：一致。
- F-010（DMG）↔ §17（DMG 降级链）：一致。
- S-012（no silent engine fallback during mutation）↔ §8（任何编辑事务开始后不得切换引擎）：一致。
- S-006（preview isolation）↔ §11（随机缓存根/不跟随链接/quarantine/配额）：一致。
- S-009（helper identity）↔ §16.1 步骤 2-3（symlink/owner/签名验证）：一致。
- W-018（missing split volume）↔ §20 行 478（分卷发现协议）：一致。

### 3.2 规格 ↔ 引擎矩阵

- minizip-ng 244/244 CTest ↔ §8 ZIP 主引擎：一致。
- libarchive umask 行为（行 69）↔ §16 helper 隔离方案：一致，设计正确绕过进程级 umask。
- libarchive 无 7z 加密 writer（行 66）↔ §8 7z 路由到 7zz：一致。
- libarchive 不能读加密 RAR/7z（行 67）↔ §8 RAR 读取用 7zz：一致。
- 7zz universal binary 需 thinning（行 85）↔ §26 Direct 配置固定 ARM64 helper：一致。

### 3.3 内部逻辑自洽

- §10 步骤 6（SHA-256 完成前可浏览但不得保存）↔ §16 read/write 锁（保存需排他锁）↔ §14.2 步骤 6-7（协调块内源复核）：三者构成完整的快照-锁-提交链，无矛盾。
- §14.6 外部编辑快照冻结 ↔ §14.1 PendingChange 可撤销：快照绑定到 PendingChange.replace，撤销语义一致。
- §11 预览 50:1 比例不可覆盖 ↔ §12 解压 100:1 可在确认后单次覆盖：预览比解压更保守，这是正确的安全分层（预览是自动行为，解压是显式用户行为）。

---

## 4. 伪造尝试（Falsification Attempt）

按任务要求主动尝试证伪实施就绪性，结果如下：

### 4.1 尝试："libarchive umask helper 方案在并发场景下仍有竞态"

**证伪失败。** 规格 §16 明确每个 libarchive 写入任务在独立短生命周期 helper 中运行。不同 helper 是不同进程，各自有独立的 umask，不争用。竞态只在同一进程内 `archive_write_disk_header()` 串行调用时存在（引擎矩阵行 69），helper 隔离方案已根除该路径。

### 4.2 尝试："外部编辑器快照在用户接受前被编辑器截断"

**证伪失败。** §14.6 步骤 5 的措辞是"把当前内容快照复制到事务暂存区"——这是 copy 操作，接受后的暂存版本是独立副本。即使原编辑目录中的文件之后被截断，暂存区不受影响。用户接受后的"新的变化提示"（行 394）确认系统检测的是编辑目录中的新变化，而非暂存区变化。

### 4.3 尝试："分卷发现的候选生成规则可能遗漏混合扩展名场景"

**证伪部分成立（P2 级别）。** §20 列出的候选规则（`.zNN`/`.zip`、`.7z.NNN`、`.partNN.rar`/`.rNN`）覆盖了标准分卷命名，但未显式处理非标准命名（如用户重命名分卷）。不过规格紧接着说"不把目录中'名字看起来像'的文件直接加入集合"和"发现……即停止并要求用户确认/重新选择"，这意味着非标准场景由用户手动选择兜底。这不是 P0/P1 矛盾，但实施计划应增加非标准分卷命名的用户手动添加流程测试（纳入 P2-4 相邻测试）。

### 4.4 尝试："App Sandbox spike 未通过时，主应用采用 hardened runtime 非 sandbox 的降级路径可能与 Quick Look 扩展的独立 sandbox 产生 IPC 不兼容"

**证伪失败。** §30 最后一段（行 638）明确定义了主应用与扩展之间的 IPC 不依赖双方都在同一沙盒内——IPC 通过 App Group 请求/结果文件 + HMAC，扩展使用各自独立 App Sandbox。主应用是否沙盒化不改变扩展边界。即使主应用是 hardened runtime 非 sandbox，IPC 协议仍然适用。

### 4.5 尝试："密码指纹列表无限增长"

**证伪部分成立（P2 级别）。** §18 说"追加新指纹并淘汰旧的'当前位置'关联"，暗示有淘汰机制，但未定义指纹列表上限。归为 P2-7。

---

## 5. 门禁结论

### GO

没有未闭合的 P0 或 P1 矛盾阻断实施计划编写。

14 个必检维度（A-1 到 A-7、B-1 到 B-7）全部在 v0.10 修订规格中闭合。交叉一致性验证（规格 ↔ 需求矩阵 ↔ 引擎矩阵）无矛盾。5 次主动证伪尝试中 3 次完全失败（规格已闭合），2 次部分成立但均为 P2 级别（plan-time 任务，不阻断门禁）。

7 项 P2 plan-time 任务（P2-1 到 P2-7）必须在实施计划编写阶段纳入，但不构成本技术门禁的阻断条件。

---

## 6. LOOP Trace

**Objective:** Re-audit technical closure of design spec v0.10 after QC-3, attempting to falsify implementation readiness across 14 required dimensions without reopening approved user product decisions.

**Sources read:**
- `~/.hermes/SOUL.md`（571 行，完整读取）
- `design/2026-07-11_full_design_spec.md`（650 行，分两段完整读取）
- `plans/mac_archive_app_requirements_traceability.md`（167 行，完整）
- `research/2026-07-11_engine_distribution_matrix.md`（134 行，完整）

**Iterations:**
1. 全量读取三份源文件 + SOUL.md。
2. 按检查组 A（7 项引擎/事务/边界）逐条对照规格章节，确认每项的闭合证据。
3. 按检查组 B（7 项预览/编辑/并发/密码）逐条对照，确认每项的闭合证据。
4. 交叉一致性验证：规格 ↔ 需求矩阵（7 对）、规格 ↔ 引擎矩阵（5 对）、规格内部逻辑自洽（3 组）。
5. 主动证伪：构造 5 个攻击向量尝试推翻闭合结论。
6. 分级：将发现归入 P0/P1/P2，编写门禁结论。

**Observations:**
- v0.10 规格在所有 14 个必检维度上有明确的闭合条款，措辞精确，无模糊措辞。
- 交叉引用一致性高，未发现规格-矩阵-引擎三方矛盾。
- 5 次证伪中 3 次被规格已有条款完全击败，2 次降为 P2。

**Evidence used:**
- §8（行 243）：ZIP unsupported-method 所有权 + RAR libarchive 诊断回退
- §14.5（行 383）：7z rebuild 清理
- §14.6（行 386-394）：外部编辑快照防竞态
- §16（行 420-422）：quiet helper + umask 隔离 + read/write 锁
- §16.1（行 435）：RAR create 四步通过条件
- §17（行 441）：DMG 降级链
- §18（行 446-453）：密码全生命周期
- §20（行 478）：分卷发现协议
- §30（行 638）：扩展 entitlement/IPC 边界
- 引擎矩阵 行 66-71：libarchive 能力边界与 umask 行为
- 需求矩阵 F-008/F-009/F-010/F-013/S-006/S-009/S-012/W-018

**Failed/abandoned paths:** 无。所有检查路径均完成，无需放弃。

**Remaining uncertainty:**
- P2-3（Xcode 安全 spike）的实际结果将决定主应用最终是否沙盒化，但规格已为两种结果都准备了设计路径（§30 行 636），不构成门禁阻断。
- P2-4（App Group HMAC 密钥生命周期）的细节留给实施计划，规格层面只要求"签名/HMAC"存在即可。

**Recommended next loop:** Codex 编写实施计划时纳入 P2-1 到 P2-7 作为首批 plan-time 任务；Xcode 安全 spike（§30 行 636）应作为实施计划的第 0 里程碑。

---

*GLM-5.2（aishuo 主路由）技术门禁审计完成。本输出为 Codex 主会场咨询性意见，不替代 Codex 最终决策。*
