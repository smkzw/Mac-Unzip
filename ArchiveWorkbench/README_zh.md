<p align="center">
  <img src="Assets/logo-v2.png" alt="Mac Unzip" width="256" height="256">
</p>

<h1 align="center">🗜️ Mac 解霸 <sub>Mac Unzip</sub></h1>

<p align="center">
  <strong>⚡ 极速解压 · 🔒 金库级安全 · 🍎 100% 原生</strong><br>
  <em>你的 Mac，值得一个真正的原生压缩工具。</em>
</p>

<p align="center">
  <a href="README.md">English</a> | <strong>中文</strong> | <a href="README_fr.md">Français</a> | <a href="README_es.md">Español</a> | <a href="README_it.md">Italiano</a> | <a href="README_ja.md">日本語</a> | <a href="README_ko.md">한국어</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026-blue" alt="Platform">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon-orange" alt="Architecture">
  <img src="https://img.shields.io/badge/Swift-6.2-red" alt="Swift">
  <img src="https://img.shields.io/badge/license-个人免费%2F商用付费-green" alt="License">
</p>

<p align="center">
  <a href="#-界面预览">📸 界面预览</a> &nbsp;•&nbsp;
  <a href="#-核心能力">🚀 核心能力</a> &nbsp;•&nbsp;
  <a href="#-安全架构">🛡️ 安全架构</a> &nbsp;•&nbsp;
  <a href="#-安装与构建">⬇️ 安装</a>
</p>

---

## ✨ 为什么是 Mac 解霸

**你的文件，不该被"套壳"对待。**

市面上的 Mac 压缩工具，打开活动监视器看看：一个"解压软件"占 400 MB 内存，比 Final Cut Pro 还吃资源。为什么？因为它里面跑着一整个 Chromium。还有的工具，把 7zip 二进制往 .app 里一塞就算完事，路径校验？符号链接检查？"用户自己注意"。

一个精心构造的恶意压缩包，一个 `../`，一个 symlink，你的整个 Home 目录就是别人的游乐场。

🍎 **Mac 解霸，从零开始，只写原生。**

Swift 6.2 + SwiftUI。没有 Electron。没有 Node.js。没有 Python 运行时。没有遥测。没有网络请求。没有广告。它只做一件事，把它做到极致：**以思想的速度，安全地处理你的压缩文件。**

> 💡 *"我们不是优化了一个 Electron 应用。我们写了一个 Mac 应用。"*

---

## 🚀 核心能力

### 📂 解压 — 拖入即开，秒级响应

- ⚡ **即拖即开** — 压缩包拖入窗口，内容立刻呈现。没有"正在解压…"进度条。没有等待。
- 🔐 **加密压缩包** — AES-256 / ZipCrypto 密码保护，原生支持
- 🪆 **嵌套浏览** — 压缩包里套压缩包？双击进入，返回键退出，层层穿透
- 🎯 **精准提取** — 10 GB 的压缩包里只取一个文件？不用全部解压。
- ⏱️ **实时进度** — 大文件解压随时可取消，进度一目了然

### 📦 压缩 — 六种格式，一步到位

- 🗜️ **ZIP / 7z / RAR / TAR.GZ / TAR.XZ / TAR.ZST** — 全格式创建
- 🔒 **AES-256 加密** — 军事级加密保护敏感文件（ZIP / 7z）
- 🖱️ **拖拽添加** — 文件、文件夹直接拖入，目录结构递归保留
- 📊 **压缩级别** — 从「极速存储」到「极限压缩」，你说了算
- ✅ **智能预检** — 路径冲突、非法字符、Windows 保留名……创建前全部拦截
- 🪟 **跨平台就绪** — UTF-8 文件名，自动剔除 macOS 元数据，Windows 11 直接打开

### 👁️ 预览 — 不解压，先看内容

