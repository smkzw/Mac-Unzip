# Engine and Distribution Matrix

Date: 2026-07-11
Status: evidence-backed design input; not yet an approved architecture

## Installation Findings

Primary Apple sources:

- App Sandbox overview: https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
- Embedded sandbox helper: https://developer.apple.com/documentation/Xcode/embedding-a-helper-tool-in-a-sandboxed-app
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Direct distribution: https://developer.apple.com/macos/distribution/
- Quick Look UI and preview extensions: https://developer.apple.com/documentation/QuickLookUI
- Finder Sync scope: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html

Evidence:

- The immediate target is self-installation on the user's own Mac. The architecture must also be ready for a later website-distributed Developer ID/notarized build and a possible GitHub open-source edition, but no upload, remote repository creation or public release is authorized yet.
- The local build may use ad-hoc/local signing. A later website build needs Developer ID signing, hardened runtime and notarization. Both may detect a separately installed RARLAB tool, subject to explicit user choice and the tool's own license.
- App Sandbox is a product-security decision rather than a distribution requirement. The design should begin with least-privilege file access, but may use a non-sandboxed local build if broad archive workflows or external-provider access cannot be made reliable inside the sandbox.
- A modern Finder preview integration is a Quick Look Preview Extension (`QLPreviewingController` or `QLPreviewProvider`), not a legacy `.qlgenerator`.
- Finder Sync is intended for sync-status UI in monitored folders, not as a general archive-action injection point. Archive actions should use file associations, Finder Quick Actions/Action Extensions, Services, App Intents/Shortcuts, and standard context/Share menus as appropriate.

Confirmed current delivery: one Apple Silicon local build for the user's own Mac, with source/package boundaries prepared for a future website build and possible open-source edition. Mac App Store is excluded. The architecture must isolate helpers, record component licenses and avoid accidental redistribution of proprietary RARLAB binaries.

## Engine Candidates

### minizip-ng 4.2.2

Upstream: https://github.com/zlib-ng/minizip-ng

Verified capabilities from upstream README and local build:

- ZIP create/extract, append/remove entries, raw entry copying, memory and streaming I/O.
- ZIP64, split archives, Traditional PKWARE encryption, WinZip AES, UTF-8 names, and legacy CP437/932/936/950 decoding.
- Central-directory recovery, symbolic-link and cross-filesystem attribute handling.
- zlib license; optional linked codecs need their own notice inventory.
- Native Apple Silicon release build succeeded locally with AppleClang 21 on macOS 26.5.1.
- Upstream CTest result: 244/244 passed, including append/erase, split, central-directory compression, ZipCrypto, WinZip AES, Zstandard and encoding/unit paths.

Assessment: preferred ZIP engine. It covers the full ZIP requirement more directly than ZIPFoundation and avoids routing encrypted ZIP to a second library.

### ZIPFoundation 0.9.20

Upstream: https://github.com/weichsel/ZIPFoundation

Verified capabilities:

- MIT, native Swift, UTF-8 writes with ZIP bit 11, caller-selected legacy decoding, ZIP64 tests, add/remove support.
- Explicitly does not support encrypted archives.
- Add and remove have different mutation semantics; product-level copy/verify/atomic-replace remains mandatory.

Assessment: high-quality reference or optional simple ZIP reader, but not the primary engine because the required ZIP encryption scope would force an additional backend.

### libarchive 3.8.x

Upstream: https://github.com/libarchive/libarchive

Verified source capabilities:

- Permissive project license with explicitly documented exceptions and build-file variation.
- Independent BSD-style RAR4 and RAR5 readers; no mandatory UnRAR embedding.
- Streaming read/write for ZIP/ZIPX, 7z, TAR families, ISO9660, XAR, CPIO and other formats.
- Current ZIP writer contains Traditional PKWARE, WinZip AES-128 and WinZip AES-256 support when built with a crypto provider.
- Current 7z writer supports Copy, Deflate, BZip2, LZMA1/LZMA2, PPMd and Zstandard, but no 7z encryption writer was found.
- Current libarchive cannot read encrypted RAR/7z payloads; an upstream issue confirms the encrypted-data read path is unsupported.
- In-place modification and random access are explicitly outside libarchive's design; application-level streaming rewrite is required.
- `archive_write_disk_header()` must be serialized on POSIX due to its process-wide `umask` behavior.
- Native Apple Silicon release build succeeded locally with AppleClang 21 on macOS 26.5.1.
- Upstream CTest result: 1005/1005 test targets completed with zero failures in 37.76 seconds. Sixty-three targets were reported as skipped/disabled by the upstream harness, principally Windows-only UTF-16/code-page cases, unavailable optional `grzip`/`lrzip`/`lzop` filters, platform ACL/xattr cases, and several fixture-gated RAR edge cases. These skips remain explicit coverage gaps rather than passing evidence.

Assessment: preferred broad-format streaming engine and TAR/Zstandard/ISO path, but not the only 7z/RAR engine because encryption is a user requirement.

