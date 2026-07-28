# GLM-5.2 技术架构评审

**模型**: aishuo GLM-5.2
**角色**: 会议参与者（Codex 主场，Hermes 分会场）
**日期**: 2026-07-11
**SOUL.md 确认**: 已完整读取全部 571 行，包括第 11 节 Codex 委托规则和会场模式规则。本输出为咨询性质，最终架构/代码/运行时/视觉验收由 Codex 裁定。

---

## 已读取输入

| 文件 | 状态 |
|---|---|
| `/Users/smkzw/.hermes/SOUL.md` (1–571 行) | 完整读取 |
| `context/mac_archive_app_conference_context.md` (70 行) | 完整读取 |
| `plans/codex_main_venue_mac_archive_app.md` (53 行) | 完整读取 |
| `research/2026-07-11_initial_landscape.md` (116 行) | 完整读取 |

未读取工作区以外的任何文件，未浏览网页，未修改源代码。

---

## 引擎与模块边界比较

### 核心设计问题

一个商业化 Apple Silicon 原生 macOS 压缩包浏览器/编辑器需要同时满足：ZIP 的编辑/互操作（高频、高完整度需求），7z 的创建/解压（高强度压缩需求），TAR 家族的创建/解压（开发者工作流），RAR 的只读浏览/解压（法律约束），DMG/ISO 的只读（系统集成）。

这些需求没有单一引擎能全部覆盖。关键决策是模块边界的划分方式。

### 候选组合评估

#### 组合 A：ZIPFoundation + libarchive + 7-Zip (C++)

- ZIP 读写编辑用 ZIPFoundation（纯 Swift，MIT，原生 Apple 平台支持）
- 广泛格式解压和 7z 创建用 libarchive（BSD，C，流式 API）
- 7z 高完整度创建和 ZIP 备选用 7-Zip 引擎（LGPL + COM 分离，或独立进程隔离）
- RAR 解压用 UnRAR 源码（嵌入解压，遵守许可约束）

评估：
- 优势：ZIP 路径纯 Swift，编辑互操作最直接；libarchive 提供广覆盖解压；7-Zip 补充 7z 创建深度
- 风险：三个引擎的格式能力有重叠，需要清晰的仲裁层决定路由；7-Zip 的 LGPL 需要组件级许可证审计（证据：research packet 标注 "License and bundled-code inventory require exact review"）
- 推荐度：高

#### 组合 B：ZIPFoundation + SWCompression + UnRAR

- ZIP 用 ZIPFoundation
- TAR/GZIP/BZIP2/XZ 用 SWCompression（纯 Swift，MIT）
- RAR 解压用 UnRAR

评估：
- 优势：最大化纯 Swift，减少 C/C++ 依赖边界，测试隔离更简单
- 风险：SWCompression 不是全功能归档引擎（research packet: "not a full-featured universal archive engine"）；7z 创建缺失——这是用户需求中的核心格式
- 推荐度：中（缺少 7z 创建是阻断性缺口）

#### 组合 C：libarchive 为单一底层引擎 + ZIPFoundation 补充编辑

- 所有格式走 libarchive 统一 API
- ZIP 编辑路径用 ZIPFoundation（因为 libarchive 的 mutation = rewrite，不是原地编辑）

评估：
- 优势：减少引擎数量，统一 API 表面
- 风险：libarchive 的加密和格式特性对等性不均匀（research packet: "encryption and format feature parity vary"）；7z 创建能力有限；ZIP 编辑体验不如原生 Swift 直接
- 推荐度：中低

### GLM-5.2 推荐边界

1. ZIP 路径：ZIPFoundation 作为主引擎。它原生 Swift、MIT 许可、明确支持 Apple 平台和 ZIP 创建/读取/修改/大文件。加密（AES/ZipCrypto）需要单独验证（research packet 明确标注 "Requires separate validation for encryption needs"）。

2. 7z 创建/解压 + 广泛格式解压：推荐 7-Zip 引擎通过独立进程或 Objective-C++ 边界调用，而非 libarchive 的 7z 写入。理由：7-Zip 是 7z 格式的参考实现，创建/解压的完整度和兼容性最高。LGPL 义务需要法务确认（推断：动态链接 + 独立可执行文件 + 源码可用声明可能满足 LGPL，但需要律师确认）。

3. TAR/GZIP/BZIP2/XZ/Zstandard 创建/解压：libarchive 流式 API 是最成熟的选择。如果需要纯 Swift 路径（例如沙盒限制下的进程内处理），SWCompression 是补充，但需确认其 Zstandard 和大文件支持是否成熟（不确定性）。

