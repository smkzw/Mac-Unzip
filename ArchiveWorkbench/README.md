<p align="center">
  <img src="Assets/logo-v2.png" alt="Mac Unzip" width="256" height="256">
</p>

<h1 align="center">Mac Unzip <sub>Mac 解霸</sub></h1>

<p align="center">
  <strong>Swift 6.2 native macOS archive utility. arm64 compiled, no wrappers.</strong>
</p>

<p align="center">
  <strong>English</strong> | <a href="README_zh.md">中文</a> | <a href="README_fr.md">Français</a> | <a href="README_es.md">Español</a> | <a href="README_it.md">Italiano</a> | <a href="README_ja.md">日本語</a> | <a href="README_ko.md">한국어</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2026-blue" alt="Platform">
  <img src="https://img.shields.io/badge/arch-Apple%20Silicon-orange" alt="Architecture">
  <img src="https://img.shields.io/badge/Swift-6.2-red" alt="Swift">
  <img src="https://img.shields.io/badge/license-Personal%20Free%20%2F%20Commercial%20Paid-green" alt="License">
</p>

---

## Table of Contents

- [Why This Exists](#why-this-exists)
- [Core Capabilities](#core-capabilities)
- [Format Support](#format-support)
- [Security Architecture](#security-architecture)
- [Screenshots](#screenshots)
- [Usage Guide](#usage-guide)
- [How It Compares](#how-it-compares)
- [Installation & Building](#installation--building)
- [System Requirements](#system-requirements)
- [License](#license)
- [Contributing & Feedback](#contributing--feedback)

---

## Why This Exists

Mac users have options for archive utilities, but each comes with trade-offs. Some wrap Electron around a Node.js runtime and eat 300 MB of RAM before you open a single file. Others bundle a raw 7zip binary and call it a day, leaving path-traversal protection as an exercise for the user. A few skip symlink validation entirely, which means a crafted archive can write files anywhere your user account can reach.

Mac Unzip is built from scratch in Swift 6.2 and SwiftUI. No wrapper frameworks, no bundled runtimes, no telemetry, no network calls. It handles archives safely and quickly, and it runs natively on Apple Silicon.

---

## Core Capabilities

### Extraction

- Drop an archive into the window; it opens instantly without full extraction
- Password-protected ZIP support (AES-256 / ZipCrypto)
- Nested archive navigation: double-click to drill into archives within archives
- Selective extraction: pull out a single file or folder without unpacking everything
- Real-time progress with cancellation support for large archives

### Creation

- Create ZIP, 7z, RAR, TAR.GZ, TAR.XZ, and TAR.ZST archives
- AES-256 encryption for sensitive payloads (ZIP / 7z)
- Drag-and-drop file and folder addition with recursive directory preservation
- Adjustable compression levels from fastest to maximum
- Preflight checks: path conflicts and illegal characters caught before creation begins

### Preview

- Images (PNG / JPEG / HEIC / SVG / WebP): thumbnail grid + full-size preview
- PDF: embedded rendering with multi-page navigation
- Video (MP4 / MOV): in-app playback without extracting to disk
- Text / code / Markdown: syntax-highlighted preview
- All previews run in a sandboxed cache with size limits and path validation

### Workflow

- Multi-window support for working with several archives simultaneously
- Finder integration via macOS Services (right-click to compress or open)
- Dark / Light / System appearance modes
- Global search across archives with tens of thousands of entries
- Crash recovery journal: interrupted extractions resume instead of starting over

---

## Format Support

| Operation | Formats |
|-----------|---------|
| **Open** | ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST, DMG, ISO |
| **Create** | ZIP, 7z, RAR, TAR.GZ, TAR.XZ, TAR.ZST |
| **Encrypt** | AES-256 (ZIP / 7z) |

---

## Security Architecture

This is not "add an if-statement and ship it" security. The extraction pipeline is designed from the ground up to handle hostile archives:

| Defense Layer | Mechanism |
|---------------|-----------|
| Path traversal | `ArchivePathPolicy` rejects `..`, absolute paths, control characters, empty components |
| Symlink attacks | Full scan before extraction; any symlink aborts the operation |
| File descriptor safety | FD-relative operations throughout (`openat` / `mkdirat`) with `O_NOFOLLOW` + `O_EXCL` |
| Resource bombs | Four-dimensional budget: compression ratio, expanded size, entry count, directory depth |
| Atomic writes | Write to temp file, `fsync`, atomic rename; automatic cleanup on failure |
| Process isolation | External tools (7zz / rar) invoked via explicit argv arrays, never through a shell |
| Preview sandbox | Preview files written to isolated cache with size caps and path validation |
| Quarantine | Files opened from archives are tagged with `com.apple.quarantine` for Gatekeeper evaluation |

---

## Screenshots

### Welcome

Drop an archive in and go.

![Welcome](Assets/screenshots/welcome.png)

### Archive Browsing (Dark Mode)

Browse archive contents with file list, quick actions, and inline preview.

![Archive Browsing - Dark](Assets/screenshots/media_dark.png)

### Archive Browsing (Light Mode)

![Archive Browsing - Light](Assets/screenshots/media_fixture.png)

### Create Archive

Pick a format, set encryption, add files, done.

![Create Archive](Assets/screenshots/creation.png)

---

## Usage Guide

### Extracting Files

1. Drop an archive into the window (or File > Open)
2. Browse contents, select what you need
3. Click "Extract" in the toolbar, choose a destination folder
4. Done. Your files are in place.

### Creating Archives

1. Click "New Archive" on the welcome screen (or File > New)
2. Choose an output format (ZIP / 7z / RAR / TAR variants)
3. Drag in the files and folders you want to compress
4. Optional: set a password, adjust compression level
5. Click "Create" and pick a save location

### Previewing Files

In the archive browser, click any file to preview it in the right panel:
- Images render directly
- PDFs display inline
- Videos play in-app
- Text and code get syntax highlighting

### Nested Archives

Double-click a compressed file inside an archive to drill into it. Use the back button in the toolbar to navigate up a level.

---

## How It Compares

Not a claim that other tools are bad. These are different technical choices with clear trade-offs in security and resource efficiency:

| Dimension | Common existing approaches | What Mac Unzip does |
|-----------|---------------------------|---------------------|
| Runtime | Some tools ship Electron or bundle Python/Node runtimes | Pure native Swift + SwiftUI, no additional runtime |
| Memory footprint | Wrapped apps idle at 200-400 MB | Native app idles around 30-50 MB |
| Extraction safety | Some tools skip path validation or do minimal filtering | FD-relative ops + full path policy + resource budgets, four layers deep |
| Symlinks | Some tools extract symlinks, enabling arbitrary file overwrite | Full pre-scan; any symlink halts extraction |
| External tool invocation | Some tools shell out with string-interpolated commands | Explicit argv arrays; command injection is structurally impossible |
| Preview | Most tools require full extraction to disk before viewing | Sandboxed streaming preview; nothing touches your filesystem |
| Crash recovery | Interrupted extraction leaves orphaned partial files | Journaled extraction with resume capability |
| Telemetry / ads | Some free tools include ads or data collection | Zero telemetry, zero ads, zero network requests |
| Apple Silicon | Some tools still ship Intel binaries running under Rosetta | Native arm64 build, fully utilizing M-series chips |

---

## Installation & Building

### Build from Source

```bash
git clone https://github.com/smkzw/Mac-Unzip.git
cd Mac-Unzip/ArchiveWorkbench
open ArchiveWorkbench.xcodeproj
```

In Xcode 26, select the **App** scheme, target your Mac, and press **⌘R**.

### External Tool Dependencies (Optional)

| Tool | Purpose | Install |
|------|---------|---------|
| 7zz | 7z format support | `brew install 7zip` |
| rar | RAR creation | Download from RARLAB |

If not installed, the corresponding format is gracefully disabled with a clear message. All other formats continue to work.

---

## System Requirements

| Requirement | Minimum |
|-------------|---------|
| OS | macOS 26 |
| Chip | Apple Silicon (M1 or later) |
| Build tools | Xcode 26 |
| Disk space | ~50 MB (app binary) |

---

## License

**Personal use**: Free. Distribute freely.

**Enterprise / commercial use**: Requires a commercial license. See [LICENSE](LICENSE) for details.

---

## Contributing & Feedback

- Found a bug? File an [Issue](https://github.com/smkzw/Mac-Unzip/issues)
- Have an improvement? Open a Pull Request
- Security vulnerability? Report privately via GitHub Security Advisory

---

<p align="center">
  <sub>Mac Unzip. Compression, the native way.</sub>
</p>
