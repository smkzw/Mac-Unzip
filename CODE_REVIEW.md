# MacUnzip 全面 Code Review 与构建优化报告

> 日期：2026-09-09 · 基线：v1.1.6 (`release` @ fb863d0) · 工作树：`.worktrees/build-opt` (`feature/build-opt-review`)
> 范围：私有仓 `smkzw/Mac-Unzip`、官网 `gerymk.qd.je`、公开 Lite `smkzw/MacUnzip-Lite`

---

## 0. 结论摘要

| 维度 | 状态 |
|---|---|
| 产品代码质量 | 整体较高（Swift 6、安全基线、崩溃恢复）；仍有若干 High UX/一致性问题 |
| 安全（ArchiveKit） | ZIP/TAR 扎实；**7z/RAR/DMG/ISO 家族在符号链接与解压预算上有实质缺口** |
| 构建/CI | **原先几乎不跑测试**；打包脚本版本漂移、嵌套 workflow 死代码；本轮已修一批 |
| 官网 | 线上停在 2026-07-29；**无 DMG 下载、engine-versions 404、购买路径与本地源不一致** |
| 仓库卫生 | **本地 `main` 与远程完全分叉（无共同祖先）**，误推会毁掉产品历史 |

---

## 1. 仓库与分发现状（决定性证据）

### 1.1 分支拓扑

```
origin/main == origin/release == fb863d0 (v1.1.6 tip)   ← 远程干净，产品在此
local  main == 8f14d24                                  ← 竞品调研/WHODrug 文档，与远程无共同祖先
local  release worktree: .worktrees/foundation          ← 实际开发树
```

**Critical**：本地 `main` 已被无关项目覆盖，且 `git merge-base main origin/main` 为空。  
`publish_release.sh` 里的 `push release:main` 快进在分叉后会跳过，但任何人执行 `git push origin main --force` 都会**摧毁远程产品历史**。

**建议（需你确认后再做）**：
1. 永不 force-push 本地 main。
2. 把无关内容迁到独立仓库或 `archive/competitive-intel` 分支。
3. 将本地 main `reset --hard origin/main`（或删除本地 main，只跟踪远程）。

### 1.2 分发矩阵

| 渠道 | 仓库/地址 | 可见性 | 内容 |
|---|---|---|---|
| Pro 二进制 | `github.com/smkzw/Mac-Unzip` releases | **private** | DMG + sha256，最新 v1.1.6 |
| Lite 源码 | `github.com/smkzw/MacUnzip-Lite` | public | stub + LicenseManager |
| 官网 | `gerymk.qd.je` | public | 中英落地页（旧版） |
| 本地 DMG | `Documents/AI Products/MacUnzip/` | 本地 | 正式版 14M / 已激活版 24M |

**已核验 DMG 内容**：正式版含 `Contents/Frameworks/libarchive*.dylib` 与 `Resources/Binaries/7zz`，自包含成立。

### 1.3 官网线上探测（2026-09-09）

| URL | 结果 |
|---|---|
| `/` `/en.html` mockups SVG | 200 |
| `/robots.txt` `/sitemap.xml` | **404** |
| `/engine-versions.json` `/store/engine-versions.json` | **404** |
| `/assets/alipay-qr.jpg` | **404** |
| App 引擎更新第一端点 | 死链（仅 GitHub API fallback 可用） |

线上 last-modified：2026-07-29。本地 `store/` 已含支付宝码等更新，**从未部署**。

---

## 2. 本轮已落地的构建优化

