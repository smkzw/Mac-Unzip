# GLM-5.2 全量技术规格 QC-3

## 已读取输入与边界

已完整读取以下文件：

- `~/.hermes/SOUL.md`（571 行，全文读取确认）
- `context/mac_archive_app_conference_context.md`
- `design/2026-07-11_full_design_spec.md`
- `design/2026-07-11_visual_direction_decision.md`
- `plans/mac_archive_app_requirements_traceability.md`
- `research/2026-07-11_engine_distribution_matrix.md`
- `research/2026-07-11_mature_product_design_synthesis.md`
- `research/2026-07-11_windows_interoperability_contract.md`
- `reviews/2026-07-11_architecture_qc2_synthesis.md`

工作边界：仅在 `/Users/smkzw/Documents/AI Products` 内活动；仅写入 `runs/conference/mac_archive_app/qc3_spec_glm.md`；未读取其他 participant/QC 输出；未浏览外部网络、未修改任何源文件、未执行代码。

本次审计性质：hostile technical completeness audit。不验证设计是否合理可取，而是攻击其在实施阶段是否会失败。所有发现标注为证据（E）、推断（I）、建议（R）或未解决不确定性（U）。

---

## 实施就绪结论

**结论：规格接近实施就绪，但有 7 项阻断级缺口必须在编写实施计划前关闭。**

阻断级问题（详见第 8 节）：

- B1：minizip-ng 与 7zz 在 ZIP 读取/编辑路由上的边界不完整，存在编码处理所有权歧义。
- B2：7z 编辑的"完整重建"事务语义缺少失败回滚路径定义。
- B3：RAR 创建的 RARLAB 输出验证协议未定义通过/失败标准。
- B4：libarchive `umask` 序列化约束未映射到操作调度器的并发模型。
- B5：DMG 挂载在 sandbox/hardened-runtime 下的可行性与失败降级路径未定义。
- B6：ZIP 7z 之间的格式转换（§6.2 菜单/§13 设计验收场景）缺乏操作定义。
- B7：App Sandbox spike 失败时的降级路径虽然被提及（§30），但缺少对 Quick Look/Finder 扩展在非 sandbox 主应用下的 entitlement 边界定义。

所有非阻断问题（共 15 项）可随实施计划并行解决，但阻断项必须在进入实施计划前通过规格修订关闭。

---

## 引擎与能力路由审计

### E-1 ZIP 路由：minizip-ng 与 7zz 的 ZIP 读取边界

证据（E）：规格 §8 声明 ZIP 的确定性路由为 minizip-ng（列/读/创建/编辑/加密）。engine_distribution_matrix §"Proposed Capability Routing" 声明 ZIP AES/ZipCrypto 的 fallback 为 libarchive / 7zz。

推断（I）：规格 §8 写"任何编辑事务开始后不得切换引擎。回退只能在打开/诊断阶段发生"。这意味着 fallback 只发生在格式探测/打开诊断阶段，编辑阶段不回退。但规格没有明确：当 minizip-ng 在打开阶段成功读取一个 ZIP 后，如果后续操作遇到 minizip-ng 不支持但 7zz 支持的某种压缩方法，会发生什么。

反例攻击：一个 ZIP 使用了 minizip-ng CTest 覆盖范围之外的方法（如 XZ 压缩方法 95，minizip-ng 的 CTest 报告没有明确列出 XZ 方法测试）。minizip-ng 打开成功（能读 central directory），但用户尝试解压某条目时失败。规格没有定义这种情况是"操作失败"还是"允许在该条目上使用诊断回退"。

建议（R）：规格 §8 必须增加一节"条目级方法不支持时的处理策略"，明确定义：单条目解压方法不支持 ≠ 整个压缩包打开失败，并定义是否允许条目级回退到 7zz 以及回退是否构成"切换引擎"。

### E-2 7z 编辑的事务语义：重建失败后的状态

证据（E）：规格 §14.5 声明"7z 或其他需完整重建的操作在执行前显示预计读取/写入量"。§14.2 第 7 步"若源已变化，中止"。§14.4 声明分卷压缩包编辑用另存为。

推断（I）：7z 编辑（添加/删除/重命名）本质是重建整个 7z 压缩包。7zz 的 `u`/`a` 命令在内部也是重写。如果重建过程中 7zz 因磁盘空间不足或被取消而中断，暂存文件 `.ArchiveApp.<UUID>.staging` 留下部分写入。

