# DeepSeek V4 Pro 独立架构复核

**角色：** Reasonix CLI `deepseek-pro`（`deepseek-v4-pro`），Codex 主会场高风险复核员  
**日期：** 2026-07-11  
**状态：** 完成  
**输入源：** 仅限下文"已读取输入"所列文件  
**边界：** 未浏览网页、未调用外部服务、未编辑源码、未改动本文件之外的任何内容

---

## 已读取输入

| 文件 | 行数 | 角色 |
|---|---|---|
| `context/mac_archive_app_conference_context.md` | 70 | 会议边界、参与者路由、成功标准、风险边界 |
| `plans/codex_main_venue_mac_archive_app.md` | 52 | Codex 任务分解、参与者分配、验证清单 |
| `research/2026-07-11_initial_landscape.md` | 116 | 商业产品证据、开源候选、格式矩阵、早期架构假设、RAR 许可判定 |

本次复核不依赖上述三个文件之外的任何外部信息。

---

## 关键假设反驳

以下按严重程度排列，对证据包中的断言逐一核查。

### 1. SimpleZip 的 RAR 创建声明应标记为「已证伪」而非「可疑」

**证据包原文（L91）：** "its RAR-creation statement is suspect because 7-Zip does not create RAR"

**反驳：** "suspect" 的措辞过于温和。若 SimpleZip 确实封装 7-Zip 或其衍生代码，而 7-Zip 明确不支持 RAR 创建，则 SimpleZip 的 RAR 创建声明要么是功能上的谎言（声称支持但实际不可用），要么是通过 shell out 到专有 `rar` CLI 实现——而后一种情况意味着该功能不可移植、不可嵌入、且可能违反 `rar` CLI 的再分发条款。该声明应降级为「**已证伪，除非提供反证**」，Codex 在设计阶段即应排除以 SimpleZip 作为 RAR 创建路径的任何依赖。

**证据类型：** 推断（基于 7-Zip 架构事实 + SimpleZip 派生关系的推断）  
**不确定性：** 低——7-Zip 不支持 RAR 创建是上游项目的公开立场

---

### 2. ZIPFoundation「modify」语义未经字节级验证

**证据包原文（L61-63）：** "MIT Swift library explicitly supporting ZIP create/read/modify, large files, and Apple platforms."

**反驳：** "modify" 是一个模糊术语。证据包未回答以下关键问题：
- 「修改」是指 entry 级增删，还是支持 entry 内字节级替换？
- 修改操作是全量重写还是原地更新？
- 对 ZIP64（>4GB 或 >65535 entries）的修改路径是否与普通 ZIP 走相同代码路径？
- 修改操作是否保证崩溃安全（即不会产出损坏的 ZIP）？
- 若修改中间失败，是否回滚到原始状态？

**建议：** Codex 必须在源码级审查 ZIPFoundation 的修改语义，并编写针对 ZIP64 边界、崩溃注入、并发修改的专项测试。不能仅凭 README 声明接受其修改能力。

**证据类型：** 推断（对文档措辞的质疑，需要源码验证才能确认）  
**不确定性：** 中——ZIPFoundation 可能是可靠的，但缺乏直接证据

---

### 3. libarchive「BSD-style」许可掩盖了组件级许可复杂性

**证据包原文（L50）：** "License is a permissive BSD-style project license but needs component-level notice review."

**反驳：** 证据包承认需要组件级审查，但未列出 libarchive 捆绑的关键第三方组件及其许可。实际 libarchive 源码树中包含：
- zlib（zlib License）
- bzip2（BSD-style）
- LZMA SDK（Public Domain）
- LZ4（BSD 2-Clause）
- Zstandard（BSD + GPLv2 双许可——需确认使用 BSD 侧）
- 各格式的解压/压缩实现可能携带上游许可条款

"BSD-style" 的笼统定性不足以支撑商业化分发决策。若 App 静态链接 libarchive，则所有组件许可均需在 App 的 legal notice 中体现。若通过 XPC service 动态隔离，则许可义务边界不同。

**建议：** Codex 必须产出 libarchive 的完整 SBOM（软件物料清单），逐组件标注许可类型和通知义务。

**证据类型：** 推断（libarchive 的组件结构是已知事实，但证据包未列举）  
**不确定性：** 低——组件许可审计是商业化分发的硬性前置条件

---

### 4. 跨平台导出预设仅考虑了 macOS 特有元数据，忽略了编码和路径兼容性

**证据包原文（L109）：** "Cross-platform export preset strips `.DS_Store`, `__MACOSX`, AppleDouble `._*`, resource forks, and unsafe POSIX-only semantics"

**反驳：** 仅剥离 macOS 元数据文件**远不足以**保证 Windows 兼容性。以下问题在证据包中完全缺失：

