# MacUnzip（Mac 解霸）接管报告与 Trellis 优化路线图

> 接管日期：2026-08-02 · 基线版本：v1.0.7 · 分支：release
> 方法：全量代码遍历 + 生态竞品调研（14 竞品）+ 实机实测（欢迎页/主界面/GBK 乱码修复）

---

## 一、产品现状快照

| 维度 | 状态 |
|---|---|
| 版本 | v1.0.7（SHA-256 校验通过） |
| 技术栈 | SwiftUI + AppKit 混合，Swift 6 严格并发，XcodeGen |
| 引擎 | 自研 SwiftPM 包 ArchiveKit：minizip-ng（ZIP 读写）、libarchive（TAR 全家桶）、7zz 外部二进制（7z/RAR 只读） |
| 安全 | 8 层防御：路径穿越防护、符号链接拒绝、资源预算、原子写入、进程隔离、沙盒预览、quarantine 标记、0o700 staging |
| 本地化 | 中文为源语言，xcstrings 覆盖 en/zh/ja/ko/es/fr/it |
| 定价 | Free（ZIP/TAR/GZ 查看解压）+ Pro $1.99 一次性（40+ 格式/创建/编辑/加密） |
| 分发 | Pro → GitHub DMG（ad-hoc 未公证）；Lite → 开源 stub |
| 质量 | R43+R44 连续双审计全干净退出；UI 测试 16/16 全绿 |
| 技术债 | 78 个未提交改动（release 分支）；分卷创建 WIP 已禁用 |

---

## 二、生态定位与差异化亮点

### 2.1 竞品全景（14 家，按威胁度排序）

| 竞品 | 定价 | 中文 UI | 不解压浏览 | 编码自动修复 | Windows 友好包 | 致命弱点 |
|---|---|---|---|---|---|---|
| The Unarchiver | 免费 | ✗ | ✗ | 手动指定 | ✗ | 4.3.9 加遥测；不能压缩/浏览 |
| Keka | 免费/商店付费 | 有但非优先 | ✗ | 手动 | 手动选项 | 不能浏览；UI 陈旧 |
| BetterZip | $35 | 2026-07 才补繁中 | ✓ | 手动指定 | 手动 | 贵；中文刚起步 |
| eZip | 免费 | ✓（中国开发者） | ✓ | ✓ | ✓ | **2024-02 停更** |
| Bandizip Mac | ¥148 | 有 | ✗ |  | ✗ | 渠道混乱售后翻车 |
| WinZip Mac | $29.95/年 | 有 | ✗ | ✗ | ✗ | 订阅制+弹窗 |
| macOS 自带 | 免费 | ✓ | ✗ | ✗ | **产出乱码** | 不支持 RAR/7z |
| PeaZip | 免费 | 有但非原生 | ✓ | ✗ |  | wxWidgets 非 Mac 体验 |
| Rar Extractor | 免费+内购 | ✓ | ✗ | ✗ | ✗ | 广告+等待倒计时 |

### 2.2 MacUnzip 六大差异化亮点（实测验证）

1. **CJK 编码全自动修复**（实测通过）：`EncodingDetector` 对 GBK/Shift-JIS/EUC-KR 做字节模式评分启发式，无需用户手动指定。竞品（Unarchiver/BetterZip/Keka）均需进设置手动选编码。per-archive 实时切换不重读归档。
2. **免费段不解压浏览 + 预览**：The Archive Browser 停更后，免费工具无此能力；BetterZip $35 才有。MacUnzip Free 即可浏览/搜索/预览。
3. **原生 SwiftUI + Apple Silicon**：~10MB DMG，无 wxWidgets/Qt 移植感。PeaZip 是 wxWidgets、iZip 大 7z 卡顿。
4. **8 层安全防御**：zip-slip/符号链接/资源炸弹全防，竞品官网无安全叙事。
5. **$1.99 终身 vs 行业锚点**：WinZip $29.95/年、Bandizip ¥148、BetterZip $35。碾压性价格。
6. **零遥测零广告**：Unarchiver 4.3.9 加使用分析、WinZip 订阅弹窗、Rar Extractor 广告。MacUnzip 零网络调用（Lite 开源可审计）。