反例攻击：7zz 重建到 80% 时磁盘空间耗尽。规格 §15 崩溃恢复说"启动时扫描未完成事务；永不自动提交"。但 §14.2 的 5 步流程没有明确定义 7z 重建这种"暂存文件可能是部分有效的 7z 文件"场景的清理策略。7z 格式的部分文件可能是可打开的（header 可能在文件头），也可能是不可用的（取决于 7zz 写入顺序）。

建议（R）：规格必须定义 7z 重建失败后暂存文件的清理策略。由于 7zz 的重建写入顺序取决于其内部实现（先写 header 还是 footer），规格不应假设暂存文件的状态，应直接声明"重建中断的暂存文件一律视为不可用，删除并报告"。

### E-3 RAR 创建的输出验证协议

证据（E）：规格 §16.1 第 5 步"在临时目录执行创建、检测、解压缩探测并核对哈希"。engine_distribution_matrix §RARLAB Assessment 声明 RARLAB 为唯一可信 RAR 创建路径。

推断（I）：§16.1 第 5 步描述了验证流程，但没有定义通过/失败标准。什么哈希匹配被认为是"通过"？是创建后立即用 rar 自身测试，还是用 7zz 交叉测试，还是用本应用解压再比较？如果 rar 创建的 RAR 用 rar 自身检测通过但用 7zz 读取失败，怎么处理？

反例攻击：RARLAB rar 创建了一个使用 RAR5 格式 + BLAKE2 的 RAR。7zz 可以解压大部分内容但某些高压缩率条目（PPMd 或特殊字典大小）解压结果与原文不完全一致（7zz 的 RAR 解压实现与 RARLAB 的不完全一致是已知的历史问题）。

建议（R）：规格必须增加 RAR 创建验证的精确定义：
- 创建后必须用 rar 自身的 `t`（test）命令检测通过。
- 必须用 rar 解压到临时目录，比对原始文件 SHA-256。
- 如果 7zz 能读取该 RAR，也应做交叉验证；若 7zz 与 rar 结果不一致，应记录但不阻止创建（因为 RARLAB 是权威实现）。
- Windows WinRAR 验证作为 X-004 的物理验收。

### E-4 libarchive umask 序列化与操作调度器

证据（E）：engine_distribution_matrix §libarchive 声明 "`archive_write_disk_header()` must be serialized on POSIX due to its process-wide `umask` behavior"。

推断（I）：umask 是进程级状态。如果 libarchive 在进程内使用（作为链接库而非外部进程），同一进程中多个并发操作会互相干扰 umask。规格 §9.4 声明调度器"支持顺序任务、每压缩包修改互斥、最多两个外部任务"。但 §27 代码边界把 libarchive 放在 `ArchiveProviders` 中，没有区分它是进程内库还是外部进程。

反例攻击：两个并发操作都使用 libarchive（例如同时解压两个 TAR 文件到不同位置），一个设置了 umask 0077（仅 owner 可读），另一个设置了 umask 0022（默认）。两者交错执行 `archive_write_disk_header()`，导致提取的文件权限不正确。

建议（R）：规格必须明确：
- libarchive 的所有 `archive_write_disk` 调用必须通过一个全局串行队列执行，或在调用前后使用 `umask()` + `fchdir()` 的锁保护。
- 或者使用 `archive_write_disk_set_options(archive, ARCHIVE_WRITEDISK_NO_OVERRIDE_PERM)` 并在应用层管理权限。
- 这一点在 §16（外部提供方与进程模型）中没有覆盖，因为 §16 只讲外部进程，libarchive 是进程内库。

### E-5 DMG 挂载在 sandbox / hardened runtime 下的可行性

证据（E）：规格 §17 声明"DMG：只读、no-auto-open、no-browse 方式挂载"。§30 声明"若外部执行在沙盒内不可靠，Local/Direct 主应用采用 hardened runtime、非 App Sandbox"。

推断（I）：`hdiutil attach` 是 DMG 挂载的标准方法。在 App Sandbox 下，`hdiutil` 的执行需要 `com.apple.security.temporary-exception.mach-lookup.global-name` 或通过 SMJobBless/SMAppService 提权的 helper。规格没有分析 DMG 挂载是否在 sandbox 下可行。

反例攻击：sandbox 主应用调用 `hdiutil attach` 被 sandbox 拒绝（没有挂载文件系统的 entitlement）。降级到 hardened runtime 非 sandbox 后，DMG 挂载可行，但规格没有定义 DMG 功能在 sandbox 降级场景下的行为（是否变成"不可用"还是"需要用户额外授权"）。