4. RAR 解压：嵌入 UnRAR 源码（仅用于解压/浏览），严格遵守其许可条款（见格式许可证审计节）。不创建 RAR。

5. DMG/ISO 只读：优先评估 macOS 系统 API（hdiutil 或 DiskImages 框架），而非自己解析。如果需要进程内浏览，libarchive 支持 ISO9660 读取。DMG 格式更复杂（UDIF），可能需要系统级挂载（推断：sandbox 限制可能阻断挂载路径）。

6. 编辑/变更架构：所有格式统一走"暂存重写 + 原子替换"事务模型（research packet "Early Architecture Hypothesis" 已提出此方向，与本评估一致）。无论底层引擎是什么，编辑操作的抽象是：物化变更条目 → 流式重写到临时归档 → 验证 → fsync → 原子替换 → 保留恢复元数据。

### 模块边界定义

推荐四层架构：

- 第一层 UI 交互层（SwiftUI + AppKit 桥）：文档式窗口、Liquid Glass、Finder 集成、Quick Look、拖放。不包含任何格式逻辑。
- 第二层 操作抽象层（Swift）：定义统一的 ArchiveEntry/ArchiveMutation/ArchiveTransaction 协议。格式能力注册表在此层路由操作到具体引擎。
- 第三层 引擎适配层（Swift ↔ C/C++/Objective-C++）：每个引擎一个适配器，处理线程安全、内存管理、错误码转换、进度回调。
- 第四层 底层引擎（ZIPFoundation / 7-Zip / libarchive / UnRAR）：不做修改或最小修改，隔离在独立模块中。

关键不变量：第二层永远不知道第三层用什么语言实现；第一层永远不知道有多少种格式引擎。

---

## 格式能力与许可证审计

### 按格式逐一审计

#### ZIP

| 维度 | 评估 |
|---|---|
| 创建/读取/编辑/加密 | 全部支持（用户需求核心格式） |
| 推荐引擎 | ZIPFoundation（MIT） |
| 创建能力依据 | research packet: "MIT Swift library explicitly supporting ZIP create/read/modify, large files, and Apple platforms" |
| 编辑限制 | ZIP 编辑本质上是重写。ZIPFoundation 支持增量修改，但删除/替换条目需要重写中央目录。推断：大型 ZIP 的编辑性能需要流式重写而非全量载入。 |
| 加密不确定性 | research packet 明确标注 "Requires separate validation for encryption needs and Windows filename behavior"。ZIPFoundation 的 AES 支持情况需要源码级验证（不确定性）。 |
| Windows 兼容性风险 | ZIP 规范允许 CP437/UTF-8 文件名。Windows 11 Explorer 和 7-Zip 的行为差异是已知互操作风险点（需要测试矩阵覆盖）。 |

#### 7z

| 维度 | 评估 |
|---|---|
| 创建/读取/加密 | 全部支持 |
| 推荐引擎 | 7-Zip 引擎（LGPL，需法务确认） |
| 创建能力依据 | 7-Zip 是 7z 格式的参考实现 |
| 许可证风险 | research packet: "License and bundled-code inventory require exact review before commercial distribution"。7-Zip 的 LGPL 适用于代码，但捆绑的 LZMA SDK 和其他组件可能有额外条款。推断：需要逐组件审计，不能假设 LGPL 一刀切覆盖。 |
| Windows 兼容性 | 7-Zip on Windows 是事实标准，7z 格式的互操作风险最低 |
| 编辑限制 | 与 ZIP 类似，7z 编辑 = 重写。7z 的固实压缩（solid archive）使单个条目修改代价更高（需要解压整个固实块再重新压缩） |

#### TAR 家族（TAR/GZIP/BZIP2/XZ/Zstandard）

| 维度 | 评估 |
|---|---|
| 创建/读取 | 全部支持 |
| 推荐引擎 | libarchive（BSD）流式 API |
| 编辑 | TAR 没有中央索引，追加是可能的（通过追加块），但中间条目的删除/替换需要重写。推荐统一走事务重写路径。 |
| Zstandard 注意点 | Zstandard 在 macOS/TAR 生态中的采用正在增长，但 Windows 端兼容性不如 GZIP/BZIP2/XZ 成熟。推断：如果目标用户包含 Windows 互操作，需要测试 Windows 7-Zip/WinRAR 的 Zstandard tar 包支持（不确定性）。 |
| 许可证 | libarchive BSD；Zstandard BSD-3。低风险。 |

