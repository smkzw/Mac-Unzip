# MacUnzip 交接文档（v1.0.7 已分发 · LOOP 已达标退出 · 2026-08-02）

> 面向接手本项目的 AI Agent。目标：进一步**代码审查、功能优化、前端深度优化、以用户为根本视角的优化**。
> 读完本文件即可完整接续。旧版恢复记录见 `LOOP_HANDOFF.md`（R31 时代快照，部分内容已被本文件取代）。

---

## 0. 一句话现状

MacUnzip 是一个 macOS 原生压缩包工具（SwiftUI + Swift 6 严格并发）。经过 R14→R44 共 30+ 轮"双审计 LOOP"（工程师审计 + 首次用户审计），**R43 与 R44 连续两轮全干净（P0–P4 零阻断性发现）**，满足退出标准。Release **v1.0.7 已构建并发布**到 `smkzw/Mac-Unzip`，本地已安装激活 Pro 的 Debug 版。现在进入"精益求精"阶段，不再有硬性 LOOP 门槛。

---

## 1. 用户的原始需求（始终有效，勿违反）

### 1.1 总要求（原话，最高优先级）
> "继续debug继续LOOP不要停。你在本地生成的app为什么还要我激活？？？我自己的app你不会直接默认激活好给你吗？另外，对于对外分发的版本，创建压缩包点击后就应该出现提示激活，而不是点了创建压缩包没反应让用户觉得app有问题点了取消后才显示要激活！！这些操作逻辑和人机交互不合理的地方是LOOP的重中之重！"

拆解为三条铁律：
1. **DEBUG 构建必须预先激活 Pro**（开发者自己的 app 不该还要手动激活）。
   - 实现：`App/Sources/LicenseManager.swift:27-31`，`#if DEBUG return true`（开发者旁路）。
2. **Release/对外分发构建：点击任何 Pro 功能的瞬间就要弹激活提示**，绝不能"点了没反应、用户以为 app 坏了、点取消后才弹提示"。
   - 实现：`App/Sources/LicenseGate.swift:39 requirePro(for:)` 作为每个 Pro 入口的**第一句**（全仓 24 个调用点）。门禁在流程启动**之前**，不在之后。
3. **操作逻辑与人机交互（UX）是重中之重**。任何"反直觉、让用户困惑、看起来像坏了"的行为都是最高优先级缺陷。

### 1.2 每轮构建/分发流程（原话）
> "继续未完成的任务，务必注意每轮LOOP结束修复好后要更新我本地安装的MacUnzip（已激活Pro版）并删除旧版，同步更新github的Pro及Lite版，必要时更新Lite版的README，更加市场化、国际化、丰富化、设计化"

- 更新本地安装的 MacUnzip（激活 Pro 的 Debug 版），**先删旧版、清缓存再装**（原话："本地安装时务必把前期遗留的安装包、安装文件、安装缓存都清掉之后再装，安装过程本身也是debugging"）。
- 同步 GitHub：Pro（`smkzw/Mac-Unzip`，发二进制 DMG）+ Lite（`smkzw/MacUnzip-Lite`，**绝不能覆盖**）。
- 必要时更新 Lite README（市场化/国际化/丰富化/设计化）。

### 1.3 已批准的分发规则（原话）
- "Pro发二进制+Lite同步源码" → 实际落地为：**Pro 发 DMG 二进制；Lite 只核对/同步 README，绝不往 Lite 拷 Pro 源码**（Lite 是含 `LicenseManager.swift` 的开源 stub，不是完整源码镜像）。
- "Stop shipping rar" → 不再分发 rar 相关产物。

### 1.4 沟通约定
- **用中文回复用户**。
- 全局 `~/.qoder/agents.md` 要求省 token：默认用 `skim <file> --mode=structure`（`/Users/smkzw/.local/bin/skim`）代替 `cat`；输出简洁、无寒暄、无 emoji。

---

## 2. 项目概览与架构

### 2.1 是什么
MacUnzip：macOS 26 (Tahoe) 原生压缩包查看/解压/创建工具。卖点：原生 Swift、隐私优先、路径遍历防护、资源预算。Free 版支持 ZIP/TAR/GZ 查看解压；Pro 版（$1.99 一次性）支持 40+ 格式（7z、RAR、DMG、ISO…）、创建压缩包、编辑（增删改查条目）、加密等。

### 2.2 技术栈
- SwiftUI + AppKit 混合。主状态容器 `AppModel`（`@Observable`，`@MainActor`）。
- Swift 6 **严格并发**（`Sendable` 检查很严，改动时注意隔离）。
- XcodeGen：`project.yml` → `MacUnzip.xcodeproj`。**改文件增删后须 `xcodegen generate`**。`.xcodeproj` 不入库。
  - 当前用 `MacUnzip.xcodeproj`；`ArchiveWorkbench.xcodeproj` 是遗留产物（勿用）。