建议（R）：规格 §17 和 §30 必须增加：DMG 挂载作为 sandbox spike 的一个显式测试项。如果 sandbox 不支持 DMG 挂载，DMG 功能在 sandbox 构建配置下应显示"此功能需要非沙盒模式"，而非静默失败。

### E-6 格式转换的操作定义缺失

证据（E）：规格 §6.2 主菜单包含"转换"。§13 设计验收场景未包含转换。requirements_traceability F-013 声明"Conversion — Save supported archive contents to another writable format without silent metadata/name loss"，状态为 Designed，但"full scope pending spec"。

推断（I）：转换操作涉及：打开格式 A → 解压全部内容到暂存 → 用格式 B 创建。这实际上是一个 extract + create 的组合操作。规格没有定义转换的事务语义（是否走 ArchiveTransaction），没有定义转换中某条目失败的策略（是否中止全部还是保留部分），没有定义转换是否保留原始元数据（权限、时间戳、链接）。

反例攻击：用户把一个含符号链接的 TAR 转换为 ZIP。ZIP 不支持存储 Unix 符号链接（minizip-ng 虽然可以写符号链接 entry，但 Windows Explorer 不识别）。转换后链接信息丢失或在 Windows 上造成混淆。

建议（R）：两种选择——
- 选项 A：从 v1 规格中移除"转换"功能，推迟到后续版本。这简化实施。
- 选项 B：保留转换但必须增加完整的转换规格章节：定义转换 = extract-to-temp + create-from-temp；定义元数据损失矩阵（哪些格式组合保留/丢失哪些元数据）；定义转换在 §14 事务模型中的位置。

我倾向选项 A（移除），因为规格已经足够庞大，转换是独立功能可以后加。

### E-7 RAR 读取：7zz 主引擎与 libarchive 诊断回退的边界

证据（E）：规格 §8 声明"RAR 读取：7zz，libarchive 仅作支持范围内的只读诊断"。engine_distribution_matrix 声明 libarchive 有独立 BSD-style RAR4/RAR5 reader，但 63 个 skipped targets 包括"fixture-gated RAR edge cases"。

推断（I）：当 7zz 读取 RAR 成功时，不需要 libarchive。当 7zz 读取 RAR 失败时，libarchive 作为诊断回退。但规格没有定义"诊断回退"的输出是什么：是给用户显示额外的技术诊断信息，还是尝试用 libarchive 实际解压？

反例攻击：7zz 因某个 RAR5 特性（如 BLAKE2 hash 校验失败）拒绝解压，但 libarchive 不做 BLAKE2 校验，可以解压出文件。用户看到"7zz 失败"但 libarchive 诊断显示"可以解压"。用户困惑：到底能不能解压？

建议（R）：规格必须明确诊断回退的语义：
- 诊断回退只用于向用户报告"另一个引擎的视角"，不用于实际提取。
- 如果 7zz 失败，即使 libarchive 看起来可以，也不自动用 libarchive 提取，因为 libarchive 的 RAR 支持范围与 7zz 不同（7zz 使用 RARLAB 解压代码，更权威）。
- 用户可以选择"尝试用诊断引擎提取（风险自担）"，但这必须是一个显式操作。

---

## 数据完整性与安全反例

### S-1 打开流程中的 TOCTOU：格式探测与文件身份

证据（E）：规格 §10 步骤 2"读取签名并探测格式"。§9.1 ArchiveDocument 包含"源文件身份、元数据和 SHA-256"。§14.2 第 6 步"重新检查设备/文件身份/大小/纳秒时间戳和 SHA-256"。

推断（I）：打开时计算 SHA-256（§10 步骤 6），保存到快照。但打开阶段的格式探测（步骤 2）与 SHA-256 计算（步骤 6）之间存在时间窗口。在这个窗口内，源文件可能被修改。

反例攻击：恶意脚本在用户选择文件与应用读取签名之间，将文件替换为一个 Zip Slip 恶意 ZIP。应用读取到的是恶意 ZIP 的签名，但 SHA-256 计算的是修改前的文件（如果 SHA-256 是从打开前的快照取的）。

建议（R）：规格 §10 必须明确 SHA-256 计算与格式探测使用同一个已打开的文件描述符（fd），不是分别 open 两次。或者格式探测完成后，先记录文件大小/mtime/inode 作为快速身份检查，SHA-256 后台计算完成后更新快照。如果后台 SHA-256 完成前用户就开始编辑，保存时必须要求 SHA-256 已完成。

### S-2 预览缓存的路径映射逆向

证据（E）：规格 §11 步骤 3"条目 ID 映射为随机磁盘名"。§11 步骤 6"添加 quarantine"。