#### RAR

| 维度 | 评估 |
|---|---|
| 解压/浏览 | 支持（用户已批准 read/extract） |
| 创建 | 不支持——无合法开源 RAR 写入器（见下） |
| 推荐引擎 | UnRAR 源码（嵌入式解压） |

RAR 创建许可证是本项目的关键法律约束。

证据（research packet 引用的原始来源）：
- RARLAB 官方许可页 https://www.rarlab.com/license.htm
- UnRAR 许可镜像 https://github.com/pmachapman/unrar/blob/master/license.txt
- research packet 原文："The UnRAR source may be embedded for handling/extraction, but the license explicitly forbids using it to develop a RAR-compatible archiver or recreate the proprietary compression algorithm."
- research packet 原文："No credible lawful open-source RAR writer has been identified."

推断：UnRAR 许可明确禁止用其开发 RAR 兼容的归档器。因此：
- RAR 创建功能在当前法律框架下不可行，除非 (a) 与 win.rar GmbH 谈判分销许可，或 (b) 检测并调用用户自行安装的已授权 `rar` CLI
- SimpleZip 项目声称支持 RAR 创建（research packet: "its RAR-creation statement is suspect because 7-Zip does not create RAR"）——此声称不可信
- 用户已批准"RAR creation only if a lawful open-source option exists"——当前证据表明不存在

推荐：RAR 仅支持解压/浏览。如果用户需要 RAR 创建，走方案 (b)——检测用户系统是否有 `rar` CLI，有则调用，无则禁用该功能并提示。

#### DMG

| 维度 | 评估 |
|---|---|
| 只读浏览/解压 | 支持但复杂 |
| 引擎选项 | macOS hdiutil（系统级挂载）/ libarchive（UDIF 解析有限）/ 自行解析 UDIF |
| 关键风险 | UDIF 格式涉及版权/专利考量（推断：Apple 未公开 UDIF 规范，实现行为可能随 macOS 版本变化）。推荐优先使用 hdiutil 或系统框架，而非逆向 UDIF。 |
| 沙盒不确定性 | 如果走 Mac App Store 分发，sandbox 可能阻断 hdiutil 挂载路径（不确定性，需要 Codex 确认分发渠道） |

#### ISO (ISO9660 / UDF)

| 维度 | 评估 |
|---|---|
| 只读浏览/解压 | 支持 |
| 推荐引擎 | libarchive（ISO9660 读取支持已有） |
| 风险 | UDF（蓝光/DVD-Video）支持深度需要确认。libarchive 的 ISO9660 覆盖通常满足数据 ISO 需求。 |

### 许可证总结矩阵

| 引擎/库 | 许可证 | 商业闭源兼容性 | 需要法务确认 |
|---|---|---|---|
| ZIPFoundation | MIT | 是 | 否 |
| SWCompression | MIT | 是 | 否 |
| libarchive | BSD | 是 | 组件级通知审查（research packet 原文标注） |
| 7-Zip | LGPL + 捆绑组件 | 条件性（动态链接/独立进程） | 是——逐组件审计 |
| UnRAR | 自有许可（禁止开发 RAR 写入器） | 仅解压嵌入 | 是——确认嵌入条款 |
| XADMaster | LGPL-2.1 | 条件性 | 如果使用则需确认 |
| ShichiZip | LGPL-2.1 | 条件性 | 如果参考/复用则需确认 |
| MacPacker | GPL-3.0 | 否（除非整个项目接受 GPL） | 不推荐复用代码 |

推断：GPL-3.0 的 MacPacker 和 SimpleZip 不可作为闭源商业产品的代码基础。LGPL 项目（XADMaster、ShichiZip）如果仅作为动态链接库或独立可执行文件使用，可能可行，但需要律师确认。MIT/BSD 项目是最低风险选择。

---

## 安全不变量

以下不变量在任何代码路径中都不得违反。每条标注格式和适用场景。

### INV-1：路径遍历防护（Zip Slip / Path Traversal）

适用于所有格式的列表/解压/预览/编辑。

- 解压前验证每个条目的目标路径在用户指定目录之内
- 检查绝对路径（`/etc/passwd`）、`..` 序列、符号链接逃逸
- 拒绝包含 null byte 的文件名（`filename\x00.exe`）
- 拒绝 Windows 保留名（`CON`、`PRN`、`AUX`、`NUL`、`COM1-9`、`LPT1-9`）在跨平台导出时
- 验证方法：构造包含 `../../` 条目、绝对路径条目、null byte 条目的恶意 ZIP/TAR 测试夹具，验证所有条目被拒绝或被安全重命名