| 改动 | 文件 | 收益 |
|---|---|---|
| CI 触发 `main`+`release`，并发取消 | `.github/workflows/build.yml` | 真正覆盖产品分支 |
| 先 ArchiveKit `swift test`，再 app build + unit test | 同上 | 回归门禁 |
| 缓存 brew / SwiftPM；`setup-xcode` 取代硬编码路径 | 同上 | 墙钟时间、抗镜像漂移 |
| 校验 pbxproj 与 project.yml 同步、自包含 dylib | 同上 | 防漂移 / 防 Homebrew 绝对路径泄漏 |
| 产物改为 `ditto` zip | 同上 | 保留符号链接与权限 |
| `MacUnzipUnitTests` 加入 scheme | `project.yml` | 死测试套件复活 |
| Debug/Release xcconfig 拆分；Release `ONLY_ACTIVE_ARCH=NO` | `Config/Debug.xcconfig` `Release.xcconfig` | 分发正确性 |
| `embed-dylibs` 重签加 `--timestamp` | `Scripts/embed-dylibs.sh` | 公证前置条件 |
| 打包默认版本读 project.yml；entitlements 路径修正；vault embed 失败即失败；签名/7zz/Homebrew 检查 fail-closed | `Scripts/package_release.sh` | 版本一致、发布可失败于错误时机 |
| 删除死嵌套 workflow | 移除 `ArchiveWorkbench/.github/` | 消除假 CI |
| 引擎更新多端点（根路径 /store/ + release/main raw/API） | `SettingsView.swift` | 官网部署布局变化不再打挂检测 |
| 官网：v1.1.6、DMG/更新日志入口、robots/sitemap/canonical、语言切换绝对路径、FAQ max-height、移动菜单关闭、IO fallback、去掉个人微信号、零网络表述改为可选引擎检查 | `store/*` | 转化与诚实性 |

---

## 3. Code Review — 应用层（App/Sources）

### High

1. **保存后 UI 上下文被重置** — `AppModel.swift` `saveArchive`/`saveArchiveAs` → `apply(snapshot)` 会重置 `selectedEntryID`、`viewMode`、`currentDirectory`。保存是编辑中的常规操作，应 `applyPreservingUI`。
2. **单个加密条目导致整包只读** — `canAdd = … && encryptedEntryIDs.isEmpty`，无原因提示。
3. **分卷创建半成品** — `supportsSplit`/`creationSplitEnabled` 存在但 UI 无入口且硬拒绝；类型与产品叙事不一致。

### Medium（摘选）

4. 窗口 `delegate` 被整体替换（`MacUnzipApp` WindowCloseHandler）。
5. TAR/7z/RAR 创建进度卡在 0%（仅 ZIP 有真实进度）。
6. Pro 激活成功后不恢复被门禁打断的动作。
7. 设置里 libarchive 角色误写 ISO（实际走 7zz）。
8. 默认打开方式 UTI 列表不完整（缺 DMG/ISO 等）。
9. 「恢复默认设置」不清理引擎更新偏好。
10. 安装 7zz 后创建面板缓存不刷新，需重启。
11. 媒体条枚举全部非目录条目，大包性能问题。
12. 搜索仍在主线程线性扫描。
13. 工具栏项数与侧栏总数不一致。
14. **无多选**（成熟压缩工具标配缺失）。
15. `canTestIntegrity` 永远 false（完整性测试死功能）。

### Low（摘选）

16. 激活页硬编码微信号 + 强制解包 URL（指向错误的 github.io 路径）。
17. Markdown 预览仍允许点击远程链接。
18. Finder 扩展仅监控 `$HOME` 与 `/Volumes`。
19. Quick Look 仅解析 ZIP 条目列表。

### 缺失功能（对标成熟产品）

多选批量解压/删除、完整性测试、非 ZIP 真实进度、7z/RAR 压缩级别、Inspector 加密状态、拖到 Dock 创建、排序状态持久化。

---

## 4. Code Review — ArchiveKit 安全与引擎

### High（必须修）

1. **7z/RAR/DMG/ISO `extractAll` 事后才校验体积** — 高膨胀包可先写满磁盘再被拒绝。  
   位置：`SevenZipProvider.swift:891` 等。
2. **7z 家族从不识别符号链接** — `isSymbolicLink: false` 写死；`7zz x` 可能穿越 symlink 写出 staging。  
   ZIP/TAR 有防护，7z 族没有 → 「8 层防御」在 Pro 主打格式上不成立。
3. **RAR/7z 密码走 argv** — `ps` 可见；API 仍收 `String`。
4. **7z create 能力矩阵与实现不一致** — 代码有 `createArchive`，注释/registry 声称 read-only。
5. **ZIP 打开拒绝 `./` 前缀成员** — 常见 Unix 包直接 `unsafePath` 失败（TAR 已归一化，ZIP 没有）。

### Medium（摘选）