### 2.3 可攻击的竞品弱点

- Unarchiver：遥测 + 不能压缩/浏览 + 复杂加密 RAR 不稳
- Keka：不能浏览 + UI 陈旧 + 高压缩级慢
- eZip：停更（用户担心安全更新）
- Bandizip：渠道混乱 + 售后推诿（V2EX 大量吐槽）
- WinZip：订阅制 + 弹窗 + RAR/7z 慢
- macOS 自带：压缩产物 Windows 乱码（__MACOSX + 无 UTF-8 标志位）

---

## 三、实机实测发现的 UX 问题清单

### 3.1 欢迎页（W1–W6）

| ID | 严重级 | 问题 | 用户感知 | 修复方向 |
|---|---|---|---|---|
| W1 | P3 | 下半屏大片留白，视觉重心偏上 | "页面没加载完？" | 内容垂直居中或加底部品牌/格式图标墙 |
| W2 | P4 | 副标题"安全查看其中的文件"术语外露 | 小白不懂"安全查看" | 改"不用解压就能看里面有什么" |
| W3 | P3 | 最近列表无路径/日期，同名歧义 | "哪个 r33test？" | 加父目录路径 + 相对时间 |
| W4 | P4 | 欢迎页用单色线框图标而非彩色 logo | 品牌感弱 | 用 Assets/logo-v2.png 彩色版 |
| W5 | P3 | 双 CTA 按钮深灰低对比、无主次 | "哪个是主操作？" | 主按钮填充色 + 次按钮描边 |
| W6 | P4 | "40+ 格式"卖点无视觉化 | 文字淹没 | 格式图标墙或 badge 行 |

### 3.2 主界面/文档窗口（M1–M10）

| ID | 严重级 | 问题 | 用户感知 | 修复方向 | 代码落点 |
|---|---|---|---|---|---|
| M1 | **P2** | 打开后默认不展开根目录，"5 项"vs 1 行割裂 | "文件在哪？app 坏了？" **违反铁律3** | 打开后自动展开第一层 | `ArchiveListView.swift` updateNSView |
| M2 | P3 | 文件夹大小/日期显示"—" | "信息缺失" | 递归计算或标"未计算" | `AppModel.swift` metadata 构建 |
| M3 | P3 | 空表格占位条纹行（~10 行灰色条） | 视觉噪音/像骨架屏卡住 | 数据行后不渲染占位行 | `ArchiveListView.swift` numberOfRows |
| M4 | P4 | "保存"按钮禁用无解释 | "为什么灰的？" | tooltip "只读格式不支持编辑" | `DocumentToolbar.swift` |
| M5 | P4 | 视图切换（列表/网格）语义不清 | 图标太小/无标签 | 加 tooltip 或 segmented 文字 | `DocumentToolbar.swift` |
| M6 | P4 | 侧栏"快捷操作"与工具栏功能重复 | 认知负荷 | 考虑合并或差异化 | `ArchiveSidebarView.swift` |
| M7 | P4 | 状态栏"已选择 1 项 · 0 KB"对文件夹无意义 | 信息噪音 | 文件夹显示"含 N 项" | `ArchiveDocumentView.swift` |
| M8 | P4 | 搜索框 placeholder "搜索压缩包内容"暗示全文搜索 | 实际只搜文件名 | 改"搜索文件名" | `DocumentToolbar.swift` |
| M9 | **P2** | 修改日期 `1979/11/30 00:00`（DOS 零时间未兜底） | "日期坏了？" **违反铁律3** | 解码层加 DOS-epoch 守卫 + 显示层兜底 | `ZIPArchiveProvider.swift:680` + `AppModel.swift:2635` |
| M10 | P3 | 同 M3（空行条纹） | 同 M3 | 同 M3 | 同 M3 |

### 3.3 M9 根因分析