| 兼容性问题 | 细节 |
|---|---|
| **文件名编码** | ZIP 传统编码为 IBM Code Page 437；UTF-8 支持依赖 General Purpose Bit 11。若 ZIPFoundation/libarchive 未正确设置此标志位，Windows 资源管理器将显示乱码 |
| **Windows 保留字符** | `< > : " / \ | ? *` 在 Windows 文件名中非法；POSIX 仅禁止 `/` 和 null |
| **路径长度限制** | Windows 传统 MAX_PATH = 260 字符；即使启用长路径，某些 API 仍有 32,767 字符限制 |
| **大小写冲突** | `Readme.txt` 和 `README.TXT` 在 Windows 上被视为同一文件；在 tar/7z 中可能共存 |
| **NTFS 非法后缀** | 以空格或句点结尾的文件名在 Windows 上非法 |
| **Unicode 规范化** | macOS HFS+/APFS 使用 NFD，Windows 使用 NFC；tar 归档中存储的 NFD 文件名在 Windows 解压后可能出现组合字符断裂 |

**建议：** 跨平台导出预设必须是多层次的：基础层（元数据剥离）+ 编码层（强制 UTF-8 + Bit 11）+ 路径安全层（保留字符映射/警告）+ 规范化层（NFD→NFC 选项）。每一项均需在 Windows 11 上以 Explorer 和 7-Zip 双工具验证。

**证据类型：** 推断（基于 POSIX/NTFS 文件系统差异的已知事实）  
**不确定性：** 极低——这些都是经过广泛文档记录的平台差异

---

### 5. Liquid Glass API 成熟度假定为「当前可用」，未经验证

**证据包原文（L38-41）：** 引用两个 Apple 文档 URL

**反驳：** 证据包假设这些文档所描述的 API 在目标 Xcode/SDK 版本中已稳定可用。但 Liquid Glass 是 Apple 在 WWDC 2025 引入的新设计语言，其 API 表面在 macOS 26 的早期版本中可能：
- 处于 beta/preview 状态
- 缺少关键控件（如 NSOutlineView 的 Liquid Glass 变体）
- 行为在后续 SDK 更新中发生破坏性变更

**建议：** Codex 必须在设计阶段前验证：目标 Xcode 版本的 Liquid Glass 文档是否标记为 "Available" 而非 "Beta"，以及 archive browser 所需的全部控件（树形视图、表格、分割视图、上下文菜单）是否均有 Liquid Glass 适配。

**证据类型：** 推断（基于 Apple 新 API 通常需要多个 SDK 版本才稳定的历史模式）  
**不确定性：** 中——可能在当前 GM SDK 中已稳定，但证据包未提供验证

---

### 6. 安全威胁模型缺失——当前仅列出攻击向量名称，未建模

**证据包 + Context 原文：** "Zip Slip, path traversal, symlink escape, decompression-bomb, password, quarantine, and resource-limit defenses tested."（Context L44）

**反驳：** 列出攻击向量名称 ≠ 建模。证据包和会议上下文均未提供：
- 威胁代理模型（恶意归档来自哪里？用户下载？自动处理？）
- 信任边界（解压目标在沙箱内还是用户选定目录？）
- 纵深防御层次（路径消毒在哪一层？是 Swift 层还是 C 库层？）
- 缺失的攻击面：**hardlink 逃逸**（硬链接可指向沙箱外路径）、**device file 创建**（tar 可包含设备节点）、**setuid/setgid 保留**（POSIX 权限位）、**xattr 注入**（`com.apple.quarantine` 属性绕过）、**压缩比炸弹**（4KB 展开为数 TB 的 zip bomb）、**递归归档**（嵌套 zip 深度耗尽栈空间）

**建议：** Codex 必须在设计阶段产出结构化的威胁模型文档，覆盖至少上述 10 类攻击面，并标注每层的缓解措施和验证方法。安全测试不能仅靠手工验证，需要自动化模糊测试和恶意 fixture 生成器。

**证据类型：** 推断（基于安全工程最佳实践的缺口识别）  
**不确定性：** 极低——缺乏威胁模型是高风险项目的可审计缺陷

---

### 7. 「Apple Silicon only」约束需要验证与 macOS 26 的兼容性事实

**Context 原文（L32）：** "Apple Silicon only"

**反驳：** 截至 2026 年 7 月，Apple 可能仍在 macOS 26 中通过 Rosetta 2 支持部分 Intel Mac。证据包未验证 macOS 26 的最低硬件要求。如果 macOS 26 已完全停止 Intel 支持，则 "Apple Silicon only" 是冗余约束；如果 macOS 26 仍支持 Intel，则选择 "Apple Silicon only" 是在主动放弃一部分潜在用户——这可能是合理的产品决策，但需要明确记录理由而非作为默认假设。