### INV-2：符号链接逃逸防护

适用于所有支持符号链接的格式（ZIP、TAR、7z）。

- 解压符号链接时验证链接目标在解压目录之内
- 拒绝指向绝对路径的符号链接（除非用户明确授权）
- 拒绝指向 `..` 链的符号链接
- 编辑时验证新增/替换的符号链接不逃逸

### INV-3：解压缩炸弹防护

适用于所有格式的解压/预览。

- 设置最大解压大小阈值（可配置，默认如 100:1 压缩比或固定上限如 64GB）
- 设置最大条目数阈值（防止百万条目耗尽 inode/内存）
- 流式解压时跟踪累计解压字节数，超限即中止
- 对嵌套归档（见 INV-7）设置递归深度限制
- 验证方法：构造 42.zip（嵌套自引用）、高压缩比炸弹、超大条目数夹具

### INV-4：密码和加密安全

适用于 ZIP（AES-256/ZipCrypto）、7z（AES-256）、RAR（AES-128/256）。

- 密码不以明文写入日志、崩溃报告、撤销栈
- 密码在内存中的生存时间最小化（用完后清零内存区域）
- 加密归档的密码提示通过安全输入通道（SecureField）
- ZipCrypto 被视为不安全（已知明文攻击）——如果用户选择 ZipCrypto，明确警告安全风险
- 加密归档编辑时密码在事务期间保持，事务结束后清除
- 验证方法：内存转储确认密码不在明文堆中；崩溃报告审查

### INV-5：隔离区预览安全

适用于预览功能。

- 预览提取选中条目到隔离缓存目录
- 设置三重限制：字节上限、时间上限、文件类型白名单
- 隔离缓存在预览结束/应用退出时清除
- 隔离缓存路径不可被其他应用写入（POSIX 权限 0700）
- 不执行从归档提取的任何可执行内容（拒绝 .app/.command/.sh 自动打开）
- 验证方法：构造恶意条目（伪装文件扩展名、超大文件、可执行内容），验证预览隔离

### INV-6：损坏归档安全降级

适用于所有格式的列表/解压。

- 损坏的归档不得导致崩溃、无限循环、内存耗尽
- 损坏检测后明确报告错误类型（CRC 失败、中央目录缺失、截断等）
- 部分损坏的归档应允许部分解压（用户选择恢复可读条目）
- 中央目录损坏的 ZIP 应支持扫描式恢复（从头扫描本地文件头）
- 引擎层的 segfault 必须通过进程隔离捕获（如果 7-Zip/libarchive 通过独立进程调用）
- 验证方法：构造 CRC 损坏、中央目录截断、条目截断、随机字节注入的夹具

### INV-7：嵌套归档安全

适用于嵌套归档（归档中的归档）。

- 设置最大递归深度（推荐默认 10 层）
- 嵌套浏览不需要完整解压外层归档（流式读取内层）
- 嵌套解压时累计大小不能超过 INV-3 的阈值
- 嵌套加密归档需要逐层密码输入
- 验证方法：构造多层嵌套（ZIP-in-ZIP-in-ZIP）、嵌套炸弹（自引用或高压缩比嵌套）

### INV-8：编辑事务原子性

适用于所有编辑/变更操作。

- 编辑永远通过暂存重写：物化变更到临时工作区 → 流式写入临时归档文件 → 验证完整性 → fsync → 原子 rename 替换原文件
- 替换前保留原文件的备份副本（或提供撤销栈）
- 崩溃恢复：应用重启后检测未完成的事务（临时文件/锁文件存在），提示用户恢复或放弃
- 编辑过程中源归档文件不可被外部修改（文件锁或 mtime 校验）
- 验证方法：在 fsync 后 rename 前强制 kill 进程，验证重启后恢复行为

### INV-9：macOS 元数据互操作安全

适用于跨平台导出。

- 默认导出预设剥离 `.DS_Store`、`__MACOSX`、AppleDouble `._*`、资源 fork
- POSIX 权限/UID/GID 在跨平台导出时不保留（除非用户明确选择保留预设）
- 扩展属性（xattr）在跨平台 ZIP 中以 Extra Field 存储，需要验证 Windows 端是否安全忽略
- 验证方法：在 macOS 创建含元数据的归档，在 Windows 11 Explorer + 7-Zip 验证可读性和元数据行为

### INV-10：Quarantine 属性

适用于从下载/网络来源的归档。