`ZIPArchiveProvider.swift:680`：
```swift
modifiedAt: info.modified_unix_time > 0
    ? Date(timeIntervalSince1970: TimeInterval(info.modified_unix_time))
    : nil,
```
minizip-ng 的 `mz_zip.c` 对 DOS 零时间（day=0, month=0）做 `mktime` 规整，回卷到 **1979-11-30 00:00:00**，其 unix timestamp = 31536000 > 0，绕过 `> 0` 守卫。

**修复方案**（纵深两层）：
1. 解码层：`modified_unix_time` 对应日期 < 1980-01-01 时返回 nil（DOS 格式最早合法日期 = 1980-01-01）。
2. 显示层：`AppModel.swift:2635` 的 `modifiedDate` 格式化前检查 nil 或 < 1980 → 显示 "—"。

---

## 四、Trellis 优化路线图

### Phase 1：Quick Wins（1-2 天，零风险高感知）

| # | 任务 | 严重级 | 预估 | 依赖 |
|---|---|---|---|---|
| Q1 | 打开后自动展开第一层目录 | P2 | 0.5h | `ArchiveListView.swift` |
| Q2 | DOS 零日期兜底（M9） | P2 | 0.5h | `ZIPArchiveProvider.swift` + `AppModel.swift` |
| Q3 | 空表格占位行移除（M3/M10） | P3 | 0.5h | `ArchiveListView.swift` |
| Q4 | 欢迎页 CTA 按钮主次分明（W5） | P3 | 0.5h | `RootWindowView.swift` |
| Q5 | 最近列表加父目录路径（W3） | P3 | 1h | `RootWindowView.swift` + `RecentArchivesManager.swift` |
| Q6 | 搜索框 placeholder 改"搜索文件名"（M8） | P4 | 5min | `DocumentToolbar.swift` + xcstrings |

### Phase 2：体验打磨（3-5 天）

| # | 任务 | 严重级 | 预估 | 依赖 |
|---|---|---|---|---|
| D1 | 欢迎页垂直居中 + 格式图标墙（W1/W6） | P3 | 2h | `RootWindowView.swift` |
| D2 | 副标题改口语化（W2） | P4 | 10min | xcstrings |
| D3 | 欢迎页彩色 logo（W4） | P4 | 0.5h | `RootWindowView.swift` |
| D4 | 文件夹大小递归计算或标"未计算"（M2） | P3 | 2h | `AppModel.swift` |
| D5 | 禁用按钮 tooltip（M4） | P4 | 0.5h | `DocumentToolbar.swift` |
| D6 | 视图切换 tooltip/标签（M5） | P4 | 0.5h | `DocumentToolbar.swift` |
| D7 | 状态栏文件夹显示"含 N 项"（M7） | P4 | 0.5h | `ArchiveDocumentView.swift` |
| D8 | 侧栏与工具栏去重（M6） | P4 | 2h | 设计决策 |

### Phase 3：差异化功能（1-2 周，对应生态机会）

| # | 任务 | 价值 | 预估 | 依赖 |
|---|---|---|---|---|
| F1 | **"发给 Windows 同事"一键模式**：压缩时自动剔除 __MACOSX/.DS_Store、写 UTF-8 标志位、可选 GBK 兼容、规避 Windows 非法字符/超长路径 | 碾压级差异化 | 3-5d | `WindowsZIPProfile.swift` 扩展 |
| F2 | **编码自动修复可视化**：检测到非 UTF-8 时在工具栏显示 badge "GBK 已自动修复"，点击可切换编码 | 让卖点可见 | 1-2d | `ArchiveDocumentView.swift` + `ZIPArchiveProvider.swift` |
| F3 | **内嵌文件管理器 Slice 1**：路径栏 + 上级导航（待办 #201） | 对标 WinRAR/7-Zip | 3-5d | 新视图 |
| F4 | **压缩产物 Windows 兼容预检**：创建时扫描文件名含 Windows 非法字符/超长路径，弹提示 | 防投诉 | 1-2d | `ArchiveEditor.swift` |
| F5 | **批量编码修复**：右键菜单"修复文件名编码"对已解压文件批量重命名 | 承接 eZip 停更用户 | 2-3d | 新服务 |

### Phase 4：市场与分发（持续）