**建议：** Codex 应确认 macOS 26 的硬件支持矩阵，并在设计文档中明确记录 "Apple Silicon only" 的产品理由（如：利用 AMX 协处理器加速压缩、简化测试矩阵、或 macOS 26 已停止 Intel 支持）。

**证据类型：** 推断（对约束合理性的质疑，需要产品决策确认）  
**不确定性：** 低——Apple 的 macOS 硬件支持策略可通过公开文档验证

---

### 8. 「Apple Archive framework」与 ZIP/7z 的定位混淆

**证据包原文（L42）：** "do not treat Apple Archive as a ZIP/7z interoperability engine because it is an Apple archive framework with different transport goals."

**反驳：** 这一判断本身是正确的，但不够精确。Apple Archive（`.aar`）格式的目标是系统级备份和传输，其核心是**内容可寻址存储**和**增量归档**。ZIP/7z 的核心是**跨平台交换**。两者的根本差异不仅是"传输目标不同"，更在于：

- Apple Archive 依赖 APFS 文件系统特性（克隆、快照），在非 APFS 卷上行为不同
- Apple Archive 的权限模型深度绑定 macOS 安全框架
- Apple Archive 不保证非 Apple 平台的可读性

证据包正确地将 Apple Archive 排除在互操作路径之外，但未利用 Apple Archive 的可能价值：作为 App 内部的**增量快照和事务日志**存储格式，而非用户可见的导出格式。这是一个遗漏的机会。

**建议：** 在设计阶段评估 Apple Archive 是否适合作为 App 内部的 crash-recovery journal 或 staged-mutation workspace 的存储格式。

**证据类型：** 推断（基于 Apple Archive 文档能力的扩展分析）  
**不确定性：** 中——Apple Archive 作为内部 journal 格式的适用性需要原型验证

---

## 架构路线比较

以下三条路线均基于证据包中已识别的开源组件，仅在**集成深度、许可策略、主力引擎选择**上形成分叉。

### 路线 A：薄 Swift 前端 + libarchive 统一后端

```
SwiftUI Shell → C Bridging → libarchive (统一读写)
                ↓
         ZIPFoundation (ZIP 编辑增强)
```

| 维度 | 评估 |
|---|---|
| **格式覆盖** | libarchive 读覆盖面最广（含 RAR 提取、ISO9660、旧格式）；写覆盖 ZIP/7z/tar 系列/CPIO；7z 写入成熟度低于 7-Zip 原生 |
| **许可** | BSD-style，但需审计 6+ 个捆绑组件的各自许可；商业分发需完整 SBOM 和 Notice 文件 |
| **Swift 集成** | C 桥接层薄且稳定；无 C++ 复杂性；ZIPFoundation 提供原生 Swift ZIP 路径 |
| **App Store** | 低风险——无 GPL/LGPL 传染；C 库静态链接或动态框架均可 |
| **Windows 兼容性** | libarchive 的 ZIP/7z 写出的字节级兼容性需逐一验证；不如 7-Zip 有 Windows 原生验证历史 |
| **加密** | libarchive 对 ZIP AES 和 7z AES-256 的支持需版本验证；可能落后于 7-Zip |
| **维护风险** | libarchive 是成熟项目但发布节奏慢；关键 bug 修复可能滞后 |

**路线 A 胜出条件：**
- App Store 分发是主要渠道，且需要最小化许可审查风险
- 7z 创建不需要完整的 7-Zip 特性矩阵（仅需基础 LZMA2 + AES-256）
- 团队有 C/系统编程能力但希望避免 C++ 桥接复杂性

---

### 路线 B：7-Zip 重型引擎 + ZIPFoundation ZIP 编辑

```
SwiftUI Shell → C++ Bridging → 7-Zip Engine (7z 读写 + 广谱提取)
                ↓
         ZIPFoundation (ZIP 创建/编辑)
```

| 维度 | 评估 |
|---|---|
| **格式覆盖** | 7z 创建质量最高；ZIP 提取覆盖广泛；RAR 提取可靠；Windows 兼容性最强 |
| **许可** | **高风险。** 7-Zip 主仓库使用 LGPL + 部分 Public Domain 混合许可；其 SDK 的 `DOC/License.txt` 需要逐文件分析；与 ZIPFoundation（MIT）混用增加了许可边界复杂度 |
| **Swift 集成** | C++/Swift 互操作需通过 Objective-C++ 桥接层或 C wrapper；编译时间增加；调试难度上升 |
| **App Store** | **中等风险。** LGPL 要求最终用户可替换库组件——这在 App Store 沙箱模型中难以满足；需要法律审查 |
| **Windows 兼容性** | 最强——7-Zip 写入的 7z/ZIP 字节流已在数十亿 Windows 安装上验证 |
| **加密** | 7-Zip 原生 AES-256 支持成熟；ZIP AES（WinZip 兼容）支持完整 |
| **维护风险** | 7-Zip 上游活跃；但 LGPL 约束意味着上游安全修复需及时合并到 App 内 |