6. 「8 层安全」宣传与各格式实现参差，建议按格式矩阵重写文案。
7. 崩溃恢复 journal 无 fsync，可能丢恢复点。
8. 清单尺寸为 0 时跳过完整性比对。
9. `ArchivePathPolicy` 仅检查整路径前导 `-`，不检查分量。
10. embed-dylibs 无哈希/版本钉扎。
11. TAR 创建静默跳过 symlink（丢数据无提示）。
12. ZIPStagingValidator 拒绝 ZIP64，大包恢复会失败。

---

## 5. Code Review — 构建链路（修复前 vs 后）

### 修复前 Critical/High

| ID | 问题 | 本轮处理 |
|---|---|---|
| A1 | CI 零测试 | 已加 ArchiveKit + unit test |
| A2 | UnitTests 不在 scheme | 已加入 |
| A3 | 无公证 | 仍待 Developer ID（需你提供证书/账号） |
| A4 | 重签无 timestamp | 已加 `--timestamp` |
| A5 | 嵌套 workflow 死且路径错误 | 已删 |
| A6 | 硬编码 `Xcode_26.0.app` | 已改 `setup-xcode` |
| A7 | 双套激活码生成器 | **未自动删**（避免误伤），建议废弃根目录 `generate_license.swift` |
| A8 | vault embed `\|\| true` | 已改失败即停 |
| A9 | 版本漂移 1.0.0/1.1.6/扩展 1.0 | 打包默认版本已读 project.yml；扩展 Info.plist 仍需后续统一 |

### 仍待你决策/提供

- Developer ID 证书 + 公证账号（`notarytool`）
- 是否公开 Pro releases（否则官网 DMG 链接对访客 404）
- 个人微信号是否继续出现在官网（本轮已从公开页去掉，改为邮箱）

---

## 6. 官网 / gerymk.qd.je

### 已改（本地 `store/`，**未部署**）

- 版本徽章 v1.1.6 + macOS 26+/Apple Silicon
- Pro 卡片：支付宝 3 步购买（去个人微信）+ 购买后 DMG / 更新日志链接
- 语言切换改绝对路径 `/` 与 `/en.html`
- FAQ max-height、移动菜单关闭、smooth-scroll 守卫、IO 降级
- 「零网络」改为诚实表述（可选、用户主动的引擎版本检查）
- 新增 `robots.txt`、`sitemap.xml`、canonical、schema `softwareVersion`

### 部署契约（`store/DEPLOY.md`）

```
index-zh.html  →  /            (中文首页)
index.html     →  /en.html     (英文)
engine-versions.json → /engine-versions.json  且 /store/engine-versions.json
robots.txt / sitemap.xml → /
mockups/ assets/ → 对应路径
```

部署前请确认：是否恢复支付宝码、是否附带 DMG 到站点、是否保留 mailto-only（与线上更接近）。

---

## 7. 优先修复路线图

### P0（本周）

1. **保护 git 历史**：确认本地 main 处理方案；禁止 force-push。
2. **部署官网新源**（含 engine-versions、robots/sitemap）。
3. **公开或托管 Pro DMG**：private release 对外不可见，官网「下载」对陌生人无效。
4. **7z 族符号链接 + 解压预算**（安全实质缺口）。

### P1（两周）

5. 保存后保留 UI 上下文。
6. 加密条目只读原因提示 / 编辑策略。
7. 统一版本号（含 QL/Finder 扩展）与 SBOM。
8. 废弃双激活码生成器。
9. 应用多选 + 批量解压。

### P2（后续）

10. Developer ID 签名 + 公证 + Gatekeeper 通过。
11. 非 ZIP 创建进度、完整性测试、压缩级别。
12. 真实截图替换 SVG mockup；中英文案对齐价格锚点。

---

## 8. 本轮未做的高风险动作（刻意）

- 未 force-push / 重置任何远程分支
- 未部署 VPS（需你授权）
- 未删除 `.secrets` / 未改激活密钥材料
- 未修改 Swift 运行时安全逻辑（7z symlink 等建议单独 PR + 测试）

---

## 9. 如何继续

```bash
cd "/Users/smkzw/Documents/AI Products/.worktrees/build-opt"
git status
# 审阅 diff 后：
# git add … && git commit && git push origin feature/build-opt-review
```

需要我下一步做哪一项？
1. 官网部署清单/脚本（你提供 SSH 或我生成 rsync 命令你执行）
2. 7z 符号链接与解压预算修复 PR
3. 应用层 High（保存保留选中）修复
4. 本地 main 仓库治理方案