- 对带 `com.apple.quarantine` 扩展属性的归档执行额外安全检查
- 解压后的文件保留 quarantine 属性（macOS 系统行为）
- Gatekeeper 警告不被绕过

---

## 跨平台与多语言测试矩阵

### TM-1：Windows 兼容性矩阵

| 测试项 | 工具 | 方法 |
|---|---|---|
| ZIP 解压 | Windows 11 Explorer + 7-Zip 24.x + WinRAR 7.x | 创建含中文/英文/日文/混合文件名、符号链接、权限、空文件、深层目录的 ZIP，在三个 Windows 工具中验证 |
| ZIP 编辑后可读性 | 同上 | 编辑后（添加/删除/替换/重命名条目）的 ZIP 在 Windows 工具中验证 |
| 7z 解压 | 7-Zip on Windows | 创建含多语言文件名/加密/固实压缩的 7z，验证 |
| 7z 编辑后可读性 | 7-Zip on Windows | 编辑后的 7z 在 7-Zip 中验证 |
| TAR 包互操作 | 7-Zip + WinRAR + Windows tar | 创建 .tar.gz/.tar.xz/.tar.zst，验证 |
| 加密格式互操作 | 7-Zip + WinRAR | ZIP AES-256、7z AES-256 在 Windows 端解压验证 |
| 元数据清洁度 | 文件属性对比 | macOS 创建的归档在 Windows 中不出现 `._*`、`__MACOSX`、`.DS_Store`（使用跨平台预设时） |
| 分卷归档 | 7-Zip + WinRAR | 创建分卷 ZIP/7z，在 Windows 中合并解压 |

### TM-2：Unicode 文件名与编码矩阵

| 测试类别 | 具体用例 |
|---|---|
| 简体中文 | GBK 编码文件名（旧 Windows ZIP 常见）、UTF-8 文件名 |
| 繁体中文 | Big5 编码文件名 |
| 日文 | Shift-JIS 编码文件名、全角字符 |
| 韩文 | EUC-KR / UTF-8 |
| 阿拉伯文/希伯来文 | RTL 字符、组合字符 |
| Emoji | 多字节 emoji 文件名（📱📁等） |
| 组合 vs 预组合 | NFD vs NFC 规范化差异（macOS HFS+ 使用 NFD，APFS 行为不同） |
| 空文件名 | 空字符串文件名（非法但可能出现在损坏归档中） |
| 超长文件名 | >255 字节文件名（POSIX 限制 vs ZIP 无限制） |
| null byte 注入 | `file\x00.txt`（安全测试，应拒绝） |
| 编码误判 | CP936 文件名被误判为 CP437（libarchive/XADMaster 的编码检测逻辑差异） |

关键验证目标：
- 创建的 ZIP 必须设置 UTF-8 标志位（General Purpose Bit Flag bit 11），使 Windows 正确解码
- 解压旧 Windows ZIP（GBK/Shift-JIS 编码）时正确识别编码，不产生乱码
- macOS NFD 规范化不导致 Windows 端文件名重复或不可读

### TM-3：大文件与性能矩阵

| 测试项 | 规格 |
|---|---|
| 单条目大文件 | 10GB/50GB/100GB 单文件压缩/解压 |
| 总归档大小 | 50GB/200GB 多条目归档 |
| 内存限制 | 处理 100GB 归档时内存占用不超过 2GB（流式处理） |
| 零字节文件 | 空文件条目处理 |
| 稀疏文件 | 包含大量零区域的文件（TAR 支持，ZIP 不原生支持） |
| 高条目数 | 100K/1M 条目归档（中央目录性能/内存） |
| 固实 7z | 固实压缩 7z 的随机访问解压性能 |
| 超大中央目录 | ZIP64 扩展（>4GB 归档或 >65535 条目） |
| 并发操作 | 同时执行多个解压/编辑操作 |

### TM-4：元数据与特殊文件矩阵

| 测试项 | 注意点 |
|---|---|
| POSIX 权限 | UID/GID/mode 在 macOS 创建 → Windows 解压 → macOS 解压的往返中保持或安全降级 |
| 符号链接 | 相对/绝对/ dangling symlink 在 ZIP/TAR 中的处理 |
| 硬链接 | TAR 支持；ZIP 不支持 |
| 设备文件 | TAR 可包含；解压安全风险（通常拒绝） |
| FIFO/管道 | TAR 可包含；解压时通常忽略 |
| 扩展属性 | xattr 在 ZIP Extra Field 中的存储和跨平台兼容 |
| 时间戳 | mtime/atime/ctime 精度（秒 vs 纳秒）在不同格式间的往返 |