推断（I）：随机磁盘名防止了从缓存路径反推压缩包内路径。但规格没有定义条目 ID 到随机名的映射是否持久化。如果不持久化，窗口关闭/应用重启后无法清理残留缓存（因为不知道映射关系）。

反例攻击：应用崩溃时预览缓存未清理。重启后，§11 步骤 8"启动时清理过期缓存"——但如何判断"过期"？如果按时间戳，正常使用的缓存也可能被误删；如果按映射表，映射表在崩溃中可能丢失。

建议（R）：规格应明确预览缓存使用固定根目录 + 每窗口子目录（UUID 命名），清理策略为"启动时扫描所有子目录，删除不属于任何活跃窗口的子目录"。不依赖映射表持久化。

### S-3 外部编辑回写的竞态

证据（E）：规格 §14.6 步骤 3"由系统打开副本；应用监视已保存变化"。步骤 4"检测到变化后显示原/新大小"。

推断（I）：外部编辑器可能在应用检测到变化后继续修改文件（用户在编辑器中按了多次保存）。规格步骤 5 说"接受后只新增一项 replace 暂存更改"，但如果用户接受后编辑器又保存了一次，暂存更改指向的是旧版本。

反例攻击：用户在 TextEdit 中编辑，应用检测到第一次保存并提示。用户点了"替换"后，TextEdit 自动保存了第二次（macOS 的自动保存机制）。暂存更改指向第一次保存的版本，但用户实际想要的是第二次。

建议（R）：规格 §14.6 应定义：接受替换时应快照副本内容到暂存区域，不再依赖编辑器目录中的文件。或者定义"应用在替换前最后一次读取副本内容并计算 SHA-256，与暂存更改绑定"。

### S-4 密码在内存中的生命周期

证据（E）：规格 §18"默认只在当前操作内存中使用"。

推断（I）：Swift 的 String/Data 是不可变的值类型，但如果密码被复制到多个变量，每个副本的释放时间不同。标准库不保证密码 String 的内存内容在释放后被擦零。

反例攻击：密码 String 被传递到多个层（输入框 → 操作对象 → 引擎适配器 → minizip-ng/7zz 参数），每一层都有 String/DATA 拷贝。操作完成后，这些拷贝的内容留在堆中，直到被后续分配覆盖。如果进程内存被 dump（如 crash report），密码可能泄露。

建议（R）：这是一个已知的难以完全缓解的问题。规格应在 §18 增加声明："密码通过 ContiguousArray<UInt8> 或 malloc 分配，使用后显式清零；传递到 C 层时使用局部 buffer 并清零；不做绝对的内存安全声明，但在 crash report 中不包含密码（通过 §21 redaction 确保）"。这是合理的折中，不需要过度承诺。

### S-5 multipart 分卷发现的安全边界

证据（E）：规格 §20 声明"分卷发现按格式规则和同目录授权进行"。§9.4 提到操作包含 multipart 语义。

推断（I）："同目录授权"意味着应用在同一目录中搜索其他分卷。但分卷命名规则因格式而异（ZIP .z01/.z02/.../.zip，7z .7z.001/.7z.002，RAR .part01.rar/.part001.rar/.r00）。规格没有定义：如果同目录中有恶意构造的"分卷"文件名，是否会覆盖/污染正常分卷数据。

反例攻击：用户有一个 archive.7z.001 到 archive.7z.005。攻击者在同一目录放入一个 archive.7z.001（覆盖原文件名）。应用"同目录授权"发现这个恶意分卷，导致解压结果包含恶意内容。

建议（R）：规格应声明分卷发现必须验证每个分卷的文件身份（mtime/inode/大小）与打开快照中记录的预期分卷列表匹配。如果发现同目录有名字匹配但身份不同的文件，应提示用户"发现异常分卷文件，请确认"。

### S-6 崩溃恢复日志的篡改风险

证据（E）：规格 §15"恢复日志存于应用支持目录，只记录安全作用域书签、源指纹、暂存身份"。

推断（I）：恢复日志在应用支持目录，是用户可写的。如果日志被篡改（例如恢复记录指向一个不同的源文件），崩溃恢复可能尝试用错误的源文件验证暂存。

反例攻击：攻击者修改恢复日志中的源文件路径书签，指向一个不同的但格式相同的压缩包。用户选择"继续恢复"后，应用用错误源文件的 SHA-256 验证暂存，验证失败，但用户困惑。

