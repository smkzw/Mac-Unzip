# MacUnzip LOOP 无损恢复记录（R31 周期结束 · 2026-07-31）

> 本文件用于无损恢复。读完即可完整接续工作。

---

## 一、用户的长期要求（始终有效，勿违反）

1. **总要求（原话）**："继续debug继续LOOP不要停。你在本地生成的app为什么还要我激活？？？我自己的app你不会直接默认激活好给你吗？另外，对于对外分发的版本，创建压缩包点击后就应该出现提示激活，而不是点了创建压缩包没反应让用户觉得app有问题点了取消后才显示要激活！！这些操作逻辑和人机交互不合理的地方是LOOP的重中之重！"
   - DEBUG 构建：Pro 预先激活（`LicenseManager.swift` 里 `#if DEBUG return true`，已实现）。
   - Release/对外分发：点击 Pro 功能时**立即**弹激活提示（`LicenseGate.requirePro` 作为每个 Pro 点击的第一句，已实现）。
   - 交互逻辑/UX 是 LOOP 的重中之重。

2. **每轮 LOOP 结束后的构建/分发流程（原话）**："继续未完成的任务，务必注意每轮LOOP结束修复好后要更新我本地安装的MacUnzip（已激活Pro版）并删除旧版，同步更新github的Pro及Lite版，必要时更新Lite版的README，更加市场化、国际化、丰富化、设计化"
   - 更新本地安装的 MacUnzip（激活 Pro 的 Debug 版）并删除旧版。
   - 同步 GitHub：Pro（smkzw/Mac-Unzip，发二进制 DMG）+ Lite（smkzw/MacUnzip-Lite，源码 fork，**绝不能覆盖**）。
   - 必要时更新 Lite README（市场化/国际化/丰富化/设计化）。

3. **分发规则（已批准）**："Pro发二进制+Lite同步源码"；"Stop shipping rar"。

4. **LOOP 退出标准**：每个 tester 在两种审计（工程师 + 首次用户）上、所有严重级（P0–P4）都连续 2 轮干净。R25–R30 均不干净 → R30 修复后，**R31 和 R32 必须都干净**。实际 R31 仍不干净 → 现在需要 **R32 和 R33 都干净**才能退出。

---

## 二、本轮（R31 周期）用户报告的问题 + 我的实现

用户本轮消息（原话）："继续按你的思路进行LOOP。只是一个提醒：目前app打开的默认页下方的最近项目直接漂移到窗口边缘而没有在中间；打开后主界面上方的各个按钮、文件名还是与背后的圆角矩形离得特别近或者重叠，完全没有美感，干脆把圆角矩形去掉吧；目前完成解压缩操作后不会默认把Finder对应路径打开；目前创建压缩包的时候没有默认选到待压缩文件的所在路径，还得用户手动选"

### 4 个 UX 修复（任务 #193，已完成）
1. **欢迎页"最近打开"居中**：`RootWindowView.swift` 最近项目块末尾加 `.frame(maxWidth: 320)`（原 `Spacer()` 把 leading 对齐块撑满全宽导致漂到边缘）。
2. **去掉工具栏圆角矩形玻璃底**：`ArchiveDocumentView.swift` 在 `.toolbar {…}` 后加 `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`（macOS 26 Liquid Glass，原生工具栏，代码里本无自定义圆角矩形）。
3. **解压后自动在 Finder 定位**：`ArchiveDocumentView.swift` 的 `.onChange(of: model.lastExtractionURL)` 里，非 `-ui-testing` 时调 `NSWorkspace.shared.activateFileViewerSelecting([outputURL])`。
4. **新建压缩包保存面板默认定位到源文件目录**：`RootWindowView.swift` `presentCreationSavePanel` 加 `panel.directoryURL = creationDraft?.inputs.first?.deletingLastPathComponent()`。

### R30 审计修复（任务 #194，已完成）
- **E1(P2)** 冷启动多压缩包打开：`RootWindowView.swift` `handleLaunchArguments` 的 `open` 分支改为打开 `urls.first` 并提示跳过数；`MacUnzipApp.swift` `handleLaunchArguments` 同样去掉 `urls.count == 1` 门槛。
- **E2(P3)** 预检竞态：`AppModel.swift` `runPreflight` 改 `defer { if generation == preflightGeneration { isRunningPreflight = false } }`。
- **E3/U2(P4/P3)** Finder IPC 多开报跳过数：并入 E1 的 `open` 分支（"已打开第一个压缩包，其余 %ld 个文件未处理。"）。
- **U1(P2)** 文件夹不可预览：`AppModel.swift` `selectFirstPreviewableEntry` 排除尾部 "/" 的文件夹，且仅当当前选中是可预览文件时才保留。
- **U3(P3)** 冷启动 extract-here：改为先 `LicenseGate.requirePro(for: .extract)` 再设 `pendingExtractHereURLs`（走与运行中相同的确认弹窗），不再直接解压。

---

## 三、当前状态（本轮已完成并验证）

- ✅ 全部修改已编译通过（含新 API `.toolbarBackgroundVisibility`）。
- ✅ UI 测试 16/16 全绿（AppLaunchTests 2 + DocumentShellTests 14）。
- ✅ 本地已安装激活 Pro 的 Debug 版到 `/Applications/MacUnzip.app`（旧版已删，已清 quarantine）。
- ✅ Release DMG **v1.0.6** 已构建并发布到 `smkzw/Mac-Unzip`（ad-hoc 签名，未公证；发布说明含 Gatekeeper 提示）。
  - DMG: `build/MacUnzip-1.0.6.dmg`（9.5M，arm64）
  - SHA-256: `5eee86cd35f708e0b623876bc5dcc1c31e5bd8e3289b94176341b4d03407554a`
  - Release URL: https://github.com/smkzw/Mac-Unzip/releases/tag/v1.0.6