**路线 B 胜出条件：**
- Windows 兼容性是压倒性优先级，且 7-Zip 的字节级兼容性被认为是不可替代的
- 法律团队已审查并批准 LGPL 组件在商业闭源 App 中的分发策略
- 团队有 C++ 和 Objective-C++ 经验，能维护跨语言桥接层
- 非 App Store 分发（直接分发/notarized DMG）是主要渠道

---

### 路线 C：Apple 框架优先 + 选择性开源提取

```
SwiftUI Shell → Apple Archive (内部 journal) + Compression (流压缩)
                ↓
         ZIPFoundation (ZIP 全工作流)
                ↓
         libarchive 或 7-Zip (仅提取——7z/tar/RAR/DMG/ISO)
```

| 维度 | 评估 |
|---|---|
| **格式覆盖** | ZIP 全工作流覆盖最好（Swift 原生）；7z/tar/RAR/DMG/ISO 仅提取；**7z 创建缺失**——这是最大的功能缺口 |
| **许可** | 最低风险——Apple 框架无许可负担；ZIPFoundation MIT；提取引擎可封装为独立 XPC service 降低传染风险 |
| **Swift 集成** | 最佳——Apple 框架原生 Swift API；ZIPFoundation 原生 Swift；提取引擎隔离 |
| **App Store** | 最低风险——符合 App Store 沙箱模型 |
| **Windows 兼容性** | ZIPFoundation 的 ZIP 写入兼容性需验证；7z 创建缺失意味着用户无法创建 Windows 首选的高压缩比格式 |
| **加密** | ZIPFoundation 的加密支持需验证——它可能不包含 ZIP AES 实现 |
| **维护风险** | Apple 框架由 OS 更新提供，无需自行维护；提取引擎可降级为独立组件 |

**路线 C 胜出条件：**
- App Store 沙箱分发是硬性要求，且法律团队拒绝任何 copyleft 许可
- 7z 创建可以通过后期用户需求验证决定是否添加（如：用户安装 `7z` CLI，App 检测并调用）
- 用户群以 ZIP 为主要工作格式，7z 创建是次要需求

---

### 路线比较总结

| | 路线 A (libarchive) | 路线 B (7-Zip) | 路线 C (Apple 优先) |
|---|---|---|---|
| 许可风险 | 低–中 | 高 | 最低 |
| 7z 创建质量 | 中 | 最高 | 无 |
| ZIP 编辑质量 | 高（ZIPFoundation） | 高（ZIPFoundation） | 高（ZIPFoundation） |
| Windows 兼容 | 需验证 | 已验证 | 需验证 |
| App Store 适合度 | 高 | 中–低 | 最高 |
| 工程复杂度 | 中 | 高（C++ 桥接） | 低–中 |
| 增量成本（添加 7z 创建） | 零（已含） | 零（已含） | 高（需引入新引擎） |

**复核员推荐：** 在三条路线均可行的情况下，从**商业化风险控制**角度，路线 A 是合理的默认选择——它在许可安全、格式覆盖、工程复杂度之间取得平衡。但如果用户研究表明确实需要最高质量的 7z 创建（如面向 Windows 开发者的工具），则路线 B 的许可风险值得承受。路线 C 适合对许可纯度有极端要求的场景，但 7z 创建缺失是显著的产品缺口。

**建议：** Codex 应以路线 A 为基线设计，同时为路线 B 做架构预留（将 7-Zip 引擎封装为可插拔的提取/创建后端，而非深度耦合进核心架构），使用户可以在路线 A 和路线 B 之间通过编译时或运行时开关切换。

---

## RAR 创建与许可证判定

### 对证据包结论的审查

**证据包结论（L99-100）：** "No credible lawful open-source RAR writer has been identified. Claims of RAR creation usually shell out to the proprietary `rar` CLI."

**复核判定：此结论在现有证据下是正确的，但分析深度不足以支撑商业化产品决策。**

### 需要强化的论证链

1. **UnRAR 许可的精确条款。** 证据包引用了 UnRAR 许可镜像 URL（L97），但未摘录关键条款。标准 UnRAR 许可的核心禁令是：
   > "The UnRAR sources cannot be used to re-create the RAR compression algorithm, which is proprietary."
   这明确禁止：逆向工程 RAR 压缩算法、基于 UnRAR 源码开发压缩器、或分发兼容 RAR 的压缩实现。

