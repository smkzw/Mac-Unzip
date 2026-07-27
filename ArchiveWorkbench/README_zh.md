# Mac解霸（Mac Unzip）

> **解压万物，掌控压缩。**
> 一款为现代 Mac 而生的赛博朋克级解压引擎，原生 Swift 打造，疾如闪电。

[English](README.md) | **[中文](README_zh.md)** | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [日本語](README_ja.md) | [한국어](README_ko.md)

---

**Mac解霸** 是一款纯原生 macOS 压缩解压工具，基于 **Swift 6.2** 与 **SwiftUI** 从零构建，深度优化 **Apple Silicon**。无论是 ZIP、7z、RAR、TAR，还是 DMG、ISO 镜像，它都能轻松打开、创建与加密——一切都在你信赖的 Mac 上完成。

不套壳 Electron，不捆绑运行时，不上传任何数据。专注、极速、可靠。

## 核心功能

### 格式支持
- **解压：** ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST、DMG、ISO
- **压缩：** ZIP、7z、RAR、TAR.GZ、TAR.XZ、TAR.ZST
- **加密：** ZIP 与 7z 支持 AES-256 高强度加密

### 高效工作流
- **拖拽即用**——把压缩包拖入窗口即可解压或预览
- **访达集成**——右键菜单一键压缩、解压任意文件与文件夹
- **包内预览**——图片、PDF、视频、文本、Markdown 无需解压即可查看
- **多窗口支持**——同时处理多个压缩包，互不干扰
- **深色 / 浅色模式**——自动跟随系统外观

### 安全与可靠
- **安全解压**——内置 zip-slip 路径穿越防护
- **拒绝恶意符号链接**，配合资源配额，让恶意压缩包无机可乘
- **崩溃恢复日志**——意外中断的解压任务可断点续传，不再前功尽弃
- **AES-256 加密**——为敏感数据保驾护航

## 应用截图

![Mac解霸](Assets/Logo.svg)

## 安装指南

### 环境要求
- **macOS 26** 或更高版本
- **Apple Silicon**（M 系列芯片）Mac
- 源码编译需 **Xcode 26**

### 从源码构建

```bash
git clone https://github.com/smkzw/ArchiveWorkbench.git
cd ArchiveWorkbench
open ArchiveWorkbench.xcodeproj
```

在 Xcode 26 中选择 **App** Scheme 与目标设备，按下 **⌘R** 即可运行。

仓库根目录另附预编译的 `ArchiveWorkbench-1.0.dmg`，方便快速体验。

## 系统要求

| 项目 | 最低要求 |
| --- | --- |
| 操作系统 | macOS 26 |
| 处理器架构 | Apple Silicon（arm64） |
| 构建工具 | Xcode 26、Swift 6.2 |
| 磁盘空间 | 约 150 MB |

## 许可协议

**个人使用永久免费。** 商业及企业使用需购买付费许可。

- 个人、教育、非商业开源用途——免费
- 公司、自由职业接单、商业产品集成等用途——[需购买许可](LICENSE)

完整条款请参阅 [LICENSE](LICENSE) 文件。

---

© 2026 smkzw 版权所有。