- ✅ Lite 仓库（`/Users/smkzw/repos/MacUnzip-Lite`）已核对：干净、与 origin/main 一致、无需改 README（已是 4 语言/SVG mockup/市场定位；Lite 只是含 LicenseManager.swift 的开源 stub，不是完整源码镜像，**勿往里面拷 Pro 源码**）。
- ✅ 临时调试文件 `AppTests/DebugTreeDumpTests.swift` 已删除，`xcodegen generate` 已重新生成项目。

---

## 四、下一阶段（R32 周期）待办

### R31 双审计结果：均 NOT CLEAN
- 工程师：P0:0 · P1:0 · **P2:1** · **P3:1** · P4:9
- 首次用户：P0:0 · P1:0 · **P2:1** · **P3:1** · P4:2
- 本轮 7 处修改全部被审计确认正确；P2/P3 均为审计中暴露的**既有问题**，非本轮回归。

### 必修（任务 #196 P2 / #197 P3）
1. **P2（工程师）** `AppModel.swift:2168-2257` `openNestedArchive`：嵌套打开失败后共享 loader 的 `currentArchiveURL/currentFormat` 被置 nil，父会话被破坏（Extract/Save-As/stage 全失败，需手动重开）。修复：嵌套打开前快照父 URL/format/password，失败时恢复/重开父归档。
2. **P2（用户）** `MacUnzipApp.swift:206-226`（`application(_:open urls:)`+`deliverOpenURL`）+ `ServiceProvider.swift:20-29`：双击/Services 多开只打开第一个且**不提示跳过数**。把"开第一个+报跳过数"扩展到这些路径。
3. **P3（工程师）** `AppModel.swift:2510-2588` `apply()`：切换归档不重置搜索状态，旧过滤带到新归档。在 `apply()`/`performOpen` 调 `clearSearch()`，并同时重置 `searchText` 与 `activeSearchText`。
4. **P3（用户）** `ArchiveDocumentView.swift:209-216`：每次解压都 `activateFileViewerSelecting` 会抢焦点，破坏"固定解压目录"的安静工作流。改为有条件自动定位（如仅交互式选择目录时，或加设置项）。

### 可选（P4 批量，任务 #198 内列出）
extract-here 逐项跳过反馈、performOpen 被挂起覆盖弹窗阻塞、extractFolder 空文件夹误报、fixPreflightIssues 重命名冲突静默、NSAccessibility.post nil-as-Any、ProviderStatusDetector 主线程同步探测、RecentArchivesManager 同步 IO、最近列表同名歧义、列表视图搜索空态。

### 修复后流程（任务 #198）
重建 Debug → 跑 UI 测试（须 16/16）→ 重装本地激活 Pro 版（删旧）→ 构建 Release DMG（下一版如 1.0.7）发 smkzw/Mac-Unzip → 核对 Lite → **跑 R32 双审计；R32 与 R33 必须都全干净（P0–P4 零发现）才能退出 LOOP**。

---

## 五、延期/勿重复标记清单（审计时跳过）
- P4-2 分卷创建流水线（已禁用的 WIP）
- P3-5 欢迎页 7zz 措辞
- P4-9 SplitVolume 显示"无"
- P4-11 per-instance engineAvailabilityCache
- MacUnzipUnitTests 过期测试（已从 scheme 排除）
- undo/redo 菜单项常亮（有意为之，保留 ⌘Z 文本框路由）

---

## 六、环境要点（省得重摸）
- 项目：`/Users/smkzw/Documents/AI Products/.worktrees/foundation/ArchiveWorkbench`（XcodeGen，`project.yml`；改文件后须 `xcodegen generate`；`.xcodeproj` 不入库；`MacUnzip.xcodeproj` 为当前用，`ArchiveWorkbench.xcodeproj` 是遗留）。
- 跑 app/测试前必须 `pkill -9 -f "MacUnzip.app/Contents/MacOS"`。
- 本地安装：`rm -rf /Applications/MacUnzip.app && cp -R <Debug构建> /Applications/MacUnzip.app && xattr -dr com.apple.quarantine /Applications/MacUnzip.app`。
- Release 打包：`./Scripts/package_release.sh --skip-sign --version X.Y.Z`（无 Developer ID 证书，ad-hoc；发布说明须带 Gatekeeper 提示）。
- 助手工具：`/tmp/wincheck <整数PID>`、`/tmp/capwin <owner子串>`（列窗口 id x y w h）、`/tmp/axdump`（AX 树，可用）。`screencapture -l <窗口id>` 可能空白（录屏权限）；`screencapture -R<x,y,w,h>` 区域截取可用；读图工具对截图的描述偏抽象，别全信。
- UI 测试沙盒不能写 /tmp；`print()` 不到 xcodebuild stdout；启动参数：`-open-archive <path>`、`-finder-files <tempPath>`+`-finder-action <action>`、`-fixture media`、`-ui-testing`。
- gh 已登录 smkzw。Pro 仓库发 DMG 二进制；Lite 仓库只核对、勿覆盖。
- 用户语言：中文回复。AGENTS.md 要求省 token（可用 `skim`，`/Users/smkzw/.local/bin/skim`）。