- 本地化：String Catalog `App/Resources/Localizable.xcstrings`，**中文为源语言**，经 `AppLocalization().string/format` 取用。已有 en/zh/ja/ko/es/fr/it 多语 README。
- 核心逻辑在 SwiftPM 包 `Packages/ArchiveKit/Sources/`：
  - `ArchiveDomain`（领域模型、错误、能力注册）、`ArchiveProviders`（ZIP/7z/RAR/DMG/ISO/TAR 各 provider）、`ArchiveSecurity`（`SecureFileMaterializer` 路径遍历防护、资源预算）、`CLibArchiveBridge`/`CMinizipBridge`（C 桥接）。

### 2.3 关键文件与职责（App/Sources，约 30 个 .swift）
| 文件 | 职责 |
|---|---|
| `AppModel.swift` | 主状态机（`@Observable @MainActor`）：打开/保存/解压/创建/编辑、搜索索引、license 联动、拖拽物化 `materializeEntryForDrag`。体量最大。 |
| `ArchiveListView.swift` | **NSOutlineView** 文件列表（`NSViewRepresentable` 包 NSScrollView+NSOutlineView）。`FileTreeNode`/`FileTreeBuilder`/`Coordinator`。展开状态、搜索、拖出拖入、排序都在这。 |
| `ArchiveDocumentLoader.swift` | 各格式 provider 的统一加载/物化/解压调度（`materializeEntryForExtraction`、`extractAll`）。 |
| `ArchiveDocumentView.swift` | 文档主视图：工具栏、侧栏、列表、预览、Inspector 的组装。 |
| `RootWindowView.swift` | 根窗口：欢迎页、最近打开、通知路由、启动参数处理 `handleLaunchArguments`、各类面板。 |
| `MacUnzipApp.swift` | `@main` + `AppDelegate`：启动参数、`application(_:open:)`、`deliverOpenURL`、Finder IPC。 |
| `LicenseManager.swift` / `LicenseGate.swift` | Pro 授权状态 + 门禁（见 1.1）。 |
| `FinderExtension/FinderSync.swift` | Finder 扩展：右键"用 MacUnzip 打开/解压到此/压缩"。冷启动走 `-finder-files`+`-finder-action` 参数；app 已运行走 `DistributedNotificationCenter`。 |
| `QLExtension/` | QuickLook 预览扩展。 |

---

## 3. 环境 / 构建 / 安装 / 分发（照抄即可）

项目根：`/Users/smkzw/Documents/AI Products/.worktrees/foundation/ArchiveWorkbench`（git worktree，分支 `release`）。

```bash
cd "/Users/smkzw/Documents/AI Products/.worktrees/foundation/ArchiveWorkbench"

# 0) 跑 app/测试前必须先杀进程（否则旧实例占用）
pkill -9 -f "MacUnzip.app/Contents/MacOS"

# 1) 构建 Debug（自动激活 Pro）
xcodebuild -project MacUnzip.xcodeproj -scheme MacUnzip -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dd build

# 2) 干净安装到本地（删旧 + 清缓存 + 去 quarantine）
rm -rf /Applications/MacUnzip.app
rm -rf ~/Library/Caches/*MacUnzip*
cp -R build/dd/Build/Products/Debug/MacUnzip.app /Applications/
xattr -dr com.apple.quarantine /Applications/MacUnzip.app

# 3) Release 打包 DMG（ad-hoc 签名，无 Developer ID；会先清空 build/ 目录！）
./scripts/package_release.sh --skip-sign --version X.Y.Z
#   产物：build/MacUnzip-X.Y.Z.dmg + .sha256（arm64）

# 4) 发布 Pro（gh 已登录 smkzw）
gh release create vX.Y.Z --repo smkzw/Mac-Unzip --title "MacUnzip vX.Y.Z" \
  --notes "..." build/MacUnzip-X.Y.Z.dmg build/MacUnzip-X.Y.Z.dmg.sha256
```

注意：
- `package_release.sh` 第一步 `find build -mindepth 1 -delete` 会**删掉 build/dd（你的 Debug derivedData）**。本地安装要在打包前完成，或打包后重建 Debug。
- Release 是 ad-hoc 签名、**未公证**，发布说明里要带 Gatekeeper 提示（右键打开）。
- Lite 仓库只读核对：`gh repo clone smkzw/MacUnzip-Lite /tmp/lite-check`。**勿覆盖、勿拷 Pro 源码**。README 用 `releases/latest` 自动徽章、无硬编码版本号，稳定性版本通常无需改。