建议（R）：规格应声明恢复日志中的安全作用域书签使用 macOS 的 security-scoped bookmark 机制（包含路径 + volume 标识），而非纯路径字符串。这本身提供了一定的防篡改能力。但如果需要更强保证，可在日志中对关键字段做签名（HMAC with device-specific key）。建议作为低优先级改进。

---

## 并发性能扩展与构建配置

### P-1 操作调度器的死锁场景

证据（E）：规格 §9.4 声明"调度器支持顺序任务、每压缩包修改互斥、最多两个外部任务及系统资源感知"。

推断（I）："每压缩包修改互斥"意味着同一压缩包上的修改操作串行执行。但提取（只读）操作是否也受限？规格没有区分只读操作与修改操作的并发策略。

反例攻击：用户打开压缩包 A，开始提取（长时间操作）。同时尝试编辑压缩包 A（添加文件）。提取是只读操作，编辑是修改操作。如果互斥锁覆盖所有操作（包括只读），提取会阻塞编辑直到完成。如果只覆盖修改，编辑会触发重建，重建期间是否有新的提取请求排队？

建议（R）：规格应明确并发模型：
- 只读操作（浏览、搜索、预览、提取）可以与同一压缩包上的其他只读操作并发。
- 修改操作（添加、删除、重命名、替换、保存）在保存事务期间获取排他锁。
- 提取操作在保存事务期间可以看到保存前的状态（快照读取）或被阻止（取决于实现复杂度）。建议阻止并提示"正在保存，请稍后"。

### P-2 100,000 条目索引的性能预算验证

证据（E）：规格 §23 声明"100,000 条目压缩包在目录可用后 2 秒内出现首个可操作列表"。标注为"待基准验证"。

推断（I）：2 秒目标对于 100,000 条目是一个合理的假设，但取决于索引策略（增量读取 vs 一次性读取 central directory）和列表虚拟化实现。规格 §4.2 声明"大压缩包使用增量索引、虚拟化列表和后台元数据加载"。

反例攻击：一个 100,000 条目的 7z 压缩包。7zz 的 list 命令需要解析整个 7z header（对于 solid archive 可能需要读取较多数据）。如果首次列出依赖 7zz 完成 list，延迟可能远超 2 秒。minizip-ng 读取 ZIP central directory 通常很快（一次 seek + read），但 7z 格式的 header 结构不同。

建议（R）：规格应声明 2 秒目标目前仅对 ZIP 格式有理论支撑（central directory 的一次性读取），7z/TAR/RAR 的索引性能需要单独的基准假设。实施时应为不同格式设定不同的首列表目标，或统一设为"不超过 5 秒"并按格式实测调整。这不是阻断项，但需要在实施计划中明确。

### P-3 构建配置的 7zz 嵌入与 LGPL 合规

证据（E）：规格 §26 声明 Direct 配置"捆绑 7-Zip 前必须提供对应源码、构建信息、修改记录和 LGPL/BSD/UnRAR 通知"。engine_distribution_matrix §7zz 声明"License is LGPL for most/all other files; 7z.dll mixes LGPL, BSD, and UnRAR-restricted decompression code"。

推断（I）：7zz 的 UnRAR 受限代码意味着包含 RAR 解压功能的 7zz 二进制在分发时有额外限制。UnRAR license 明确禁止反向工程，且要求在分发时包含特定通知。如果产品需要在网站分发，必须确保 7zz 的 RAR 解压代码来自 UnRAR 的合法引用，且通知正确。

反例攻击：Direct 构建捆绑了 7zz（含 UnRAR 代码），在网站上分发。用户下载后，法务审查发现 UnRAR license 的通知未正确包含，或 7zz 的构建未按 LGPL 要求提供对应源码。

建议（R）：规格 §26 应增加一个 "7zz 嵌入合规清单"：
- 7zz 的 ARM64 thinned build（去除 x86_64）。
- 对应源码包（与 7zz 同版本）的 commit hash 和 URL。
- LGPL 通知文本。
- UnRAR license 通知文本。
- 任何补丁的记录（规格已要求"修改记录"，但应明确无修改时也要声明"无修改"）。
- SBOM 格式选择（SPDX 或 CycloneDX）。
这不是阻断项（Direct 构建暂未授权），但 OpenSource 构建需要提前考虑。

### P-4 外部进程的 stdout/stderr 环形缓冲区溢出处理

证据（E）：规格 §16 声明"stdout/stderr 并发读取到有界环形缓冲；溢出终止任务，不以截断输出判断成功"。

