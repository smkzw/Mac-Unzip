# Mac Unzip

> **Crack open any archive. Bend compression to your will.**
> A cyberpunk-grade decompression engine forged in native Swift for the modern Mac.

**[English](README.md)** | [中文](README_zh.md) | [Français](README_fr.md) | [Español](README_es.md) | [Italiano](README_it.md) | [日本語](README_ja.md) | [한국어](README_ko.md)

---

**Mac Unzip** is a native macOS archive utility built from the ground up with **Swift 6.2** and **SwiftUI**, optimized for **Apple Silicon**. It opens, creates, and secures archives across every format that matters — ZIP, 7z, RAR, TAR, DMG, and ISO — without ever leaving the Mac you trust.

No Electron. No bundled runtimes. No telemetry. Just a fast, focused tool that does one thing exceptionally well.

## Features

### Formats
- **Open:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO
- **Create:** ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST
- **Encrypt:** AES-256 protection for ZIP and 7z archives

### Workflow
- **Drag & drop** archives anywhere in the window to extract or preview
- **Finder Sync extension** — right-click any file or folder to compress or open it
- **In-app preview** — view images, PDFs, video, text, and Markdown without extracting the whole archive
- **Multi-window support** for juggling several archives at once
- **Dark / Light mode** that follows your system appearance

### Security & Reliability
- **Secure extraction** with zip-slip / path-traversal protection
- **Symlink rejection** and resource budgets to stop malicious archives in their tracks
- **Crash recovery journal** — interrupted extractions resume instead of corrupting
- **AES-256 encryption** for sensitive ZIP and 7z payloads

## Screenshots

![Mac Unzip](Assets/Logo.svg)

## Installation

### Requirements
- **macOS 26** or later
- **Apple Silicon** (M-series) Mac
- **Xcode 26** to build from source

### Build from source

```bash
git clone https://github.com/smkzw/ArchiveWorkbench.git
cd ArchiveWorkbench
open ArchiveWorkbench.xcodeproj
```

Select the **App** scheme, choose your target device, and press **⌘R** in Xcode 26.

A prebuilt `ArchiveWorkbench-1.0.dmg` is also available in the repository root for quick evaluation.

## System Requirements

| Component | Minimum |
| --- | --- |
| Operating system | macOS 26 |
| Architecture | Apple Silicon (arm64) |
| Build tools | Xcode 26, Swift 6.2 |
| Disk space | ~150 MB for the app bundle |

## License

**Personal use is FREE.** Commercial and enterprise use requires a paid license.

- Personal, educational, and non-commercial open-source use — free of charge
- Company, freelance, client, or revenue-generating use — [paid license required](LICENSE)

See the [LICENSE](LICENSE) file for full terms.

---

© 2026 smkzw. All rights reserved.