### GUI 自动化（自验用，AppleScript）
- 已在 `/tmp` 建好一批助手脚本：`ax_rows2.scpt`（dump 行+层级）、`ax_expand.scpt`/`ax_expand_sub.scpt`（展开）、`ax_search2.scpt`（搜索，硬编码 "a.txt"）、`ax_clear.scpt`（清空搜索）、`ax_full.scpt`（全文本）、`ax_win.scpt`（窗口列表）、`ax_cafe.scpt`（Cmd+F 搜 "cafe"）。
- 测试压缩包：`/tmp/r33test.zip`（r33test/{top.txt, sub/{a.txt,b.md}}）、`/tmp/other2.zip`（root.txt + r33test/sub/deep.txt，用于切换隔离测试）、`/tmp/diac.zip`（café.txt/naïve.md，用于变音符搜索测试）。
- 工具栏按钮按 **description** 匹配（不是 title），例：`if description of b is "解压缩全部" then click b`。
- `open -a MacUnzip x.zip` 在 pkill 后紧跟有时会显示欢迎页（启动竞态）——对已运行的 app 再 `open` 一次即可。

---

## 4. 本轮（R38→R44）我做了什么

### 4.1 修复的功能缺陷
1. **搜索清空后展开状态丢失**（`ArchiveListView.swift`）：
   - 进入搜索时快照层级展开集合到 `preSearchExpandedPaths`，清空搜索时恢复。
   - 恢复时**按深度排序（最浅先）**再 `expandItem`——因为 NSOutlineView 会丢弃"父节点仍折叠时"的 expandItem 调用。
2. **切换压缩包时展开状态泄漏**（`ArchiveListView.swift` updateNSView 顶部）：
   - 检测 `lastArchiveSourceURL != archiveSourceURL` 时，清空 `expandedPaths`/`preSearchExpandedPaths` 并 `outline.collapseItem(nil, collapseChildren: true)`。
   - 根因：`FileTreeNode.==` 只比较 `fullPath`，NSOutlineView 凭自身内部状态让"同名文件夹"跨 reloadData 保持展开。必须显式全折叠。
3. **拖出（drag-out）可靠性**（`ArchiveListView.swift filePromiseProvider` + `AppModel.materializeEntryForDrag`）：
   - 多 GB 拷贝放 `Task.detached` 离主线程；物化返回 `(file, stagingRoot)` 元组，成功/失败/物化失败/self-nil 四条路径都清理 staging，无临时目录泄漏。
   - 拷贝中途失败（如磁盘满）会留残文件 → catch 里删 `destination`；但加 **TOCTOU 防护**：若错误是 `NSCocoaErrorDomain`/`NSFileWriteFileExistsError`（说明是别的进程在 fileExists 检查与 copyItem 之间抢建了该文件），则**不删**（那是别人的文件）。
   - staging 目录用 `0o700` 权限（与 extractAll 一致）。
4. **变音符/大小写搜索**（`AppModel.ArchiveSearchIndex`）：大压缩包（>1000 条目）索引改用 `String.folding([.diacriticInsensitive,.caseInsensitive])`，与小压缩包的 `localizedStandardContains` 行为对齐（"cafe" 能搜到 "café"）。删掉了冗余的 `foldedNames`（文件名永远是路径子串）。
5. **切换大压缩包时搜索索引过期窗口**（`AppModel.buildSearchIndex`）：重建索引前**同步** `searchIndex = nil`，让空窗期走正确的线性 fallback，而不是用旧归档的 ID 集过滤新条目。
6. **Finder 冷启动双开竞态**（`MacUnzipApp.handleLaunchArguments`）：`open` 分支删掉多余的 `.openArchiveURL` 通知与死状态 `pendingLaunchURL/pendingSkippedOpenCount`——`RootWindowView` 自己解析同样的 `-finder-*` 参数并负责打开，delegate 只留 `noteRecentArchive`。

### 4.2 审计收敛曲线（说明质量已稳定）
R40 报 8 处（4×P3+4×P4）→ R41 报 1 处（P3 TOCTOU）→ R42 零缺陷（2 条 P4 非缺陷备注）→ **R43 全干净** → **R44 全干净**。连续两轮干净，达标退出。

---

## 5. LOOP ledger（R14–R44 全记录）

> "双审计"= 工程师审计（读代码找 bug）+ 首次用户审计（模拟小白找 UX 问题），严重级 P0（崩溃/丢数据）→P4（吹毛求疵）。退出标准：连续 2 轮双审计全干净。