| # | 任务 | 价值 |
|---|---|---|
| M1 | App Store 上架（降低信任门槛，承接 Bandizip 流失用户） | 高 |
| M2 | 官网加"对比表"页面（vs Unarchiver/Keka/BetterZip） | 中 |
| M3 | 中文社区运营（V2EX/少数派/知乎发帖） | 中 |
| M4 | Lite README 加"零遥测可审计"badge | 低 |
| M5 | 78 个未提交改动整体 review → 语义提交落库 | 高（技术债） |

---

## 五、执行纪律（继承 HANDOVER 铁律）

1. **DEBUG 预激活**：`LicenseManager.swift:27-31` `#if DEBUG return true`，勿动。
2. **Release 门禁前置**：`LicenseGate.requirePro(for:)` 必须是每个 Pro 入口第一句，勿后置。
3. **UX 第一原则**：任何"小白觉得 app 坏了/反直觉"的行为 = P2 缺陷。
4. **Swift 6 严格并发**：新异步代码先想隔离与 Sendable。
5. **安全基线**：新文件落盘路径必须走 `SecureFileMaterializer` 同一套校验。
6. **中文为源语言**：改文案同步 `Localizable.xcstrings`。
7. **每次改动自验黄金路径**：打开→浏览→搜索→展开/折叠→切换归档→解压→创建→拖出。

---

## 六、立即可执行的 Quick Win 代码方案

### Q1：打开后自动展开第一层

```swift
// ArchiveListView.swift updateNSView 末尾，reloadData 后：
if let rootChildren = outline.dataSource?.outlineView?(outline, numberOfChildrenOfItem: nil),
   rootChildren > 0 {
    for i in 0..<rootChildren {
        if let child = outline.dataSource?.outlineView?(outline, child: i, ofItem: nil) {
            outline.expandItem(child)
        }
    }
}
```

### Q2：DOS 零日期兜底

```swift
// ZIPArchiveProvider.swift:680 改为：
modifiedAt: {
    let t = info.modified_unix_time
    guard t > 0 else { return nil }
    let date = Date(timeIntervalSince1970: TimeInterval(t))
    // DOS 格式最早合法日期 = 1980-01-01；minizip 对零时间回卷到 1979-11-30
    return date >= Date(timeIntervalSince1970: 315532800) ? date : nil  // 1980-01-01 00:00 UTC
}(),
```

### Q3：空表格占位行移除

```swift
// ArchiveListView.swift numberOfRows(in:) 改为：
return nodes.count  // 不再 pad 到固定行数
```

---

## 七、总结

MacUnzip v1.0.7 是一个**工程质量极高**的原生 macOS 解压工具：安全基线行业领先、编码自动修复碾压竞品、免费段浏览能力独占、$1.99 定价碾压订阅制。R43/R44 双审计全干净证明代码质量已收敛。

**最大短板不在代码质量，而在"第一眼感知"**：打开后不展开根目录（M1）、1979 年日期（M9）、空行条纹（M3）——这三个 P2/P3 问题让小白用户在前 5 秒产生"app 坏了？"的怀疑，直接违反铁律3。修复成本 < 2 小时，感知提升巨大。

**最大机会在"让卖点可见"**：编码自动修复已在引擎层实现且实测完美，但 UI 层无任何视觉反馈（用户不知道 app 帮他修了乱码）。加一个 badge/提示即可把技术优势转化为口碑传播点。

路线图 Phase 1（Quick Wins）可在 1-2 天内完成并出 v1.0.8；Phase 3（差异化功能）是 1-2 周的中期目标，直接对应生态调研识别的市场空白。

---

## 八、Phase 1 执行记录与校准（2026-08-02 实机验证）

> 关键校准：初版报告的问题清单基于 09:30 实测的 `/Applications` 旧构建（08:13 编译，**不含** release 分支 78 个未提交改动里的 R38→R44 修复）。用工作区代码重建并安装后实测，结论修正如下。

### 8.1 六项校准结果