### Official 7-Zip / `7zz`

Upstream: https://github.com/ip7z/7zip and https://www.7-zip.org/license.txt

Verified capabilities and constraints:

- Reference 7z implementation; supports full 7z create/read/update and AES encryption, plus encrypted RAR extraction.
- License is LGPL for most/all other files; `7z.dll` mixes LGPL, BSD, and UnRAR-restricted decompression code. Binary distributions must reproduce license information.
- Commercial use is allowed, but closed commercial distribution still needs an LGPL-compliance plan and exact source/notice package.
- Local 7-Zip 26.01 ARM64 smoke test created and verified AES-256 ZIP and header-encrypted AES 7z archives with Simplified Chinese, Japanese, Arabic, emoji, deep-path, zero-byte, and binary entries.
- The inspected test binary is universal; an Apple Silicon-only product should ship a separately built or thinned ARM64 helper and sign it as nested code.

Assessment: preferred isolated helper for full 7z operations and encrypted RAR/7z extraction. Do not expose its raw CLI output or command syntax to the UI. All arguments must use end-of-options protection, controlled working directories, bounded output, cancellation, and structured error mapping.

### RARLAB `rar`

Primary license: https://www.rarlab.com/license.htm

- Only credible RAR creation path found.
- Proprietary shareware; no lawful open-source RAR writer was identified.
- The local build may detect a separately installed licensed binary. Bundling or redistributing it remains prohibited without written rights.

Assessment: optional external provider, never a required dependency for core app operation.

## Proposed Capability Routing

| Capability | Preferred engine | Fallback | Notes |
|---|---|---|---|
| ZIP browse/create/edit/repair | minizip-ng | libarchive / 7zz | Always wrap edit in app transaction |
| ZIP AES/ZipCrypto | minizip-ng | libarchive / 7zz | UI labels security vs compatibility clearly |
| 7z browse/create/edit/encrypt | embedded ARM64 7zz helper | libarchive for unencrypted basic path | 7z edit is archive rebuild/update, not cheap in-place mutation |
| TAR/GZIP/BZIP2/XZ/Zstandard | libarchive | system tools only for diagnostics | Preserve streaming and metadata policies |
| RAR browse/extract | 7zz helper | libarchive for unencrypted/limited cases | Multipart and encrypted cases require 7zz verification |
| RAR create | user-installed licensed RARLAB `rar` | none | Local provider only; never copy it into a distributable bundle without written rights |
| ISO browse/extract | libarchive | 7zz helper | ISO9660/UDF coverage needs fixture matrix |
| DMG browse/mount/extract | public macOS mechanisms and isolated system workflow | libarchive/7zz only where format support is proven | Mount and raw extraction are separate UX actions |
| Preview selected entry | engine stream to app-owned quarantined cache + Quick Look | built-in safe text/image viewers | Never execute extracted content automatically |

## Architecture Consequences

- `ArchiveCapabilityRegistry` is the single source of truth for format/operation support and user-facing reasons for read-only or rebuild-required states.
- The UI never calls a codec directly. It calls typed operations through `ArchiveCore` and receives structured progress, warnings, conflicts and failure categories.
- `ArchiveTransaction` owns staging, free-space estimation, source-version checks, verification, fsync, atomic replacement, backup retention and crash recovery for every mutation.
- In-process libraries operate in bounded worker tasks; external helpers use a hardened process runner with no shell, explicit argv, sanitized environment, time/output limits, cancellation and signed-helper verification.
- Quick Look Preview Extension is read-only and resource-bounded. Finder Sync is excluded unless a future sync-status use case appears.

## Domestic and Non-GitHub Platform Search

- SourceForge confirmed active 7-Zip and PeaZip distributions, but neither supplies a native SwiftUI editor architecture.
- Repeated Gitee API searches for Chinese and English macOS/Swift archive-manager terms returned no usable repository results during this run.
- GitCode/Gitee web-index searches produced no independently maintained, licensed, mature native macOS candidate beyond mirrors or unrelated compression code.
- Conclusion: domestic products remain valuable for Chinese UX terminology and expectations, but the credible reusable engine pool is currently upstream GitHub/libarchive/7-Zip/minizip-ng rather than a domestic native-app framework.

## Remaining Evidence Gaps

- The 63 skipped/disabled libarchive targets still need targeted replacement fixtures where they overlap product requirements, especially encrypted/solid/multipart RAR, RAR5 Unicode, Windows legacy code pages, and ISO/UDF variants.
- Windows 11 Explorer/7-Zip/WinRAR interoperability is not yet physically verified.
- A component inventory and license record are not yet generated. A future website/open-source profile will additionally require an exact notice/source-compliance package before it can be released.
- Full Xcode is not installed, so SwiftUI Liquid Glass, app extensions, signing and rendered UI remain unverified.
- Current installation is local. Website distribution and a possible GitHub open-source edition must be architecture-compatible but are not authorized for upload/release. Mac App Store remains out of scope.