### TM-5：分卷归档矩阵

| 测试项 | 注意点 |
|---|---|
| ZIP 分卷 | .z01/.z02/.../.zip 的创建和跨平台合并解压 |
| 7z 分卷 | .7z.001/.7z.002 的创建和 Windows 7-Zip 解压 |
| RAR 分卷 | 只读——解压用户提供的 RAR 分卷 |
| 分卷大小边界 | 最后一个分卷只有 1 字节 |
| 分卷损坏 | 中间分卷损坏时的部分恢复行为 |
| 分卷加密 | 加密分卷的密码提示在哪个分卷输入 |

### TM-6：性能基准

| 场景 | 基准指标 |
|---|---|
| 列出 100K 条目 ZIP | 时间 < 2s |
| 解压 1GB 单文件 ZIP | 吞吐量 vs Archive Utility 对比 |
| 编辑 10GB ZIP（删除 1 个条目） | 重写时间 vs 全量解压再压缩 |
| 加密 ZIP AES-256 创建 | 加密开销 vs 非加密创建 |
| 预览启动延迟 | 双击到 Quick Look 显示 < 500ms |
| 内存峰值 | 处理 50GB 归档时 < 2GB |

### TM-7：崩溃恢复矩阵

| 场景 | 预期行为 |
|---|---|
| 编辑事务中 kill | 临时文件残留，重启后提示恢复 |
| 解压中途中断 | 已解压文件的状态明确（部分/清除） |
| 磁盘空间不足 | 解压/编辑前检查目标磁盘可用空间 |
| 文件系统只读 | 明确报错，不产生损坏文件 |
| 外部修改源归档 | mtime/checksum 校验失败时报错 |

### TM-8：辅助功能（Accessibility）矩阵

| 测试项 | 工具 |
|---|---|
| VoiceOver 导航 | 所有 UI 元素有 accessibility label |
| 键盘导航 | Tab/Shift+Tab/Enter/Space/Esc 完整路径 |
| 动态字体 | Dynamic Type 缩放后布局完整 |
| 高对比度 | 增强对比度模式下可读 |
| 减少动效 | Reduce Motion 下无 Liquid Glass 动画干扰 |
| 辅助功能检查器 | Accessibility Inspector 无警告 |

---

## 性能与故障恢复验收

### 性能验收标准（推荐）

以下为推断性建议值，需要实际基准测试验证（证据不足时标为推断）：

1. 列表性能：100K 条目归档的列表渲染不超过 3 秒（推断：SwiftUI List + lazy loading 应能实现）
2. 解压吞吐量：单线程解压 GZIP/DEFLATE 吞吐量不低于系统 Archive Utility 的 80%（推断：Apple Compression framework 使用硬件加速，第三方库可能慢 20-50%）
3. 编辑性能：在 10GB ZIP 中删除 1 个 1MB 条目，重写时间不超过全量解压再压缩的 50%（推断：流式重写跳过被删除条目，理论上接近此值）
4. 内存：处理任意大小归档时峰值内存不超过 4GB（不变量：所有路径流式处理，不全量载入）
5. 预览延迟：Quick Look 集成预览启动不超过 1 秒

### 故障恢复验收标准

1. 事务原子性（INV-8）：在 rename 前强制终止进程，验证原文件完整、临时文件可清理
2. 损坏归档（INV-6）：CRC 损坏/截断/中央目录缺失的归档不崩溃，给出明确错误，支持部分恢复
3. 磁盘空间：操作前检查可用空间（推断：估算解压后大小需要预扫描条目元数据）
4. 崩溃报告安全（INV-4）：崩溃报告中不包含密码/敏感路径

### 不可验收项（需 Codex 裁定）

以下项 GLM-5.2 无法在当前会话中验证，交由 Codex：
- 实际 Apple Silicon 构建的运行时性能
- Liquid Glass 渲染的视觉验收
- Mac App Store vs 直接签名分发的 sandbox 差异对引擎架构的影响
- Windows 11 上的实际互操作测试

---

## 必须修订项与阻断项

### BLOCK-1：RAR 创建功能（阻断性）

状态：不可行，需要用户/Codex 决策。

证据：UnRAR 许可明确禁止开发 RAR 写入器（research packet 引用 rarlab.com/license.htm 和 UnRAR license.txt）。无合法开源 RAR 写入器。

