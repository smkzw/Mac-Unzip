# macOS Archive App — Initial Evidence Packet

Date: 2026-07-11

This is an initial source packet for design review. It is not the final recommendation.

## Confirmed User Requirements

- Apple Silicon only; latest native macOS stack and Liquid Glass visual language.
- Chinese-first native labels and settings; terminology must be reviewed by Hermes/aishuo MiniMax-M3.
- Create, extract, browse, preview, and edit archive contents where the format permits safe mutation.
- Windows-readable outputs and correct Chinese/English/multilingual filenames.
- Approved provisional format matrix: ZIP and 7z full workflow; TAR/GZIP/BZIP2/XZ/Zstandard create/extract/browse; DMG/ISO read-only; RAR creation only if a lawful open-source option exists.
- Multi-model QC across functions, workflows, visuals, and backend chains; Codex owns final runtime/visual acceptance.

## Commercial Product Evidence

### BetterZip 5

- Product/docs: https://betterzip.app/ and https://betterzip.com/library/betterzip/docs/
- Relevant strengths: archive tree browser, search, preview, add/delete/rename, external-editor round-trip, archive update, operations queue, Quick Look, presets, removal of macOS-specific metadata for Windows compatibility.
- Important constraint: direct modification is format-dependent; its documentation identifies ZIP/7z/RAR single-volume mutation as a narrower capability than general extraction.

### Keka

- Product: https://www.keka.io/en/
- Relevant strengths: drag-and-drop and Finder workflow, broad create/extract matrix, split archives, password flows, approachable single-task UI.
- Relevant gap for this project: it is primarily compression/extraction oriented rather than a full archive-content editor.

### PeaZip

- Repository: https://github.com/peazip/PeaZip
- Relevant strengths: very broad format support, archive conversion, split/join, checksum and encryption workflows, integrated viewers, cross-platform behavior references.
- Tradeoff: not a modern native SwiftUI macOS interaction model.

### Bandizip for macOS

- Product: https://en.bandisoft.com/bandizip.mac/
- Relevant strengths: ZIP edit operations, archive list/selected extraction, image preview, Finder services, integrity/repair tools, password management, code-page autodetection, and explicit NFC/NFD filename-normalization controls.
- Product lesson: encoding and normalization are first-class user-visible compatibility controls, not hidden implementation details.

### WinZip Mac

- Product: https://www.winzip.com/en/product/winzip/mac/
- Relevant strengths: ZIP-centric encryption, add/update workflows, image operations within ZIP, cloud/share workflows, and familiar consumer packaging.
- Product lesson: secure-sharing presets can be clearer than exposing every low-level compression switch in the main flow.

### Archiver and MacZip

- Archiver: https://archiverapp.com/ — preview-first, AES-256, Apple Silicon native, simple consumer positioning.
- MacZip: https://maczip.cn/ — free Chinese-market reference with preview and Apple Silicon support; useful for Chinese terminology and workflow comparison, but not an authoritative engine or license source.

## Apple Platform Evidence

- Liquid Glass adoption: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- SwiftUI Liquid Glass sample: https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass
- Apple Archive framework: https://developer.apple.com/documentation/AppleArchive
- Compression framework: https://developer.apple.com/documentation/compression/
- Initial implication: use standard SwiftUI/AppKit controls so macOS supplies current materials and behaviors; do not treat Apple Archive as a ZIP/7z interoperability engine because it is an Apple archive framework with different transport goals.

## Open-Source Candidates

### libarchive

- Upstream: https://github.com/libarchive/libarchive
- Mature C library for reading/writing streaming archives. Reads many legacy formats including RAR with limitations; writes ZIP, ZIPX, 7z, tar families, cpio, xar, ISO9660 and more.
- The top-level `COPYING` file is a permissive two-clause BSD-style license with a small set of explicitly listed public-domain/triple-licensed source exceptions; build files vary. RAR4 and RAR5 readers are implemented in libarchive source files under the same permissive notice, not by embedding UnRAR. External codecs selected at build/link time still require an SBOM and notice review.
- Strength: broad read coverage and streaming API. Risk: mutation generally means rewriting an archive; encryption and format feature parity vary.

### 7-Zip

- Upstream: https://github.com/ip7z/7zip and https://7-zip.org/
- Mature C++ engine with broad read support and strong 7z/ZIP creation. License and bundled-code inventory require exact review before commercial distribution.
- It does not provide RAR creation.

### ZIPFoundation

- Upstream: https://github.com/weichsel/ZIPFoundation
- MIT Swift library explicitly supporting ZIP create/read/modify, large files, and Apple platforms.
- Source-level verification on 2026-07-11 found: write paths always encode entry names as UTF-8 and set ZIP general-purpose bit 11; read paths support CP437 plus a caller-supplied alternate encoding; ZIP64 creation/removal has dedicated tests. The library explicitly rejects encrypted entries and contains no encryption implementation. It can remain a strong unencrypted ZIP engine, but ZIP AES/ZipCrypto requires a second engine such as minizip-ng or the 7-Zip path.
- Mutation nuance: adding writes before the existing central directory and has a cancellation rollback path, while removal writes a temporary archive then replaces the original. The product must still wrap every mutation in its own copy/verify/fsync/atomic-replace transaction because library-level failure behavior is not a commercial crash-safety guarantee.

### SWCompression

- Upstream: https://github.com/tsolomko/SWCompression
- MIT pure-Swift framework covering compression streams and several archive/container formats, with writing support varying by format.
- Strength: testable Swift surface. Risk: not a full-featured universal archive engine.

### XADMaster

- Upstream: https://github.com/MacPaw/XADMaster
- LGPL-2.1 Objective-C extraction library with broad legacy formats and filename-encoding autodetection.
- Strength: proven macOS extraction/encoding heuristics. Risk: LGPL distribution obligations and extraction-only architecture.