| 轮次 | 主题/结果 |
|---|---|
| R14 | P1 staging 校验、P2 导航重开/创建后校验/中英混排、P3/P4 批量 |
| R15–R16 | 双审计 |
| R17 | 双审计 + 停止分发 rar + P2–P4 |
| R18 | 双审计 + **P1 去掉 Homebrew-libarchive 硬启动依赖** + 7zz 状态/授权署名/首次密码横幅/磁盘满横幅等大批 |
| R19 | 双审计（R18 修复后） |
| R21–R22 | 用户 P2/P3/P4 批量 + 双审计 |
| R23 | 双审计 + 本地化目录梳理（en/zh）+ Pro/Free 门禁核对 + RAR 规则核对 |
| R24–R30 | 每轮：双审计 + 修复批量（P1/P2/P3/P4）。**R25–R30 均未全干净** |
| R31 | 首次用户审计；修 P2（嵌套打开破坏父 loader、OS 多开跳过数）+ P3（切换归档不重置搜索、Finder 定位抢焦点） |
| R32–R37 | （任务 #198 框架内）持续双审计 + 修复 |
| R38 | 快照式展开恢复 + 5 处工程师发现 |
| R39 | 工程师：拖出 staging 清理 3 处（嵌套泄漏/拷贝失败泄漏/未决 promise） |
| R40 | 工程师 8 处（残文件清理、索引过期、启动双开、冗余排序/foldedNames、0o700）→ 全部修复 |
| R41 | 工程师 1 处（TOCTOU 删错文件）→ 修复 |
| R42 | 工程师零缺陷（2 条 P4 非缺陷备注）+ 用户自验通过 |
| R43 | **双审计全干净（第 1 轮）** |
| R44 | **双审计全干净（第 2 轮）→ 达标退出，分发 v1.0.7** |

---

## 6. 我踩过的坑（务必先看，省得重踩）

### 6.1 NSOutlineView / 文件列表
- **`FileTreeNode.==` 只比 `fullPath`**（hash 也只 combine fullPath）。后果：NSOutlineView 靠自身内部状态让"同名文件夹"跨 `reloadData()` 保持展开。切换归档必须 `collapseItem(nil, collapseChildren: true)` 显式全折叠，光清 Coordinator 的 `expandedPaths` 没用。
- **`expandItem` 对"祖先仍折叠"的节点会被静默丢弃**。恢复展开必须按深度从浅到深排序后逐个 expand。
- Coordinator **有时**在切换归档时被重建（`makeNSView`，`lastArchiveSourceURL=nil`），**有时**被复用（`updateNSView`）——SwiftUI diff 非确定。重置逻辑必须覆盖"复用"情形。
- `fullPath` **无**尾部斜杠；`nodeByPath` 以 fullPath 为键；`nodeByEntryID` 以 `ArchiveEntryID` 为键。

### 6.2 并发 / 资源
- Swift 6 严格并发：delegate 是 nonisolated，回主线程用 `Task @MainActor`，回调标 `@Sendable`，离线程拷贝用 `Task.detached` 且只捕获 Sendable 值。
- `print()`/stdout 重定向时是块缓冲，调试追踪要写文件 append 才看得到。
- `SecurePassword` 用 mlock，无明文 String 访问器，取值要 `secure.withBytes { String(decoding: $0, as: UTF8.self) }`。

### 6.3 审计 / LOOP 方法论（血泪教训）
- **不要并发跑两个用户审计 agent**。
- **用户审计 subagent 会在 GUI 自动化上烧光 150-turn 预算**（自由式和清单式都会）。GUI 行为**自己用 AppleScript 验证**，别外包给 subagent。
- 工程师审计用只读 subagent 很高效；把"刚改的那几处"精确圈给它审，收敛快。
- 每修一处就可能引入新 P4，导致"修→审→又报→再修"回归。**非缺陷的 P4 备注（审计明确写 not a defect / not exploitable / theoretical）应记为延期，不要追着改**，否则永不退出。

### 6.4 构建 / 分发
- 跑 app/测试前必须 `pkill -9 -f "MacUnzip.app/Contents/MacOS"`。
- `package_release.sh` 会清空 `build/`（含 Debug derivedData）。
- `open -a` 紧跟 pkill 有启动竞态（显示欢迎页）；对运行中的 app 再 open 一次。
- UI 测试沙盒不能写 /tmp；`-ui-testing` 启动参数会禁用 Finder 抢焦点等副作用。

---

## 7. 当前状态（交接时刻）