- 🖼️ **图片**（PNG / JPEG / HEIC / SVG / WebP）— 缩略图网格 + 全尺寸渲染
- 📄 **PDF** — 内嵌多页阅读器，在压缩包浏览器里直接翻页
- 🎬 **视频**（MP4 / MOV）— 应用内直接播放。不解压。不写临时文件。点开就看。
- 💻 **文本 / 代码 / Markdown** — 50+ 语言语法高亮
- 🔒 **沙箱隔离** — 所有预览在独立缓存中运行，带容量上限和路径校验

### 🔄 工作流 — 为真实使用场景而生

- 🪟 **多窗口** — 同时操作五个压缩包，你的 Mac 完全 hold 住
- 🖱️ **Finder 集成** — 右键 → 压缩 / 打开，通过 macOS Services 无缝衔接
- 🌗 **深色 / 浅色 / 跟随系统** — 三种外观模式，每种都像素级精致
- 🔍 **全局搜索** — 5 万条目的压缩包里找一个文件？即时定位。
- 💾 **崩溃恢复** — 解压到一半断电了？续传。不用重来。没有残留文件。

---

## 📋 格式支持

| 操作 | 格式 |
|------|------|
| 📂 **打开** | ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO |
| 📦 **创建** | ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST |
| 🔐 **加密** | AES-256（ZIP / 7z） |

---

## 🛡️ 安全架构

**这不是"加个 if 判断"级别的安全。**

Mac 解霸的解压管线，从第一行代码开始就按「对抗恶意压缩包」的标准设计。那种有人专门构造来搞你机器的压缩包。Mac 解霸，纹丝不动。

| 🧱 防护层 | ⚙️ 机制 |
|--------|------|
| 🚫 路径穿越 | `ArchivePathPolicy` 拒绝 `..`、绝对路径、控制字符、空分量 |
| 🔗 符号链接攻击 | 解压前全量扫描，发现 symlink 立即中止整个操作 |
| 📁 文件描述符安全 | 全程 FD 相对操作（`openat` / `mkdirat`）+ `O_NOFOLLOW` + `O_EXCL` |
| 💣 资源炸弹 | 压缩比、展开体积、条目数、目录深度 — 四维预算评估 |
| ⚛️ 原子写入 | 写临时文件 → `fsync` → 原子重命名；失败自动清理 |
| 🏗️ 进程隔离 | 外部工具（7zz / rar）通过显式 argv 数组调用。命令注入：结构上不可能。 |
| 📦 预览沙箱 | 独立缓存目录，带容量上限和路径校验。什么都逃不出去。 |
| 🍎 隔离属性 | 压缩包中打开的文件自动标记 `com.apple.quarantine`，交由 Gatekeeper 评估 |

> 🔒 *"我们对待每一个压缩包，都像对待潜在的恶意软件——直到它证明自己无害。"*

---

## 📸 界面预览

### 🏠 欢迎页

拖入压缩包，直接开始。没有注册。没有引导页。没有废话。

![欢迎页](Assets/screenshots/welcome.png)

### 🌙 压缩包浏览（深色模式）

媒体预览、文件详情、快捷操作——一屏搞定。

![压缩包浏览 - 深色模式](Assets/screenshots/media_dark.png)

### ☀️ 压缩包浏览（浅色模式）

![压缩包浏览 - 浅色模式](Assets/screenshots/media_fixture.png)

### 📦 创建压缩包

选格式、设加密、加文件。跨平台兼容性自动检测。

![创建压缩包](Assets/screenshots/creation.png)

---

## 📖 使用指南

### 📂 解压文件

1. 🖱️ 将压缩包拖入窗口（或 File → Open）
2. 👀 浏览内容，选择需要的文件
3. 📤 点击工具栏「解压缩」，选择目标文件夹
4. ✅ 完成。文件已就位。

### 📦 创建压缩包

1. ➕ 点击欢迎页「新建压缩包」（或 File → New）
2. 🗂️ 选择输出格式：ZIP / 7z / RAR / TAR.GZ / TAR.XZ / TAR.ZST
3. 🖱️ 拖入要压缩的文件和文件夹
4. 🔐 可选：设置密码、调整压缩级别
5. 💾 点击「创建」，选择保存位置