推断（I）：环形缓冲区的"溢出终止任务"策略对于正常操作的 7zz 是合理的，因为 7zz 的正常输出不会太大。但如果 7zz 在处理超大压缩包时输出大量进度信息（例如每个条目一行），缓冲区可能溢出并终止一个本来正常的操作。

反例攻击：用户解压一个 100,000 条目的 7z 压缩包。7zz 的 verbose 输出每条目一行（如果应用在 verbose 模式运行 7zz），输出量超过环形缓冲区。操作被终止，用户看到"任务因输出溢出被终止"，但实际上操作本身是正常的。

建议（R）：规格应声明外部进程默认以非 verbose / quiet 模式运行（`-bso0 -bse0` 或等效），只通过 exit code 和结构化输出文件判断结果。环形缓冲区用于捕获意外错误输出，不是正常输出通道。实施时应定义明确的进度获取机制（如 7zz 的 `-bsbout` 或自定义 progress 文件），不依赖 stdout 行解析。

---

## 需求追踪与测试缺口

以下逐行比对 requirements_traceability.md，标注 QC-3 视角的缺口：

### F-001 (ZIP) — 测试覆盖缺口

追踪要求：Unit/integration/fixture/fuzz/Windows tests。
规格覆盖：minizip-ng 路由明确，UTF-8 bit 11 明确，ZipCrypto/AES 区分明确。
缺口（U）：规格 §13.2 提到 AES ZIP "显示第三方工具要求"，但没有定义 AES ZIP 的 W0/W1/W2 归属。推断为 W1（需要 7-Zip/WinRAR），但规格 §19 的 tier 定义只提"encrypted ZIP"归入 W1，没有细分 AES vs ZipCrypto 的 tier 归属。如果 ZipCrypto ZIP 在旧版 Windows 解压软件中也可解密（只是弱安全），它是否属于一个单独的"兼容性"tier？

### F-002 (7z) — 测试覆盖缺口

追踪要求：Helper contract, mutation, cancellation, encrypted/multipart Windows tests。
规格覆盖：7zz 路由明确，编辑=重建明确，加密预设明确。
缺口（E）：规格没有定义 7z 的 solid archive 下的条目级操作行为。7z 的 solid 压缩意味着所有文件被当作一个流压缩。删除一个条目需要重新解压整个 solid 块再重新压缩。这影响 §14.5 的"重建成本"估计和 §23 的性能预算。规格应声明 solid 7z 的编辑成本显著高于非 solid。

### F-008/F-009 (RAR) — 测试覆盖缺口

追踪要求：RAR4/5, encrypted, solid, Unicode, multipart fixtures。
规格覆盖：§8 RAR 路由明确，§16.1 RARLAB 验证明确。
缺口（I）：engine_distribution_matrix 声明 63 个 libarchive skipped targets 包含 "fixture-gated RAR edge cases"。规格没有列出这些 edge case 的替代验证来源。如果 7zz 是主引擎，需要在 7zz 的测试覆盖中验证这些 edge case，但规格没有引用 7zz 的测试矩阵。建议在实施计划中用 7zz 的内置 fixture（7-Zip 仓库中有 RAR 测试数据）覆盖。

### F-010 (DMG) — 测试覆盖缺口

追踪要求：Read-only/no-auto-open/no-browse mount, detach/recovery/adversarial image tests。
规格覆盖：§17 DMG 挂载策略明确。
缺口（E）：规格没有列出要测试的 DMG 类型。macOS 有多种 DMG（UDRW read-write、UDZO zlib-compressed、UDBZ bzip2-compressed、UDIF encrypted、sparse、sparsebundle）。规格 §17 只说"只读挂载"，没有定义哪些 DMG 格式变体在支持范围内。建议明确：v1 支持 UDZO/UDBZ 只读 DMG；加密 DMG 需要密码且在 §18 密码流程中处理；sparse/sparsebundle 的浏览/提取可行性需要作为 sandbox spike 的测试项。

### F-011 (ISO) — 测试覆盖缺口

追踪要求：ISO9660/UDF/Joliet/Rock Ridge fixture matrix。
规格覆盖：§17 声明 ISO 由 libarchive 处理。
缺口（I）：libarchive 的 ISO 支持深度需要验证。规格没有引用 libarchive 的 ISO fixture 覆盖率。63 个 skipped targets 中是否包含 ISO/UDF cases？engine_distribution_matrix 提到 skipped targets 包含 "encoding" cases，ISO 的 Joliet/Rock Ridge 涉及编码。建议在实施计划中明确 ISO fixture matrix 的来源（自行生成 vs libarchive 上游）。