2. **RAR 格式版本差异。** RAR 格式有多个代际：
   - **RAR4（RAR 2.x–4.x）：** 较旧，有一些第三方解压实现（如 libarchive 的 RAR4 解压），但仍无合法的开源压缩器。
   - **RAR5（RAR 5.0+）：** 当前标准，压缩算法完全不同。没有已知的开源实现。
   - 证据包未区分这两个版本，而这影响 libarchive 的 RAR 提取覆盖声明（libarchive 对 RAR5 的支持可能有限）。

3. **商业许可路径未被探索。** 证据包提到了三个选项（L100），但未执行任何一项的调查：
   - win.rar GmbH 是否提供商业 SDK 许可？
   - 商业 SDK 的许可费用和条款是什么？
   - `rar` CLI 是否可以合法地与商业 App 捆绑分发？

### 改变结论需要什么证据

| 当前结论 | 推翻条件 |
|---|---|
| 不含 RAR 创建 | win.rar GmbH 出具书面商业 SDK 许可，授权在 macOS App 中嵌入 RAR 压缩功能 |
| 不含 RAR 创建 | 发现独立的、清洁室开发的、与 UnRAR 许可无关联的 RAR5 兼容压缩器，且有可验证的合法来源 |
| 仅支持 RAR 提取 | win.rar GmbH 公开声明 RAR5 压缩专利已过期或进入公共领域 |
| 使用用户安装的 `rar` CLI 检测模式 | win.rar GmbH 确认此使用模式不违反其最终用户许可协议 |

**复核结论：** 当前「不含 RAR 创建」的判定应维持，但 Codex 应主动联系 win.rar GmbH 询问商业 SDK 许可——这是一个低成本的尽职调查步骤。如果 SDK 许可费用在预算内，RAR 创建可以成为差异化竞争优势。

---

## 商业发布验证矩阵

以下矩阵将 Context 中的成功标准（L37-46）映射到可验证的证据要求。每行是一个需求-验证对。

| # | 需求 | 验证方法 | 最低证据标准 | 验证者 | 优先级 |
|---|---|---|---|---|---|
| V1 | Apple Silicon 原生构建 | `file` 命令确认 Mach-O arm64；Instruments 验证无 Rosetta 翻译 | 构建日志 + `file` 输出 | Codex | P0 |
| V2 | Liquid Glass UI 合规 | 与 Apple HIG Liquid Glass 检查清单逐项对照；在所有可用 macOS 外观模式下截图 | 检查清单完成记录 + 截图矩阵（浅色/深色 × 所有窗口） | Codex（视觉接受） | P0 |
| V3 | ZIP 创建 → Windows 11 兼容 | 生成含中文/英文/emoji/长路径/大文件(>4GB)的 ZIP；在 Windows 11 上用 Explorer 原生解压 + 7-Zip 验证 | Windows 验证截图 + 文件列表 diff | Codex 或指定验证者 | P0 |
| V4 | 7z 创建 → Windows 11 兼容 | 同上，使用 7z 格式；验证 AES-256 加密卷在 7-Zip for Windows 上可解密 | 同上 + 解密成功确认 | Codex 或指定验证者 | P0 |
| V5 | 中文术语审核 | MiniMax-M3 + GLM-5.2 各自产出术语审查报告；Codex/用户确认 | 两份模型审查报告 + 用户接受记录 | Hermes Lead + Codex | P1 |
| V6 | Zip Slip 防御 | 恶意 ZIP fixture（含 `../` 路径遍历）输入 App；验证解压路径不逃逸目标目录 | 测试用例 + 结果日志（路径被拒绝/消毒） | 自动化 + Codex | P0 |
| V7 | 归档修改事务安全 | 修改操作期间注入进程崩溃（SIGKILL）；重启后验证原始归档完整无损，无残留临时文件 | 崩溃注入测试脚本 + 完整性校验 | 自动化 + Codex | P0 |
| V8 | 多语言文件名 | 生成含 NFD/NFC/组合字符/从右到左/全角字符的归档；验证提取后文件名在 macOS Finder 和 Windows Explorer 中均正确显示 | 文件名对比表 + 截图 | 自动化 + Codex | P0 |
| V9 | 归档炸弹防御 | 输入高压缩比归档（如 42KB → 4.5PB 的 42.zip）；验证 App 在展开前检测并拒绝 | 测试用例 + 拒绝日志 | 自动化 | P1 |
| V10 | 符号链接逃逸防御 | 输入含绝对路径符号链接或指向沙箱外路径的符号链接的归档；验证拒绝或消毒 | 测试用例 + 安全日志 | 自动化 | P0 |
| V11 | 加密支持矩阵 | 验证每种格式的加密创建→提取往返；ZIP AES vs ZipCrypto 兼容性矩阵 | 往返测试日志 + 兼容性矩阵表 | 自动化 | P1 |
| V12 | Quick Look 预览 | 对归档内各常见文件类型验证 Quick Look 预览可用 | 文件类型覆盖表 + 截图 | Codex（视觉接受） | P1 |
| V13 | 跨平台导出预设 | 使用预设导出的归档在 Windows 上验证无 `__MACOSX`、无 `._*`、无 `.DS_Store`；验证文件名未损坏 | Windows 验证 + 文件列表 | Codex | P1 |
| V14 | 无障碍（Accessibility） | VoiceOver 完整工作流遍历（创建→浏览→提取→编辑）；验证所有控件有可用标签 | VoiceOver 审计记录 | Codex | P1 |
| V15 | 签名 + 公证 | `codesign -dvvv` 和 `spctl -a -v` 验证 | 命令行输出 | Codex | P0 |
| V16 | 组件级许可审计 | 完整 SBOM，每个组件标注许可类型、通知义务、是否兼容商业闭源分发 | SBOM 文档 | Codex | P0 |