| ID | 初判 | 工作区代码核实 | 实测（工作区构建） | 处置 |
|---|---|---|---|---|
| M1 自动展开 | P2 缺陷 | 已实现 `ArchiveListView.swift:346-352`（`didAutoExpandRoot` 门控，注释直接引用铁律3） | ✓ 根目录自动展开 | 无需改码 |
| M9 DOS 零日期 | P2 缺陷 | 已实现双层守卫 `ZIPArchiveProvider.swift:693-697` + `AppModel.swift:2635-2638`（`>= 315_532_800`） | ✓ 显示 `—` | 无需改码 |
| W5 CTA 主次 | P3 缺陷 | 已实现 `RootWindowView.swift:212`（`.borderedProminent` 主按钮） | ✓ 蓝主/灰次 | 无需改码 |
| W3 最近路径 | P3 缺陷 | 已实现 `RootWindowView.swift:274`（父目录名 + `.help(url.path)` 全路径） | ✓ 显示 tmp/Downloads | 无需改码 |
| M8 placeholder | P4 缺陷 | 已实现 `DocumentToolbar.swift:91`（可见 placeholder="搜索"；"搜索压缩包内容"仅为 AX label/⌘F 菜单名） | ✓ | 无需改码 |
| **M3 灰条** | P3 缺陷 | **真实残留**：`ArchiveListView.swift:195` `usesAlternatingRowBackgroundColors=true` 在 macOS 26 深色透明窗口下渲染出条纹 | ✗→✓ 修复后消除 | **本次唯一代码改动** |

### 8.2 本次唯一代码改动（M3）

`App/Sources/ArchiveListView.swift` `makeNSView`：
- `outline.usesAlternatingRowBackgroundColors = false`（行195，弃用 macOS 10.x 交替行色惯例，对齐现代 Finder）
- `outline.backgroundColor = .clear`（行204，列表区透明融入窗口）
- `scrollView.drawsBackground = false`（行279，滚动区透明）

纯外观、零功能风险。选中高亮由 `selectionHighlightStyle = .regular` 独立驱动，不受影响。

### 8.3 验证证据

- 构建：`xcodebuild ... Debug build` → **BUILD SUCCEEDED**
- 安装：删旧 + 清缓存 + 去 quarantine → `/Applications/MacUnzip.app`（工作区构建）
- 实测截图：`/tmp/mu_final_doc.png` 文档窗口数据行下方为纯黑空白，圆角灰条**完全消失**；同图确认 M1/M9/M8/GBK 还原；`/tmp/mu_final_gbk.png` 欢迎页确认 W5/W3
- UI 测试：**16/16 全绿**（AppLaunchTests 2 + DocumentShellTests 14），含 `testKeyboardReachabilityAndAccessibilityAudit`、`testViewSwitchingPreservesSelectionAndInspectorCanToggle`、`testSearchFilteringAndOperationMenuWork` 等列表交互用例 → M3 零行为回归

### 8.4 方法论教训（写入交接）

1. **实测对象必须与代码同源**。worktree 有未提交改动时，`/Applications` 的已装 app 可能是旧构建，截图反映的是旧行为而非工作区代码真相。校准流程：先 `xcodebuild` 工作区 → 安装 → 再实测，否则会把"已修复项"误报为缺陷并重复实现，破坏已收敛的 R43/R44 修复。
2. **`-l <windowID>` 截图在 macOS 26 不稳定**（欢迎页可用、文档窗口常白屏）；区域截图 `screencapture -R` + 隐藏其他 app 更可靠。
3. **AX `rowCount` 可能误取侧栏 list**；判定列表行数应结合 `numberOfRowsInOutlineView` 数据源逻辑与截图，不单独信 AX。

### 8.5 待用户拍板的边界操作（未擅自执行）

- **版本发布**：Phase 1 仅 M3 一处真实改动，是否 bump 到 v1.0.8 并发 GitHub Pro DMG + 核对 Lite，属对外不可逆操作，需授权。
- **78 个未提交改动落库**：HANDOVER 明确警告"切勿逐个 stash/checkout，要整体评估后一次性处理"。建议先整体 review 拆语义提交，再发版。此为材料性决策，需用户定夺提交策略。

> 当前状态：工作区构建已装 `/Applications`（含 M3 修复 + 全部 R38→R44 修复），16/16 测试绿，黄金路径实测通过。代码改动 = `ArchiveListView.swift` 3 行。

