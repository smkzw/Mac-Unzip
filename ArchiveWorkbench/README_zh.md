<p align="center">
  <img src="Assets/logo-v2.png" alt="Mac Unzip" width="256" height="256">
</p>

<h1 align="center">Mac 解霸 <sub>Mac Unzip</sub></h1>

<p align="center">
  <strong>Swift 6.2 原生 macOS 压缩解压工具，arm64 编译，不套壳。</strong>
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

---

## 目录

- [为什么做这个工具](#为什么做这个工具)
- [核心能力](#核心能力)
- [格式支持](#格式支持)
- [安全架构](#安全架构)
- [界面预览](#界面预览)
- [使用指南](#使用指南)
- [相较现有方案的改进](#相较现有方案的改进)
- [安装与构建](#安装与构建)
- [系统要求](#系统要求)
- [许可证](#许可证)
- [贡献与反馈](#贡献与反馈)

---

## 为什么做这个工具

Mac 上的压缩解压工具不少，但用下来总觉得差点什么：有的套了层 Electron 壳子，内存占用高得离谱；有的把 7zip 二进制直接打包进来，安全性全凭信任；有的解压时不做路径校验，一个恶意压缩包就能把文件写到系统任意位置。

Mac 解霸从零开始用 Swift 6.2 和 SwiftUI 构建，不套壳、不打包第三方运行时、不采集任何用户数据。它只做一件事：安全、快速、可靠地处理你的压缩文件。

---

## 核心能力

### 解压

- 拖入压缩包即刻打开，无需等待完整解压
- 支持密码保护的 ZIP（AES-256 / ZipCrypto）
- 嵌套压缩包逐层浏览，双击即可进入
- 选择性解压：只取出你要的那一个文件或文件夹
- 实时进度反馈，大文件解压随时可取消

### 压缩

- 支持 ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST 六种格式创建
- AES-256 加密保护敏感文件（ZIP / 7z）
- 拖拽添加文件和文件夹，递归保留目录结构
- 压缩级别可调，从极速存储到极限压缩
- 预检机制：创建前自动检测路径冲突和非法字符

### 预览

- 图片（PNG / JPEG / HEIC / SVG / WebP）：缩略图 + 全尺寸预览
- PDF：内嵌渲染，支持多页翻阅
- 视频（MP4 / MOV）：直接播放，无需解压到磁盘
- 文本 / 代码 / Markdown：语法高亮预览
- 所有预览在安全沙箱中完成，不暴露完整文件系统

### 工作流

- 多窗口并行操作多个压缩包
- Finder 右键菜单集成（通过 Services）
- 深色 / 浅色 / 跟随系统三种外观模式
- 全局搜索：万级条目压缩包中即时定位文件
- 崩溃恢复日志：意外中断的解压可续传而非重来

---

## 格式支持

| 操作 | 格式 |
|------|------|
| **打开** | ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO |
| **创建** | ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST |
| **加密** | AES-256（ZIP / 7z） |

---

## 安全架构

这不是"加个 if 判断"级别的安全。Mac 解霸的解压管线从设计之初就按对抗恶意压缩包的标准构建：

| 防护层 | 机制 |
|--------|------|
| 路径穿越 | `ArchivePathPolicy` 拒绝 `..`、绝对路径、控制字符、空分量 |
| 符号链接攻击 | 解压前全量扫描，发现 symlink 立即中止 |
| 文件描述符安全 | 全程 FD 相对操作（`openat` / `mkdirat`），配合 `O_NOFOLLOW` + `O_EXCL` |
| 资源炸弹 | 压缩比、展开体积、条目数、目录深度四维预算评估 |
| 原子写入 | 先写临时文件，`fsync` 后原子重命名，失败自动清理 |
| 进程隔离 | 外部工具（7zz / rar）通过显式 argv 数组调用，绝不经过 shell |
| 预览沙箱 | 预览文件写入独立缓存目录，带尺寸上限和路径校验 |
| 隔离属性 | 从压缩包中打开的文件自动标记 `com.apple.quarantine`，交由 Gatekeeper 评估 |

---

## 界面预览

### 欢迎页

打开应用，拖入压缩包即可开始。

![欢迎页](Assets/screenshots/welcome.png)

### 压缩包浏览（深色模式）

浏览压缩包内容，左侧为文件列表和快捷操作，右侧为文件详情和预览。

![压缩包浏览 - 深色模式](Assets/screenshots/media_dark.png)

### 压缩包浏览（浅色模式）

![压缩包浏览 - 浅色模式](Assets/screenshots/media_fixture.png)

### 创建压缩包

选择格式、设置加密、添加文件，一步到位。

![创建压缩包](Assets/screenshots/creation.png)

---

## 使用指南

### 解压文件

1. 将压缩包拖入窗口（或 File > Open）
2. 浏览内容，选择需要的文件
3. 点击工具栏「解压缩」按钮，选择目标文件夹
4. 等待完成，文件已就位

### 创建压缩包

1. 点击欢迎页「新建压缩包」或 File > New
2. 选择输出格式（ZIP / 7z / RAR / TAR 系列）
3. 拖入要压缩的文件和文件夹
4. 可选：设置密码加密、调整压缩级别
5. 点击「创建」，选择保存位置

### 预览文件

在压缩包浏览界面，单击任意文件即可在右侧面板预览：
- 图片直接显示
- PDF 内嵌渲染
- 视频可播放
- 文本 / 代码带语法高亮

### 嵌套压缩包

双击压缩包内的另一个压缩文件，即可逐层进入浏览。点击工具栏返回按钮回到上一层。

---

## 相较现有方案的改进

不是说别的工具不好——而是我们选了不同的技术路径，这些路径在安全性和资源效率上有明确的取舍：

| 维度 | 现有常见方案 | Mac 解霸的做法 |
|------|-------------|---------------|
| 运行时 | 部分工具基于 Electron 或打包 Python/Node 运行时 | 纯原生 Swift + SwiftUI，无额外运行时 |
| 内存占用 | 套壳应用空载即占 200-400 MB | 原生应用空载约 30-50 MB |
| 解压安全 | 部分工具不做路径校验或仅做简单过滤 | FD 相对操作 + 全量路径策略 + 资源预算，四层防护 |
| 符号链接 | 部分工具解压 symlink 可能导致任意文件覆盖 | 解压前全量扫描，发现即中止 |
| 外部工具调用 | 部分工具通过 shell 拼接命令调用 7zip/rar | 显式 argv 数组，杜绝命令注入 |
| 预览能力 | 多数工具需先解压到磁盘再打开 | 沙箱内流式预览，不落盘、不暴露文件系统 |
| 崩溃恢复 | 解压中断后需手动清理残留文件 | 日志化解压，中断后可续传 |
| 遥测 / 广告 | 部分免费工具含广告或数据采集 | 零遥测、零广告、零网络请求 |
| Apple Silicon | 部分工具仍为 Intel 二进制通过 Rosetta 运行 | 原生 arm64 编译，充分利用 M 系列芯片 |

---

## 安装与构建

### 从源码构建

```bash
git clone https://github.com/smkzw/Mac-Unzip.git
cd Mac-Unzip/ArchiveWorkbench
open ArchiveWorkbench.xcodeproj
```

在 Xcode 26 中选择 **App** scheme，目标设备选你的 Mac，按 **⌘R** 运行。

### 外部工具依赖（可选）

| 工具 | 用途 | 安装方式 |
|------|------|----------|
| 7zz | 7z 格式支持 | `brew install 7zip` |
| rar | RAR 创建支持 | 从 RARLAB 官网下载 |

未安装时，对应格式功能会自动禁用并提示，不影响其他格式使用。

---

## 系统要求

| 项目 | 最低要求 |
|------|----------|
| 操作系统 | macOS 26 |
| 芯片 | Apple Silicon（M1 及以上） |
| 构建工具 | Xcode 26 |
| 磁盘空间 | 约 50 MB（应用本体） |

---

## 许可证

**个人用户**：免费使用，可自由分发。

**企业 / 商业用途**：需购买商业许可。详见 [LICENSE](LICENSE)。

---

## 贡献与反馈

- 遇到问题？请提交 [Issue](https://github.com/smkzw/Mac-Unzip/issues)
- 有改进建议？欢迎发起 Pull Request
- 安全漏洞？请通过 GitHub Security Advisory 私密报告

---

<p align="center">
  <sub>Mac 解霸 — 压缩解压，原生就够了。</sub>
</p>