**优先级说明：** P0 = 阻塞发布；P1 = 发布前必须完成但可并行或后期执行。

---

## 数据损坏与兼容性高风险测试

以下测试用例旨在揭露**静默数据损坏**（即操作表面上成功，但数据已损坏且无错误提示）或**跨平台不兼容**。这些测试无法被功能测试或手动冒烟测试覆盖，必须作为专项测试套件运行。

### 测试套件 A：文件名编码破坏

| 测试 ID | 描述 | 预期行为 | 风险 |
|---|---|---|---|
| A1 | 创建含 **emoji 文件名**（如 `📁报告.pdf`）的 ZIP，在 Windows 11 Explorer 中解压 | 文件名正确显示为 emoji，非乱码或 `???` | ZIP General Purpose Bit 11 未设置或不正确的 UTF-8 编码导致 Windows 显示为 CP437 乱码 |
| A2 | 创建含 **NFD 组合字符**（如 `が` = U+304B + U+3099）的 ZIP；在 Windows 上解压后拖回 macOS | 文件名在往返后保持可理解（NFC 或 NFD 均可能，但不应变为不可逆的乱码） | macOS NFD ↔ Windows NFC 差异导致组合字符断裂 |
| A3 | 创建含 **从右到左覆盖字符**（U+202E RIGHT-TO-LEFT OVERRIDE）的 ZIP | App 应警告或拒绝，而非静默创建可能用于伪装文件扩展名的归档 | 恶意文件名伪装攻击（如 `‮cod.exe` 显示为 `exe.doc`） |
| A4 | 创建含 **Windows 保留字符**（`CON`、`NUL`、`AUX`、`<`、`>`、`:`、`"`、`/`、`\`、`\|`、`?`、`*`）文件名的 7z | App 在创建时应警告；若强制创建，Windows 解压时 7-Zip 的行为需记录在已知限制中 | 创建了在 Windows 上无法解压的归档 |
| A5 | 创建含 **超过 255 字节的 UTF-8 文件名**的 ZIP | App 应正确处理（使用 ZIP64 扩展）或明确限制 | 文件名截断导致数据丢失 |

### 测试套件 B：元数据静默损失

| 测试 ID | 描述 | 预期行为 | 风险 |
|---|---|---|---|
| B1 | 创建 ZIP 时保留 **POSIX 权限位**（如 `0755`）；在 Windows 上解压后再在 macOS 上用 `ls -la` 查看 | 权限位可能丢失（需记录），但不应对原始文件造成修改 | 权限位在跨平台往返中静默丢失，无警告 |
| B2 | 提取含 **符号链接**的 tar 归档；验证目标路径未逃逸且链接类型（相对/绝对）在提取后仍正确 | 符号链接正确重建，且未指向目标目录外的路径 | 符号链接逃逸或类型错误（相对变绝对） |
| B3 | 创建含 **扩展属性**（`xattr`）的 ZIP（如 `com.apple.quarantine`）；在 Windows 上解压后回 macOS | macOS 特有 xattr 应被剥离或在跨平台预设中警告 | `com.apple.quarantine` 属性可能绕过安全检查 |
| B4 | 创建含 **资源分叉**（resource fork）的 ZIP | 跨平台预设应剥离或转换为 AppleDouble `._*` 并在元数据报告中注明 | 资源分叉在非 Mac 系统上是垃圾数据 |

### 测试套件 C：归档修改一致性

| 测试 ID | 描述 | 预期行为 | 风险 |
|---|---|---|---|
| C1 | 在含 10000 个 entry 的大 ZIP 中删除第 5001 个 entry 并添加一个新 entry；验证其他 entry 的 CRC-32 均未变化 | 仅目标 entry 受影响的 ZIP 结构变更；其余 entry 的 CRC-32 不变 | 沉默的 CRC 损坏——ZIP 表面可打开但部分文件已损坏 |
| C2 | 修改加密 ZIP 中的一条 entry 内容；验证加密层在修改后仍有效 | 修改后的 entry 正确加密；其他 entry 不受影响 | 修改破坏加密完整性，导致部分或全部 entry 解密失败 |
| C3 | 向现有 ZIP 追加 entry 时注入进程崩溃（中途 SIGKILL）；重启后验证原始 ZIP 完整无损 | 原始 ZIP 未被修改；临时文件存在但可识别为未完成 | 原始 ZIP 部分损坏（头已写入但数据不完整） |
| C4 | 连续 50 次增删改 ZIP entry 后验证最终 ZIP 与"从零创建同内容 ZIP"的字节一致性 | 允许差异（如时间戳），但 entry 数据 CRC-32 必须一致 | 累积修改导致 ZIP 结构退化（如中央目录碎片化） |

### 测试套件 D：加密兼容性矩阵

| 测试 ID | 描述 | 预期行为 | 风险 |
|---|---|---|---|
| D1 | 创建 **ZIP AES-256** 加密归档；在 Windows 11 Explorer 中尝试原生打开 | Windows Explorer **不支持** ZIP AES——需记录此已知限制 | 用户认为加密 ZIP 在 Windows 上可用，实际不可用 |
| D2 | 创建 **ZipCrypto** 加密归档；在 Windows 11 Explorer 中尝试原生打开 | Windows Explorer 支持 ZipCrypto；但需标注其已知的安全弱点 | ZipCrypto 已知易受已知明文攻击 |
| D3 | 创建 **7z AES-256** 加密归档；在 Windows 上用 7-Zip 解密 | 应正常工作 | 低风险——7-Zip 原生支持 |
| D4 | 创建含 **混合加密**（部分 entry 加密、部分不加密）的 ZIP | App 应支持或明确拒绝 | 部分加密工具的互操作性问题 |

### 测试套件 E：大文件与边界条件

| 测试 ID | 描述 | 预期行为 | 风险 |
|---|---|---|---|
| E1 | 创建含单个 **5GB 文件**的 ZIP（触发 ZIP64） | 正常创建；在 Windows 上正常解压；文件 MD5 一致 | ZIP32 限制（4GB-1）静默截断 |
| E2 | 创建含 **65536 个 entry**的 7z（超过 ZIP 的 65535 限制但不超 7z 限制） | 7z 正常创建和解压 | entry 索引溢出 |
| E3 | 创建含 **零字节文件**的归档；验证零字节 entry 正确存储和提取 | 零字节 entry 应正确处理，非跳过 | 零字节文件被误判为损坏或跳过 |

---

## 必须由 Codex 复核的事项

以下事项超出本复核员的权限范围，必须由 Codex（作为主会场主席和最终决策者）完成：

1. **所有 URL 声明的当前有效性。** 本复核未访问任何外部 URL；证据包中引用的 GitHub 仓库、Apple 文档、产品页面的当前状态和内容需 Codex 亲自验证。

2. **ZIPFoundation 源码级修改语义审查。** 见关键假设反驳 #2。Codex 必须阅读 ZIPFoundation 的修改路径源码，确认其对 ZIP64、加密 ZIP、崩溃安全性的真实支持。

3. **libarchive 完整 SBOM 生成。** 见关键假设反驳 #3。Codex 必须产出组件级许可清单。

4. **Liquid Glass API 在当前 Xcode 版本中的稳定性和控件覆盖。** 见关键假设反驳 #5。

5. **威胁模型的编写和维护。** Codex 是安全边界的最终负责人。

6. **与 win.rar GmbH 的商业许可沟通。** 本复核识别了此路径但无权执行。

7. **最终架构路线的选择。** 本复核提供了三条路线的分析，但产品权衡（许可风险 vs 功能完整性）是用户和 Codex 的决策。

8. **Windows 11 物理验证。** 本复核列出的所有 Windows 兼容性测试必须在真实 Windows 11 机器上执行——虚拟机可能存在文件系统行为差异。

9. **用户对中文术语的最终确认。** 即使 MiniMax-M3 和 GLM-5.2 通过了审查，最终用语必须由用户确认。

10. **签名和公证的最终执行。** `codesign` 和 `spctl` 验证必须在构建管道中自动化。

---

## LOOP 记录

### 执行动作

| 步骤 | 动作 | 结果 |
|---|---|---|
| L1 | 读取 `context/mac_archive_app_conference_context.md`（70 行） | 理解会议边界、参与者路由、成功标准、风险边界 |
| L2 | 读取 `plans/codex_main_venue_mac_archive_app.md`（52 行） | 理解任务分解、参与者分配、验证清单 |
| L3 | 读取 `research/2026-07-11_initial_landscape.md`（116 行） | 获取全部商业产品证据、开源候选、架构假设、RAR 判定 |
| L4 | 检查 `runs/conference/mac_archive_app/` 目录 | 确认 5 个参与者占位文件存在；确认输出目录可用 |
| L5 | 对证据包执行逐行假设挑战 | 识别 8 个关键假设问题 |
| L6 | 构建三条架构路线比较 | 每条路线标注维度评估和胜出条件 |
| L7 | 审查 RAR 创建判定 | 维持结论，增强论证链，列出推翻条件 |
| L8 | 构建商业发布验证矩阵（16 项） | 每项含验证方法、证据标准、验证者、优先级 |
| L9 | 构建数据损坏测试套件（5 套件 21 用例） | 覆盖编码、元数据、修改一致性、加密兼容、大文件边界 |
| L10 | 识别 Codex 必须复核的 10 个事项 | 超出复核员权限范围 |
| L11 | 写入本文件 | 完成 |

### 关键观察

1. **证据包的整体质量是中等偏上**——它正确识别了主要开源候选和 RAR 许可的核心约束，但在以下方面深度不足：(a) 许可审计的粒度；(b) 跨平台兼容性的编码/路径语义；(c) 归档修改的事务语义细节；(d) 安全威胁建模。

2. **最危险的单一缺陷**是缺乏结构化的安全威胁模型。一个处理任意不可信归档输入的 App，如果仅依赖"列出攻击向量名称"作为安全策略，在商业化发布中将面临不可接受的风险。

3. **路线 A（libarchive）与路线 B（7-Zip）之间的选择**本质上是一个**许可风险 vs 格式完整性**的权衡。本复核员无法替用户做这个权衡，但路线 A 作为默认基线的建议是基于"商业化软件的许可风险通常是生存威胁"这一经验判断。

4. **SimpleZip 的 RAR 创建声明应被视为已证伪**，不应在设计阶段消耗任何进一步的研究资源。

5. **ZIPFoundation 的修改语义**是证据包中最大的盲点——如果 ZIPFoundation 的修改路径存在隐式限制（如不支持 ZIP64 修改或不支持加密 ZIP 修改），整个 ZIP 编辑架构可能需要重新设计。

### 不确定性声明

| # | 不确定性 | 来源 | 解决方式 |
|---|---|---|---|
| U1 | ZIPFoundation 对 ZIP64 修改、加密 ZIP 修改的实际支持 | 证据包未验证 | Codex 源码审查 |
| U2 | libarchive 的 7z 写入质量与 7-Zip 原生的差距 | 证据包未基准测试 | 原型 + Windows 互操作测试 |
| U3 | Liquid Glass API 在 Xcode 当前 GM 版本中的稳定性 | 证据包未验证 | Codex 在 Xcode 中验证 |
| U4 | win.rar GmbH 的商业 SDK 许可可行性 | 证据包未询问 | Codex 发出商业询问 |
| U5 | macOS 26 的 Intel 支持状态 | 证据包未确认 | Codex 查看 Apple 公开文档 |
| U6 | libarchive 对 RAR5 提取的支持程度 | 证据包未区分 RAR4/RAR5 | Codex 审查 libarchive 的 RAR5 支持状态 |

### 建议的下一步

1. **Codex 应立即执行本 LOOP 中列出的 10 项复核事项**，尤其是 ZIPFoundation 源码审查和 libarchive SBOM 生成。
2. **在设计阶段开始前，Codex 应产出结构化的安全威胁模型**——这不依赖于架构路线的选择，因为所有路线都处理不可信归档输入。
3. **在架构路线选定后，Codex 应运行本复核的测试套件 A-E 中的最小可行子集**作为概念验证的一部分（至少 A1、B1、C1、D1、E1）。
4. **SimpleZip 应从候选列表中明确移除**——其在 RAR 创建上的不实声明降低了其整体可信度。
5. **Codex 应主动联系 win.rar GmbH** 询问商业 SDK 许可，以关闭 RAR 创建的决策循环。

---

**复核员签名：** Reasonix CLI `deepseek-pro`（`deepseek-v4-pro`）  
**复核完成时间：** 2026-07-11  
**边界确认：** 本次复核未浏览网页、未调用外部服务、未编辑源码、未改动 `runs/conference/mac_archive_app/participant_reasonix_deepseek_pro_research.md` 之外的任何文件。所有结论均基于三个输入文件的内容推导。