### F-013 (Conversion) — 阻断级缺口

已在 E-6 中详述。规格定义了菜单入口（§6.2）和追踪行（F-013），但没有操作定义。这是规格层面的不一致：要么移除菜单入口直到规格完成，要么补充规格章节。

### S-007/S-008 (源文件保全与外部修改检测) — 设计完备

追踪要求：Kill/fault injection at every transaction phase; file identity and SHA-256 mismatch tests。
规格覆盖：§14.2 步骤 6-7、§15 崩溃恢复完备。
评估（E）：这两个安全需求在规格层面覆盖充分。唯一补充：§14.2 步骤 6 的"重新检查设备/文件身份/大小/纳秒时间戳和 SHA-256"应在规格中明确，如果 SHA-256 尚未完成计算（大文件场景），是否用 mtime+inode+size 作为快速预检。规格 §15 提到"源和暂存均重新验证后"，但没有定义验证的优先级。

### X-001 到 X-008 (Windows 互操作) — 环境缺口

所有 Windows 验收行标注为 "Pending environment"。这是规格无法关闭的外部依赖。规格 §19 的 tier 定义和 §29 设计验收场景覆盖了这些需求的设计层面。规格层面的完备性无缺口。建议在实施计划中将 Windows VM/物理机作为前置依赖。

### Q-001 到 Q-008 (性能/可访问性/视觉) — 待实现

所有性能行标注为 "Pending implementation"。规格 §23 正确标注这些为"验收假设"。无规格缺口。

### M-001 到 M-006 (模型 QC) — 路由完备

规格 §28.3 的 QC 合同与追踪矩阵一致。无缺口。

### W-010 (Replace/edit) 和 W-018/W-019 — 追踪标注 "Design detail pending full spec"

证据（E）：追踪矩阵 W-010 标注"Design detail pending full spec"。W-018/W-019 标注"Design detail pending full spec"。
评估（I）：规格 §14.6 外部编辑回写已详细定义，W-010 在规格层面实际上是完备的，追踪矩阵状态过时。§22 错误分类表已覆盖 W-018（missingVolume）和 W-019（wrongPassword/unsupportedEncryption/corruptedArchive）。建议更新追踪矩阵状态为 Designed。

---

## 分级必须修订项

### 阻断级（进入实施计划前必须修订规格）

| ID | 问题 | 必须修订内容 | 对应规格节 |
|---|---|---|---|
| B1 | ZIP 条目级方法不支持的回退策略未定义 | 增加"条目级方法不支持"的处理策略：不构成引擎切换，定义为操作级失败 | §8 |
| B2 | 7z 重建失败后暂存文件的清理策略未定义 | 声明重建中断的暂存文件一律视为不可用，删除并报告 | §14.5 或 §15 |
| B3 | RAR 创建验证通过/失败标准未定义 | 定义：rar test 通过 + rar 解压哈希比对；7zz 交叉验证记录不阻止 | §16.1 |
| B4 | libarchive umask 序列化约束未映射到调度器 | 声明 libarchive archive_write_disk 调用通过全局串行队列或显式 umask 锁 | §9.4 或 §27 |
| B5 | DMG 挂载在 sandbox/hardened-runtime 下的降级路径未定义 | DMG 作为 sandbox spike 测试项；定义 sandbox 下 DMG 不可用时的用户可见状态 | §17, §30 |
| B6 | 格式转换缺乏操作定义 | 选项 A：移除 §6.2 转换菜单入口，推迟到后续版本；选项 B：增加完整转换规格章节 | §6.2, §13 |
| B7 | Sandbox spike 失败降级下 Quick Look/Finder 扩展的 entitlement 边界未定义 | 定义非 sandbox 主应用 + sandbox 扩展的 IPC/entitlement 模型 | §30 |

### 高优先级（实施计划首周内修订）

| ID | 问题 | 建议修订 |
|---|---|---|
| H1 | 预览缓存的清理策略依赖映射表持久化 | 改为每窗口 UUID 子目录，启动时清理无活跃窗口的子目录 |
| H2 | 外部编辑回写的竞态（编辑器多次保存） | 接受替换时快照副本内容 |
| H3 | 外部进程 stdout 策略 | 声明默认 quiet 模式，不依赖 stdout 行解析进度 |
| H4 | multipart 分卷发现的安全验证 | 声明分卷身份验证（mtime/inode/size）与异常分卷提示 |
| H5 | 并发模型中只读 vs 修改操作的锁粒度 | 明确只读可并发、修改排他、保存期间阻止新只读 |
| H6 | RAR 诊断回退的语义 | 声明诊断回退仅报告不提取，用户显式选择才用诊断引擎提取 |

