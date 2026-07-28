# Windows Interoperability Contract

Date: 2026-07-11
Status: proposed acceptance contract; not yet approved

## Why compatibility needs two tiers

“Windows can open it” is not one invariant. Microsoft currently documents that Windows 11 24H2 File Explorer supports ZIP, RAR, 7z and TAR, but does not operate on encrypted archives. Microsoft recommends 7-Zip or WinRAR for encrypted archives. The product therefore must state the receiving environment instead of applying a single ambiguous “Windows compatible” badge.

Primary sources:

- Microsoft Support, “Zip and unzip files”: https://support.microsoft.com/en-US/Windows/Experience/Storage-FileManagement/zip-and-unzip-files
- Microsoft Learn, “tar on Windows”: https://learn.microsoft.com/en-us/windows/tar/
- PKWARE, APPNOTE 6.3.10: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
- 7-Zip, 7z format: https://www.7-zip.org/7z.html
- Microsoft Learn, “Naming Files, Paths, and Namespaces”: https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
- Microsoft Learn, “Case Sensitivity”: https://learn.microsoft.com/en-us/windows/wsl/case-sensitivity

## Product-facing tiers

### Tier W0 — Windows Explorer native

Recipient needs no third-party program on Windows 11 24H2.

- Default format: unencrypted ZIP.
- ZIP compression method: Store or Deflate only.
- File names: UTF-8 with general-purpose bit 11 in both local and central headers, without BOM. PKWARE says that when bit 11 is used for UTF-8 names, Unicode Path/Comment extra fields are not needed and should not be created. A legacy-compatible alternate profile using Info-ZIP 0x7075 remains a test candidate, not the W0 default, until physical Windows/older-tool evidence justifies it.
- Do not emit macOS AppleDouble files, `.DS_Store`, Finder tags, resource-fork sidecars, absolute paths, or unsafe `..` components.
- For a newly generated W0 ZIP, propose NFC UTF-8 path names while preserving the original-to-output mapping for user review. Editing an existing archive never silently rewrites unchanged entry-name bytes.
- Detect collisions using Unicode canonical equivalence plus Windows-default case-insensitive comparison. A collision blocks creation until the user chooses a unique output name; there is no automatic numeric suffix hidden from the review.
- Reject or explicitly rename `< > : " / \\ | ? *`, NUL, control characters U+0001–U+001F, trailing ASCII space/period, and DOS device names `CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `COM¹`–`COM³`, `LPT1`–`LPT9`, and `LPT¹`–`LPT³`, including those names followed by any extension.
- Enforce 255 UTF-16 code units per path component. Because the receiver's extraction root is unknowable, W0 uses a conservative 180 UTF-16-code-unit archive-relative path budget and labels longer paths as `可能超出部分 Windows 程序的路径限制`; physical acceptance extracts under the documented test root and verifies the complete path stays within 260 characters. Advanced users may keep the original path, which removes the W0 guarantee.
- Preserve portable timestamps; macOS-only metadata is opt-in and never required to understand the archive.
- No encryption badge may claim W0 compatibility because Windows Explorer does not support encrypted archives.

### Tier W1 — Windows 7-Zip/WinRAR compatible

Recipient may install current 7-Zip or WinRAR.

- Formats: 7z, encrypted 7z, AES-encrypted ZIP, ZipCrypto ZIP, RAR read/extract and licensed RAR output.
- Default secure choice: 7z AES-256 with encrypted headers where confidentiality matters.
- Compatibility choice: ZipCrypto ZIP, clearly labeled “兼容性较高，保护较弱”.
- AES ZIP is labeled as requiring a compatible third-party decompressor on Windows.
- Generated RAR is never promised unless the RARLAB provider passes discovery, license acknowledgment and a live create/test probe.

### Tier W2 — Specialist/command-line interoperable

- TAR, TAR.GZ, TAR.BZ2, TAR.XZ and TAR.ZST are standards-based transfer formats but are not presented as the default consumer handoff.
- The UI states the expected receiver (`Windows 11 24H2`, `Windows tar`, or a named third-party tool) and never collapses this tier into W0.

## Creation presets

| Chinese UI preset | Output contract | Required warning |
|---|---|---|
| `发给 Windows 用户` | W0 unencrypted Store/Deflate ZIP | None when filename/path preflight passes |
| `跨平台加密分享` | W1 AES-256 7z with encrypted headers | `接收方需要 7-Zip 或 WinRAR` |
| `兼容旧版解压软件` | W1 ZipCrypto ZIP | `兼容性较高，但密码保护较弱` |
| `长期归档` | W1/W2 7z or TAR.ZST, user-selected | Receiver and recovery requirements shown |

The preset name is separate from the exact format. Internal codes W0/W1/W2 do not appear in the primary interface. Advanced settings and diagnostics reveal the exact format, method, encryption, split size, filename policy and receiver requirement.

## Filename-conflict workflow

1. Preflight lists every invalid, canonical-equivalent, case-insensitive or path-budget conflict before writing.
2. Each row shows `原名称`, `输出名称`, reason and affected receiving environment.
3. User may rename one, apply a reviewed batch rule, remove the entry, or switch to a professional preset that preserves names but drops the Windows-native guarantee.
4. The app reruns the whole-tree collision check after every change. Creation remains disabled until no W0 conflict exists.
5. Extraction never silently overwrites two entries that collapse to one destination name. The conflict sheet requires skip, keep both with reviewed names, or choose another destination/preset.

## Acceptance fixtures

Each generator path must be tested with:

- Simplified and Traditional Chinese; Japanese; Korean; Arabic and right-to-left marks; Latin diacritics; emoji and supplementary-plane characters.
- NFC/NFD-equivalent names, Windows case-fold collisions, reserved names, trailing dot/space, deep paths, empty files, sparse-like large files, symlinks and executable bits.
- 0 B, 1 B, 4 GiB boundary, ZIP64, high-entry-count and split-archive cases.
- Random binary data, already compressed media, incompressible data and highly compressible text.
- Correct password, wrong password, canceled operation, truncated archive, damaged central directory and missing split volume.

## Required physical test matrix

No engine-only test can close cross-platform acceptance. Release candidates need real-open tests on:

1. Windows 11 24H2 File Explorer: open/list/extract W0 ZIP; open/list/extract supported unencrypted 7z/TAR/RAR cases.
2. Current Windows 7-Zip: list/test/extract every W1/W2 format and password mode.
3. Current WinRAR: list/test/extract ZIP/7z/RAR, including multilingual paths and multipart cases.
4. macOS app round-trip: create, reopen, edit by transactional rebuild, integrity-test and extract.
5. Hash and manifest comparison across macOS and Windows after extraction.

Current evidence: local Apple Silicon 7-Zip smoke tests cover Unicode and encryption mechanics. A real Windows VM/device is not presently configured in this workspace, so the physical Windows rows remain open release gates.