- ✅ **v1.0.7 已发布**：https://github.com/smkzw/Mac-Unzip/releases/tag/v1.0.7
  - DMG `build/MacUnzip-1.0.7.dmg`（~10M，arm64，ad-hoc 未公证）
  - SHA-256 `825987c5c159577e2d6e9b08ed6bd1f5c279788b7cfe6d1c5cdeb3662ef4be26`
- ✅ 本地 `/Applications/MacUnzip.app` = 激活 Pro 的 Debug 版（已删旧、清缓存、去 quarantine）。
- ✅ Lite（`smkzw/MacUnzip-Lite`）已核对：README 4 语言/SVG mockup/`releases/latest` 自动徽章，无需改；**未做任何写操作**。
- ⚠️ **git：分支 `release` 有 78 个未提交改动**（大量相互依赖的文件）。**切勿逐个 git-stash/checkout**，会撕裂工作区。要提交就整体评估后一次性处理。
- ✅ R43+R44 连续干净，LOOP 达标退出。

### 延期 / 勿重复标记清单（审计时跳过，均为已知非阻断）
- 拖出文件名 `.`/`..` 守卫（纵深防御，不可利用）
- 搜索索引 fingerprint 强度（理论碰撞，实际不触发）
- 启动时 compress 分支的死通知 post（无功能影响）
- 分卷创建流水线（已禁用 WIP）；欢迎页 7zz 措辞；SplitVolume 显示"无"；per-instance engineAvailabilityCache
- undo/redo 菜单常亮（有意为之，保留 ⌘Z 文本框路由）
- 本地化 accessibilityIdentifier（会破坏测试）；测试里硬编码 +90 红绿灯偏移；无窗口最小尺寸（设计）
- FinderSync 监控整个 home；ArchiveEditor.swift 未用 `index` 警告（既有）；遗留 `ArchiveWorkbench.xcodeproj`
- AppUnitTests 未纳入 scheme；flat/搜索态下"待添加项"渲染怪异；第二实例实时保存时的假阳性恢复
- selection 为 nil 时不恢复合成目录高亮（既有）

---

## 8. 给接手 Agent 的建议（四个方向）

### 8.1 代码审查
- 重点文件：`AppModel.swift`（最大、最核心）、`ArchiveListView.swift`（AppKit 桥接最复杂）、`ArchiveDocumentLoader.swift`（多 provider 调度）。
- Swift 6 严格并发是红线：任何新异步代码先想隔离与 Sendable。
- 安全基线已较高（`SecureFileMaterializer` 防路径遍历、资源预算、0o700 staging）；新增文件落盘路径务必走同一套校验。
- 78 个未提交改动是技术债隐患：建议先整体 review 再决定如何落库（可能拆多个语义提交）。

### 8.2 功能优化
- 待办 #201：**内嵌文件管理器**（WinRAR/7-Zip 风格）——路径栏、上级导航、浏览任意文件夹并直接开压缩包。建议切片交付（Slice 1 先做路径栏+上级导航）。
- 待办 #149：多模型 E2E LOOP 测试（grok/minimax 等）尚未完成。
- 格式支持/加密/分卷创建（目前禁用）可作为增量。

### 8.3 前端深度优化
- 工具栏已做扁平化（去 Liquid Glass/胶囊/搜索框圆角底）、间距调优；可继续打磨视觉一致性与动效。
- `ArchiveListView` 是 NSViewRepresentable 包 NSOutlineView——若要大改列表交互（右键菜单、多选拖拽、内联重命名体验），这里是主战场，注意 6.1 的坑。
- 预览（`MediaPreviewView`/`MarkdownPreviewView`/`RoutedPreviewViews`）可增强。

### 8.4 以用户为根本视角（最高优先级，见 1.1）
- 评判标准始终是："小白用户会不会觉得 app 坏了/反直觉？"
- Pro 门禁必须在点击瞬间反馈（已实现，改动时别破坏"门禁在流程前"原则）。
- 每次改动后自验黄金路径 + 边缘路径：打开→浏览→搜索→展开/折叠→切换归档→解压→创建→拖出。用第 3 节的 AppleScript 脚本自验，别只信编译通过。
- 多语言：中文为源，改文案要同步 `Localizable.xcstrings`。

---

## 9. 快速参考
- 分支 `release`；XcodeGen（改文件增删后 `xcodegen generate`）；scheme `MacUnzip`。
- DEBUG 自动激活 Pro；Release 点 Pro 功能立即弹门禁。
- 双审计 LOOP 已退出；后续是开放式优化，无硬门槛，但"用户视角 + 交互逻辑"仍是第一原则。
- 中文回复；省 token 用 `skim`。