### 中优先级（实施里程碑前修订）

| ID | 问题 | 建议修订 |
|---|---|---|
| M1 | DMG 支持的格式变体列表 | 明确 UDZO/UDBZ/加密/sparse 支持范围 |
| M2 | ISO fixture 来源 | 引用 libarchive ISO 覆盖或自建 fixture |
| M3 | solid 7z 编辑成本声明 | 在 §14.5 增加 solid archive 编辑成本显著高于非 solid |
| M4 | 7zz 嵌入 LGPL/UnRAR 合规清单 | §26 增加详细合规检查清单 |
| M5 | 密码内存生命周期声明 | §18 增加显式清零策略和 crash report redaction 声明 |

### 低优先级（后续迭代）

| ID | 问题 | 建议修订 |
|---|---|---|
| L1 | 追踪矩阵 W-010/W-018/W-019 状态过时 | 更新为 Designed |
| L2 | 崩溃恢复日志防篡改 | 作为低优先级安全增强 |
| L3 | AES ZIP 与 ZipCrypto 的 tier 归属细分 | 在 §19 中明确区分 |

---

## LOOP 记录

**Objective（目标）：**
对全量设计规格执行 hostile technical completeness audit，识别所有在实施阶段会导致失败的规格级缺口，判定是否实施就绪，提供精确的阻断修订项。

**Actions（行动）：**
1. 完整读取 SOUL.md（571 行确认）。
2. 完整读取 8 个任务文件（会议上下文、全量设计规格、视觉方向决策、需求追踪矩阵、引擎分布矩阵、成熟产品设计综合、Windows 互操作合同、QC-2 架构综合）。
3. 逐节攻击设计规格的引擎路由、数据模型、并发模型、安全不变量、构建配置。
4. 逐行比对需求追踪矩阵，标注规格覆盖与缺口。
5. 构造 15+ 个具体失败场景（Zip Slip 之外的路径覆盖、TOCTOU、umask 竞态、外部编辑器多次保存、分卷篡改、进程输出溢出、solid archive 重建、密码内存泄漏等）。
6. 按严重度分级所有发现。

**Observations（观察）：**
- 规格整体完备性高。QC-2 综合已关闭了上一轮的大部分架构缺口（确定性路由、同卷暂存、分卷语义、源指纹、helper 生命周期、预览隔离、嵌套限制、RARLAB 验证、构建 profile、Windows 文件名合同）。
- 剩余缺口集中在引擎边界细节（B1/B4）、事务失败路径（B2）、验证标准定义（B3）、sandbox 可行性降级（B5/B7）、以及一个功能定义不一致（B6）。
- 安全设计覆盖面广（§12/§14/§15/§18），但存在若干竞态和清理策略的边界问题（S-1 到 S-6）。
- 性能预算正确标注为假设，无过度承诺。
- 追踪矩阵有少量状态过时（W-010/W-018/W-019）。

**Evaluation（评估）：**
7 项阻断级问题均为规格层面的定义缺失或不一致，不是设计方向的错误。每项阻断有明确的修订路径（修订 1-3 个规格节即可关闭）。修订工作量估计为规格文档的 5-8% 改动量。修订后规格可进入实施计划。

**Revisions（修订）：**
本审计为只读输出，不修订源文件。所有修订建议在第 8 节分级列表中给出，等 Codex 合并后修订规格。

**Uncertainty（未解决不确定性）：**
- U1：7zz 在 verbose 模式下的输出量行为（P-4），需要在实施时实测确认。规格建议 quiet 模式已覆盖风险。
- U2：libarchive 对加密 DMG 的支持深度（M1），需要在实施时测试。规格 §17 未明确，但这不阻断实施计划。
- U3：sandbox spike（§30）的结果将决定 B5/B7 的最终实现路径。如果 sandbox 完全可行，B5/B7 自动关闭；如果不可行，降级路径已在规格中提及但需细化。
- U4：格式转换（B6）的保留/移除是产品决策。建议移除以简化 v1，但 Codex/用户可能选择保留。

**Next loop（下一轮）：**
- Codex 合并所有 QC-3 输出（MiniMax-M3/GLM-5.2/DeepSeek Pro），修订阻断项 B1-B7。
- 修订后的规格进入实施计划阶段。
- App Sandbox spike 作为实施计划的前置任务，其结果关闭 B5/B7 并最终确定外部 provider 策略。
- 完整 Xcode 安装仍是环境前置依赖。