### ShichiZip

- Upstream: https://github.com/idawnlight/ShichiZip
- LGPL-2.1 native macOS 7-Zip derivative with Finder/Quick Look integration and macOS resource-fork handling.
- Useful as interaction and integration reference; copyleft and derivative architecture require careful separation if reused.

### MacPacker

- Upstream: https://github.com/sarensw/MacPacker
- GPL-3.0 native Swift archive browser supporting nested browsing, selective extraction, Quick Look, Finder integration, and current ZIP edit/save.
- Useful product reference; GPL-3.0 is generally incompatible with a closed-source commercial derivative unless the entire distribution strategy accepts GPL obligations.

### Newly discovered low-maturity projects

- SimpleZip: https://github.com/chiba233/SimpleZip — MIT, created 2026-05-12, about 118k Swift lines and 153 test files but only 5 stars/0 forks as of this review. Source inspection confirms it bundles `7zz` and implements RAR creation only by downloading or detecting RARLAB's proprietary `rar` CLI. It is a valuable checklist/reference but is too young and insufficiently independently validated to adopt wholesale without a deep audit.
- libarchive-swift: https://github.com/everpcpc/libarchive-swift — young Swift wrapper with minimal adoption; possible binding reference, not yet a primary foundation.

## Source-Level Reference Audit

### SimpleZip

- RAR installer script downloads current ARM and x64 RARLAB packages, constructs a universal binary, and places it under the user's Application Support directory. It explicitly warns that RAR is proprietary/shareware and must not be shipped without redistribution rights.
- Archive edits use backend commands against a copy and atomic replacement according to its security documentation; this validates the transaction-rewrite direction but does not prove its implementation safe.
- The project disables App Sandbox and targets macOS 13, so it does not directly satisfy a macOS 26-only, latest-Swift/Liquid-Glass product requirement.
- The code volume and feature count accumulated in roughly six weeks are audit risk signals; maturity cannot be inferred from file/test counts alone.

### ShichiZip

- Approximately 40k Swift lines and 61 test files in the shallow source audit; active native macOS 7-Zip derivative with archive mutation, Quick Look, Finder/file-manager workflows, encoding patches, and quarantine regression tests.
- Strong architecture/test reference for an embedded 7-Zip engine. LGPL-2.1 and upstream 7-Zip component licenses require a deliberate distribution/compliance design.

### MacPacker

- Approximately 15k Swift lines and 17 test files; active since 2023 with broader community adoption than the newly created candidates.
- Uses an engine catalog with XADMaster and 7-Zip paths, includes UTF-named archive regression tests, and treats RAR as list/extract only.
- GPL-3.0 means direct code reuse would generally require a GPL-compatible product strategy; use as a behavioral and testing reference unless that business model is chosen.

## RAR Creation Licensing Finding

- Official RAR/WinRAR license: https://www.rarlab.com/license.htm
- Official UnRAR license mirror: https://github.com/pmachapman/unrar/blob/master/license.txt
- The UnRAR source may be embedded for handling/extraction, but the license explicitly forbids using it to develop a RAR-compatible archiver or recreate the proprietary compression algorithm.
- No credible lawful open-source RAR writer has been identified. Claims of RAR creation usually shell out to the proprietary `rar` CLI.
- Source inspection of SimpleZip confirms this pattern: its apparent RAR-create feature installs or discovers RARLAB's proprietary `rar`; it is not an open-source RAR encoder.
- Product options to evaluate in the design: (1) RAR read/extract only; (2) detect and use a user-installed licensed `rar` CLI; (3) negotiate a distribution license with win.rar GmbH. Do not bundle or reverse-engineer RAR writing without written rights.

## Early Architecture Hypothesis For Review

- SwiftUI document-style shell with AppKit bridges where Finder-grade table, drag/drop, Quick Look, menu, and window behavior require them.
- A format-capability registry routes operations to isolated engines rather than pretending all formats support the same actions.
- ZIP path should favor a native Swift implementation for edit/interoperability; broad extraction and 7z path should use audited native libraries/engines behind a C/Objective-C++ boundary.
- All modification is staged as a transaction: materialize changed entries in an app-managed workspace, stream-rewrite to a sibling temporary archive, verify, fsync, then atomically replace while retaining recovery metadata.
- Preview extracts only the selected entry into a quarantined cache with byte/time/type limits and Quick Look integration.
- Cross-platform export preset strips `.DS_Store`, `__MACOSX`, AppleDouble `._*`, resource forks, and unsafe POSIX-only semantics unless the user deliberately selects a preservation preset.

## Open Questions

- Direct notarized distribution, Mac App Store, or both? Sandbox and helper-binary policy change the engine architecture.
- Minimum macOS target within the macOS 26 generation.
- Whether RAR creation may depend on separately licensed/user-installed software if no open-source writer exists.
- Required encryption matrix: ZIP AES, legacy ZipCrypto, and 7z AES-256 have different Windows compatibility and security tradeoffs.

## Current macOS Simplified Chinese Terminology Evidence

Direct inspection of macOS 26.5.1 `/System/Library/CoreServices/Applications/Archive Utility.app` localization tables found these Apple strings:

- App and noun: `归档实用工具`, `归档`, `ZIP归档`, `Apple归档`
- Actions/status: `创建归档…`, `解压缩归档…`, `正在归档…`, `正在解压缩…`
- Settings: `设置…`, `归档实用工具设置`
- Password: `将密码储存在钥匙串中`

This contradicts the MiniMax proposal that `展开`, `偏好设置`, and hiding `钥匙串` are more native-current. The design should use Apple's live strings as the baseline, then use `压缩包` selectively where consumer comprehension is better.