### 👁️ 预览文件

在压缩包浏览界面，单击任意文件：
- 🖼️ 图片全分辨率渲染
- 📄 PDF 内嵌显示，支持翻页
- 🎬 视频直接播放（无需解压）
- 💻 代码语法高亮

### 🪆 嵌套压缩包

双击压缩包内的压缩文件，逐层进入。点返回按钮退出。套娃到底。🐢

---

## ⚔️ 对比现有方案

不是说别的工具不好。是不同的工程选择，带来可量化的差异：

| 维度 | 🏚️ 常见方案 | 🏰 Mac 解霸 |
|------|-------------|-------------|
| 运行时 | Electron / 打包 Python / Node | 纯原生 Swift + SwiftUI |
| 内存（空载） | 200–400 MB 😱 | ~30–50 MB 😌 |
| 解压安全 | 不做或仅做简单路径过滤 | FD 相对操作 + 路径策略 + 资源预算（八层防护） |
| 符号链接 | 直接解压 → 任意文件覆盖 | 全量预扫描，发现即中止 |
| 外部工具调用 | Shell 字符串拼接 | 显式 argv 数组。注入不可能。 |
| 预览 | 先解压到磁盘，再打开 | 沙箱流式预览。不碰你的文件系统。 |
| 崩溃恢复 | 残留文件。从头再来。 | 日志化解压。断点续传。 |
| 遥测 / 广告 | "免费" = 你是产品 | 零遥测。零广告。零网络。句号。 |
| Apple Silicon | Intel 二进制跑 Rosetta | 原生 arm64。M 系列每颗核心都在干活。 |

---

## ⬇️ 安装与构建

### 🛠️ 从源码构建

```bash
git clone https://github.com/smkzw/Mac-Unzip.git
cd Mac-Unzip/ArchiveWorkbench
xcodegen generate
open MacUnzip.xcodeproj
```

Xcode 26 中选 **App** scheme → 目标设备选你的 Mac → 按 **⌘R**。搞定。

### 🔧 外部工具依赖（可选）

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| 7zz | 7z 格式支持 | `brew install 7zip` |
| rar | RAR 创建支持 | 从 RARLAB 官网下载 |

没装？没关系。对应格式自动禁用并给出提示，其他格式照常工作。🤷

---

## 💻 系统要求

| 项目 | 最低要求 |
|------|----------|
| 🖥️ 操作系统 | macOS 26 |
| ⚙️ 芯片 | Apple Silicon（M1 及以上） |
| 🔨 构建工具 | Xcode 26 |
| 💾 磁盘空间 | 约 50 MB（应用本体） |

---

## 📜 许可证

| 层级 | 功能范围 | 价格 |
|------|----------|------|
| 🆓 **免费版** | 解压 ZIP/TAR/GZ、打开和浏览压缩包、格式检测 | $0 |
| 👑 **专业版** | 解压、创建、加密、预览、嵌套浏览、Finder 集成、崩溃恢复 | [¥9.99 →](https://gerymk.qd.je/) |

专业版为一次性买断。终身使用。单台设备。离线 Ed25519 验证。详见 [LICENSE](LICENSE)。

---

## 🤝 贡献与反馈

- 🐛 发现 Bug？→ [提交 Issue](https://github.com/smkzw/Mac-Unzip/issues)
- 💡 有想法？→ 发起 Pull Request
- 🔓 安全漏洞？→ 通过 GitHub Security Advisory 私密报告

---

<p align="center">
  <strong>🗜️ Mac 解霸</strong><br>
  <em>压缩解压，原生就够了。⚡</em><br><br>
  <sub>为 Apple Silicon 而生 ❤️ 本应用的制作过程中没有 Electron 受到伤害（也没有被使用）。</sub>
</p>