推荐：
- 默认：RAR 仅解压/浏览
- 可选：检测用户系统是否有 `rar` CLI（已授权安装），有则允许调用其创建 RAR，无则功能禁用并说明原因
- 不推荐：与 win.rar GmbH 谈判分销许可（成本和时间不确定，需法务评估）

### BLOCK-2：分发渠道未定（阻断性）

状态：Mac App Store vs 直接签名分发 vs 两者，尚未确定。

影响：
- Mac App Store 的 sandbox 限制可能阻断 hdiutil 挂载 DMG、调用独立进程版 7-Zip、文件系统广泛访问
- sandbox 还影响 App Sandbox container 外的文件访问模式
- engine 架构（进程内 vs 独立进程 helper）取决于此决策

推荐：在进入设计规格前由 Codex/用户确定分发渠道。

### BLOCK-3：7-Zip LGPL 许可证审计（阻断性）

状态：需要法务确认。

影响：7-Zip 捆绑了 LZMA SDK、DOORS/ANSI 编码转换等组件，每个组件可能有不同许可证。LGPL 的动态链接/独立进程策略需要律师确认。

推荐：Codex 确认是否预算法务审计。如果 LGPL 风险不可接受，备选方案是用 libarchive 的 7z 写入（功能更有限）或纯实现一个最小 7z 创建器（工程量大）。

### BLOCK-4：加密矩阵未定义（阻断性）

状态：用户需求提到加密，但具体加密格式矩阵未明确。

关键问题：
- ZIP AES-256（WinZip AES）：Windows 7-Zip 和 Explorer 支持吗？（推断：7-Zip 支持 AES-256，Explorer 的支持不确定——需要测试）
- ZipCrypto：不安全但兼容性最广。是否提供？
- 7z AES-256：7-Zip 原生支持，Windows 兼容性最佳
- 加密文件名：是否支持？（加密文件名在 Windows 端的行为需要测试）

推荐：定义加密矩阵为：ZIP AES-256（推荐）+ ZIP ZipCrypto（兼容性选项，附安全警告）+ 7z AES-256（推荐）+ 加密文件名（7z 支持，ZIP 部分支持）。

### REVISE-1：ZIPFoundation 加密支持验证（必须修订）

research packet 标注 ZIPFoundation "Requires separate validation for encryption needs"。如果 ZIPFoundation 不支持 AES-256，ZIP 加密路径需要额外库（如 minizip-ng）或自实现。

推荐：Codex 在源码级别验证 ZIPFoundation 的 AES 支持状态。

### REVISE-2：编码检测策略（必须修订）

旧 Windows ZIP 使用 CP437/GBK/Shift-JIS 等非 UTF-8 编码。XADMaster 的编码检测启发式被 research packet 标注为 "proven"（LGPL），libarchive 也有自己的检测逻辑。ZIPFoundation 是否做编码检测需要验证。

推荐：如果 ZIPFoundation 不做编码检测，需要额外集成编码检测层（如 ICU 或自实现启发式），否则旧 Windows ZIP 解压会出乱码。

### REVISE-3：macOS 最低版本目标（必须修订）

conference context 提到 "latest macOS/SwiftUI/AppKit surface" 和 "macOS 26 generation"，但具体最低部署目标未确定。Liquid Glass 是 macOS 26 的特性，如果部署目标低于 macOS 26，需要降级处理。

推荐：Codex/用户确认最低部署目标为 macOS 26.x（与 Liquid Glass 一致），或定义降级方案。

### REVISE-4：ZIP64 支持确认（必须修订）

如果目标用户处理 >4GB 归档或 >65535 条目，ZIP64 扩展是必须的。ZIPFoundation 的 ZIP64 支持完整度需要源码级验证。

### 非阻断但重要项

- XADMaster（LGPL）是否使用：其编码检测启发式对多语言文件名体验有显著价值，但 LGPL 义务需要评估
- libarchive-swift 和 SimpleZip 的成熟度不足（research packet: "low maturity", "very low adoption"），不推荐作为依赖
- ShichiZip 作为交互参考有价值，但 LGPL-2.1 + 7-Zip 衍生架构的复用需要法律和技术双重评估

---

## LOOP 记录

### 循环合约

- 目标：独立审计 macOS 原生压缩包应用的技术架构，覆盖引擎组合、格式能力、许可证、安全不变量、测试矩阵
- 假设：没有单一引擎覆盖所有格式需求；编辑 = 事务重写；RAR 创建法律上不可行
- 退出标准：输出文件按要求的 9 节 schema 完整覆盖，每条推荐有证据/推断标注，阻断项明确标识