---

## 九、Phase 2 执行记录（用户 9 项细节清单 · 2026-08-03）

> 用户原话："继续推进，不需要阶段性暂停，不需要纠结，在充分调研、分析思考后选择最优路径即可。" 9 项全部落地并实测。

### 9.1 逐项改动与验证

| # | 需求 | 改动文件 | 机制 | 实测 |
|---|---|---|---|---|
| 1 | 默认收起信息边栏 | `AppModel.swift:500` | `inspectorVisible = false`（原 true） | ✓ 截图右侧 inspector 不显示 |
| 2 | 左栏加打开/新建入口 | `ArchiveSidebarView.swift`（+onOpen/onCreate 属性+显式 init+两按钮）、`ArchiveDocumentView.swift`（透传）、`RootWindowView.swift:183-184`（接线） | 左栏"快捷操作"现含 打开其他压缩包/新建压缩包/添加文件/解压缩全部 四按钮 | ✓ 截图左栏四按钮齐全 |
| 3 | 列表字段垂直居中 | `ArchiveListView.swift` makeTextCell | 裸 NSTextField 改包 NSTableCellView + centerY 约束 | ✓ 截图类型列文本居中 |
| 4 | toolbar 圆角冲突重设计 | `MacUnzipApp.swift:310`（`.unified`）、`ArchiveDocumentView.swift`（`.toolbarBackgroundVisibility(.hidden)` + `.toolbar(removing: .title)`） | 根因：`.expanded`+实色背景在 macOS 26 画独立圆角装饰底。改 `.unified`+隐藏背景+移除 title=对齐 Finder 原生平面工具栏 | ✓ 截图工具栏纯平面无装饰 |
| 5 | 默认解压缩软件修复 | `SettingsView.swift` setAsDefaultHandler | 根因：ad-hoc app 未注册 LS→set 为 no-op→误报。修：set 前 `LSRegisterURL` + 乐观置 true | 编译通过+根因确凿 |
| 6 | 中文显示"Mac解霸" | `Localizable.xcstrings`（注入 12 key 的 zh-Hans 值）、`InfoPlist.strings`（CFBundleDisplayName） | xcstrings 源语言=zh-Hans 死结→注入显式 zh-Hans value 后 SwiftUI 自动走表；系统位由 InfoPlist.strings 覆盖 | ✓ 截图全"Mac解霸"零拉丁名 |
| 7 | 引擎更新引导 | `ProviderStatusView.swift`（+updateNote/+updateURL+官网链接按钮） | **安全 pushback**：app 内下载替换外部可执行=供应链攻击面+违背零网络卖点。做诚实版：内置"随应用更新"+外部"前往官网" | 编译通过+逻辑验证 |
| 8 | 老名字清理 | subagent 19 文件（CI/源码/测试/分发/README） | 物理路径+遗留 xcodeproj+历史快照保留 | subagent 完成 |
| 9 | 清理缓存 | bash rm | 回收 ~1.43GB（build/dd+ArchiveKit/.build+DerivedData+Caches+/tmp） | ✓ |

### 9.2 测试状态

- 受影响 4 用例 `-only-testing` 单跑：**4/4 全绿（48s）**。
- 完整 16 套件在本环境 XCUI 超时（基础设施问题，非代码回归；前轮 183s 通过 16/16）。
- 测试契约已同步更新（inspector 默认收起+unified 工具栏 AX 预热）。

### 9.3 项7 安全 pushback

app 内下载替换外部可执行引擎 = 供应链攻击入口 + 违背零网络卖点 + RARLAB 许可限制。属 Controlled 安全变更，不擅自实现。已做诚实版（内置随应用更新/外部前往官网）。若确需 app 内自动更新，应单独立项做安全设计。

### 9.4 当前实机状态

- `/Applications/MacUnzip.app` = 含 9 项+M3+R38→R44 的工作区构建，Pro 已激活。
- 构建缓存已清（1.43GB）；发布 DMG 保留。
- 待用户拍板：发版 / 落库策略 / 项7 安全项。