### 迭代记录

**迭代 1 — Locate**

动作：完整读取 SOUL.md（571 行）、conference context（70 行）、Codex plan（53 行）、research landscape（116 行）。

观察：
- conference context 定义了严格的会场规则：Codex 是最终裁定者，Hermes/Reasonix 是咨询性质
- research packet 是当前唯一的证据来源，但明确标注为 "initial" 和 "not the final recommendation"
- 多个 open questions 尚未解决（分发渠道、最低 macOS 版本、加密矩阵、RAR 创建）
- 证据质量：research packet 引用的 URL 是可查询的原始来源（rarlab.com、Apple developer docs、GitHub repos），证据质量较高

评估：证据基础足够进行架构审计，但多个关键决策点需要 Codex/用户输入。

**迭代 2 — Outline & Operate**

动作：按要求的 9 节 schema 独立撰写审计报告。不参考其他参与者的输出。

观察：
- 引擎组合比较中，组合 A（ZIPFoundation + libarchive + 7-Zip）覆盖最完整
- RAR 创建的法律阻断在 evidence 中非常明确，不需要推断
- 安全不变量需要覆盖 10 个维度——每条都需要可测试的验证方法
- 测试矩阵需要覆盖 8 个维度，其中 Windows 兼容性和 Unicode 编码是最高风险区域

评估：
- 格式能力矩阵的验证高度依赖实际夹具测试——当前只有文献证据，缺少运行时验证（交由 Codex）
- LGPL 许可证的评估超出了技术评审的边界——需要法务介入（标记为 BLOCK-3）
- DMG/ISO 的处理方式高度依赖分发渠道（sandbox vs 非 sandbox）——标记为 BLOCK-2

**迭代 3 — Polish & Review**

动作：自审全文，从 reviewer/user/third-party 三个视角检查。

发现并修正：
1. 修正：初始草稿中未充分强调 ZipCrypto 的安全风险——已补充安全警告
2. 修正：初始草稿中 DMG 的 UDIF 专利/版权风险未标注为推断——已标注
3. 补充：分卷归档测试矩阵（TM-5）在初稿中被遗漏——已补充
4. 补充：崩溃恢复测试矩阵（TM-7）在初稿中被遗漏——已补充
5. 补充：辅助功能测试矩阵（TM-8）在初稿中被遗漏——已补充
6. 审查：确认每条技术声称都标注了来源（research packet / 推断 / 不确定性）

### 不确定性汇总

| 领域 | 不确定性 | 影响程度 |
|---|---|---|
| ZIPFoundation 加密支持 | 源码级未验证 | 高——可能需要替换/补充引擎 |
| ZIPFoundation 编码检测 | 源码级未验证 | 高——影响多语言文件名体验 |
| ZIPFoundation ZIP64 支持 | 源码级未验证 | 中——影响大文件/大条目数 |
| 7-Zip LGPL 许可证 | 需法务确认 | 阻断——可能影响引擎选择 |
| sandbox 对引擎架构的影响 | 取决于分发渠道决策 | 阻断——可能需要重新设计 helper 进程 |
| DMG UDIF 处理方式 | 取决于分发渠道和 Apple API 可用性 | 中 |
| Zstandard Windows 兼容性 | 未测试 | 低——TAR 家族不是核心格式 |
| libarchive 7z 写入完整度 | 未验证 | 中——如果不完整需要 7-Zip 引擎 |
| Apple Silicon 实际性能 | 未测试 | 中——交由 Codex 运行时验证 |

### 推荐的下一循环

推荐 Codex 在主会场进行以下工作：

1. 确认分发渠道（Mac App Store / 直接签名 / 两者）——阻断 BLOCK-2
2. 启动 7-Zip LGPL 许可证法务审计——阻断 BLOCK-3
3. 确认加密矩阵（ZIP AES-256 / ZipCrypto / 7z AES-256 / 加密文件名）——阻断 BLOCK-4
4. 源码级验证 ZIPFoundation 的加密/编码检测/ZIP64 支持状态——阻断 REVISE-1/2/4
5. 确认 macOS 最低部署目标——阻断 REVISE-3
6. 收集其他参与者（Qwen-Plus、MiMo、DeepSeek-Flash、MiniMax-M3）的独立输出，在主会场比较分歧
7. 对分歧项（尤其是引擎组合推荐和安全不变量优先级）进行主会场裁定或要求重跑

GLM-5.2 本轮输出为咨询性质。本会话可在 Codex 验证输出后归档。
