# Real ZIP Provider Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixture-only ZIP path with a real, native arm64 workflow that opens and lists a UTF-8 ZIP, safely materializes one regular entry, creates a Windows Explorer-compatible ZIP, and drives the existing macOS document shell from provider data.

**Architecture:** Add a pinned minizip-ng C target behind a narrow C bridge, then expose it through a Swift `ZIPArchiveProvider` actor. The provider maps all C results into `ArchiveDomain` values, applies `ArchiveSecurity` budgets and path policy before publication, and never exposes a minizip handle to the app. The app receives immutable document snapshots and keeps the current Finder-like presentation independent of the engine.

**Tech Stack:** Swift 6.2, Swift Package Manager, SwiftUI/AppKit, minizip-ng 4.2.1 at commit `26b4619120f714cb76c0c52cdd48223bee944d73`, Apple Compression/zlib, XCTest, XcodeGen, macOS 26, arm64 only.

## Global Constraints

- Build and run only on Apple Silicon; `ARCHS` and `VALID_ARCHS` remain `arm64`.
- Pin minizip-ng to release 4.2.1 commit `26b4619120f714cb76c0c52cdd48223bee944d73`; record its zlib license and do not fetch an unpinned branch during a build.
- The app and Swift provider never call minizip-ng directly; all C ownership stays inside `CMinizipBridge`.
- This slice supports UTF-8 ZIP names only. Legacy CP437/CP932/CP936/CP950 byte-preserving decode is a separate provider slice and must not be claimed by these tests.
- Extraction publishes regular files only, validates the archive path before writing, refuses links and special files, and enforces a non-overrideable `ResourceBudget` for previews.
- The Windows-native creation profile emits unencrypted ZIP using Store or Deflate, UTF-8 general-purpose bit 11, NFC names, no `.DS_Store`, `._*`, or `__MACOSX`, and no hidden fallback to another engine.
- Passwords, AES/ZipCrypto, split archives, mutation, integrity recovery, and physical Windows acceptance are outside this slice; capability UI must not infer them from this implementation.
- `检测完整性` remains only inside the labeled `操作` secondary menu.
- No GitHub upload, remote publication, notarization submission, or external distribution occurs without an explicit user command.

---

## File Structure

- `ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng/`: exact upstream C/header subset and unchanged upstream `LICENSE`.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/include/AWBMinizipBridge.h`: the only C API imported by Swift.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`: owns reader/writer handles and converts minizip return values into a small stable ABI.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ArchiveProvider.swift`: provider protocol and immutable document/entry metadata contracts.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`: actor-isolated ZIP listing, entry reads, and Windows-profile creation.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPProviderError.swift`: explicit C-to-domain error mapping.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`: descriptor-rooted, no-follow publication of validated bytes.
- `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`: security-scoped URL access and provider snapshot loading.
- `ArchiveWorkbench/App/Sources/AppModel.swift`: loading/error/document state derived from real snapshots.
- `ArchiveWorkbench/App/Sources/RootWindowView.swift`: native open panel and real-document routing.

### Task 1: Pin minizip-ng and prove the C bridge boundary

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng/LICENSE`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng/UPSTREAM.json`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng/mz_config.h`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/include/AWBMinizipBridge.h`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Tests/CMinizipBridgeTests/CMinizipBridgeTests.swift`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Package.swift`

**Interfaces:**
- Consumes: minizip-ng `MZ_VERSION` and zlib license at the pinned commit.
- Produces: `const char *awb_mz_version(void)` and an SPM library target named `CMinizipBridge`.

- [ ] **Step 1: Import the exact upstream source subset**

Run the following from the worktree root; this is a byte-for-byte vendor import, not a source rewrite:

```bash
git clone --depth 1 --branch 4.2.1 https://github.com/zlib-ng/minizip-ng.git /tmp/minizip-ng-4.2.1
test "$(git -C /tmp/minizip-ng-4.2.1 rev-parse HEAD)" = "26b4619120f714cb76c0c52cdd48223bee944d73"
mkdir -p ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng
rsync -a --delete --include='LICENSE' --include='mz.h' --include='mz_crypt.c' --include='mz_crypt.h' --include='mz_crypt_apple.c' --include='mz_os.c' --include='mz_os.h' --include='mz_os_posix.c' --include='mz_strm.c' --include='mz_strm.h' --include='mz_strm_buf.c' --include='mz_strm_buf.h' --include='mz_strm_libcomp.c' --include='mz_strm_libcomp.h' --include='mz_strm_mem.c' --include='mz_strm_mem.h' --include='mz_strm_os.h' --include='mz_strm_os_posix.c' --include='mz_strm_pkcrypt.c' --include='mz_strm_pkcrypt.h' --include='mz_strm_split.c' --include='mz_strm_split.h' --include='mz_strm_wzaes.c' --include='mz_strm_wzaes.h' --include='mz_strm_zlib.c' --include='mz_strm_zlib.h' --include='mz_zip.c' --include='mz_zip.h' --include='mz_zip_rw.c' --include='mz_zip_rw.h' --exclude='*' /tmp/minizip-ng-4.2.1/ ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng/
```

Expected: the destination contains the listed files only; `git diff --no-index /tmp/minizip-ng-4.2.1/LICENSE ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng/LICENSE` exits 0.

- [ ] **Step 2: Add immutable provenance and macOS feature configuration**

Create `UPSTREAM.json` exactly as:

```json
{
  "name": "minizip-ng",
  "version": "4.2.1",
  "commit": "26b4619120f714cb76c0c52cdd48223bee944d73",
  "repository": "https://github.com/zlib-ng/minizip-ng",
  "license": "Zlib"
}
```

Create `mz_config.h` exactly as:

```c
#ifndef MZ_CONFIG_H
#define MZ_CONFIG_H
#define HAVE_DIRENT_H 1
#define HAVE_SYS_DIRENT_H 0
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1
#define HAVE_PDIR 1
#define HAVE_FSEEKO 1
#define HAVE_SYMLINK 1
#define HAVE_READLINK 1
#endif
```

- [ ] **Step 3: Write the failing bridge version test**

```swift
import CMinizipBridge
import XCTest

final class CMinizipBridgeTests: XCTestCase {
    func testPinnedEngineVersion() {
        XCTAssertEqual(String(cString: awb_mz_version()), "4.2.1")
    }
}
```

- [ ] **Step 4: Add the package targets and run the red test**

Add a `CMinizipBridge` target whose path is `Sources/CMinizipBridge`, whose public headers are under `include`, and whose C settings define `MZ_ZLIB`, `MZ_LIBCOMP`, `MZ_PKCRYPT`, `MZ_WZAES`, `MZ_ICONV`, and the absolute include search path to `ThirdParty/minizip-ng`. Add the exact vendored `.c` files as sources by symlinking them into `Sources/CMinizipBridge/vendor` with relative links, so Xcode and SwiftPM see one target root. Add `CMinizipBridgeTests` depending on that target.

Run:

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
swift test --filter CMinizipBridgeTests/testPinnedEngineVersion
```

Expected: FAIL at compile/link time because `awb_mz_version` is not declared or implemented.

- [ ] **Step 5: Implement the smallest bridge API**

`AWBMinizipBridge.h`:

```c
#ifndef AWB_MINIZIP_BRIDGE_H
#define AWB_MINIZIP_BRIDGE_H
#ifdef __cplusplus
extern "C" {
#endif
const char *awb_mz_version(void);
#ifdef __cplusplus
}
#endif
#endif
```

`AWBMinizipBridge.c`:

```c
#include "AWBMinizipBridge.h"
#include "mz.h"
const char *awb_mz_version(void) { return MZ_VERSION; }
```

- [ ] **Step 6: Prove SwiftPM and Xcode can link the pinned bridge**

Run:

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
swift test --filter CMinizipBridgeTests/testPinnedEngineVersion
cd ../../..
xcodegen generate --spec ArchiveWorkbench/project.yml
xcodebuild -project ArchiveWorkbench/ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -configuration Debug -destination 'platform=macOS,arch=arm64' build
```

Expected: the focused test passes and Xcode reports `** BUILD SUCCEEDED **` with an arm64 application binary.

- [ ] **Step 7: Commit the dependency boundary**

```bash
git add ArchiveWorkbench/Packages/ArchiveKit/Package.swift ArchiveWorkbench/Packages/ArchiveKit/ThirdParty/minizip-ng ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge ArchiveWorkbench/Packages/ArchiveKit/Tests/CMinizipBridgeTests
git commit -m "build: pin native minizip zip engine"
```

### Task 2: List real UTF-8 ZIP entries through an actor provider

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ArchiveProvider.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPProviderError.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests/ZIPArchiveProviderTests.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests/Fixtures/.gitkeep`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/include/AWBMinizipBridge.h`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Package.swift`

**Interfaces:**
- Consumes: `ArchiveEntry`, `ArchivePathPolicy`, and bridge-owned minizip readers.
- Produces: `public protocol ArchiveProvider`, `public struct ArchiveDocumentSnapshot`, `public struct ArchiveEntrySnapshot`, and `public actor ZIPArchiveProvider` with `open(url:)` and `readEntry(id:maximumBytes:)`.

- [ ] **Step 1: Define provider value contracts**

```swift
import ArchiveDomain
import Foundation

public struct ArchiveEntrySnapshot: Equatable, Sendable {
    public let entry: ArchiveEntry
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let modifiedAt: Date?
    public let isDirectory: Bool
    public let isEncrypted: Bool
}

public struct ArchiveDocumentSnapshot: Equatable, Sendable {
    public let sourceURL: URL
    public let format: ArchiveFormat
    public let entries: [ArchiveEntrySnapshot]
}

public protocol ArchiveProvider: Actor {
    func open(url: URL) throws -> ArchiveDocumentSnapshot
    func readEntry(id: ArchiveEntryID, maximumBytes: UInt64) throws -> Data
}
```

- [ ] **Step 2: Write failing listing tests against deterministic fixtures**

The test creates its fixture with the system `/usr/bin/zip` only as test setup; production code must use minizip-ng.

```swift
import ArchiveProviders
import XCTest

final class ZIPArchiveProviderTests: XCTestCase {
    func testOpenListsUTF8FilesAndDirectories() async throws {
        let fixture = try ZIPFixture.make(entries: [
            "文档/说明.txt": Data("你好 Windows".utf8),
            "图片/封面.png": Data([0x89, 0x50, 0x4e, 0x47])
        ])
        let provider = ZIPArchiveProvider()
        let snapshot = try await provider.open(url: fixture.archiveURL)
        XCTAssertEqual(snapshot.format, .zip)
        XCTAssertEqual(snapshot.entries.filter { !$0.isDirectory }.map(\.entry.displayPath), ["文档/说明.txt", "图片/封面.png"])
        XCTAssertTrue(snapshot.entries.allSatisfy { $0.entry.rawPath.bytes == Array($0.entry.displayPath.utf8) })
    }

    func testOpenRejectsNonZipBytes() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try Data("not zip".utf8).write(to: url)
        let provider = ZIPArchiveProvider()
        do {
            _ = try await provider.open(url: url)
            XCTFail("expected corruptedArchive")
        } catch let error as ArchiveError {
            XCTAssertEqual(error, .corruptedArchive)
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify red state**

Run:

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
swift test --filter ZIPArchiveProviderTests
```

Expected: FAIL because `ArchiveProviders`, `ZIPArchiveProvider`, and bridge reader functions do not exist.

- [ ] **Step 4: Add an opaque reader ABI**

Extend the bridge header with fixed-width, ownership-explicit declarations:

```c
#include <stdint.h>
typedef struct awb_mz_reader awb_mz_reader;
typedef struct {
    const uint8_t *name_bytes;
    uint16_t name_size;
    uint64_t compressed_size;
    uint64_t uncompressed_size;
    int64_t modified_unix_time;
    uint8_t is_directory;
    uint8_t is_symlink;
    uint8_t is_encrypted;
} awb_mz_entry_info;
int32_t awb_mz_reader_open(const char *path, awb_mz_reader **out_reader);
int32_t awb_mz_reader_first(awb_mz_reader *reader, awb_mz_entry_info *out_info);
int32_t awb_mz_reader_next(awb_mz_reader *reader, awb_mz_entry_info *out_info);
int32_t awb_mz_reader_read_current(awb_mz_reader *reader, uint8_t *buffer, int32_t capacity);
int32_t awb_mz_reader_close_current(awb_mz_reader *reader);
void awb_mz_reader_close(awb_mz_reader **reader);
```

Implement `awb_mz_reader` as a heap-owned struct containing the minizip reader handle and the current `mz_zip_file *`. `open` allocates, calls `mz_zip_reader_create` and `mz_zip_reader_open_file`, and frees everything on failure. `first`/`next` call the matching minizip navigation function and copy only scalar values plus the current filename pointer into `awb_mz_entry_info`. `close` is null-safe and always calls `mz_zip_reader_delete`.

- [ ] **Step 5: Implement actor-isolated listing and error mapping**

`ZIPProviderError.swift` maps `MZ_PASSWORD_ERROR` to `.wrongPassword`, `MZ_FORMAT_ERROR` and `MZ_CRC_ERROR` to `.corruptedArchive`, `MZ_SUPPORT_ERROR` to `.unsupportedMethod`, and all remaining non-zero engine results to `.helperFailed`.

`ZIPArchiveProvider.open(url:)` must:

```swift
public func open(url: URL) throws -> ArchiveDocumentSnapshot {
    closeReader()
    let reader = try BridgeReader(url: url)
    var snapshots: [ArchiveEntrySnapshot] = []
    for info in try reader.allEntries() {
        guard let displayPath = String(bytes: info.nameBytes, encoding: .utf8) else {
            throw ArchiveError.unsupportedFormat
        }
        if !info.isDirectory { try ArchivePathPolicy().validate(displayPath) }
        let entry = ArchiveEntry(rawPath: ArchivePathBytes(info.nameBytes), displayPath: displayPath)
        snapshots.append(.init(
            entry: entry,
            compressedSize: info.compressedSize,
            uncompressedSize: info.uncompressedSize,
            modifiedAt: info.modifiedAt,
            isDirectory: info.isDirectory,
            isEncrypted: info.isEncrypted
        ))
    }
    self.reader = reader
    self.entriesByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.entry.id, $0) })
    return ArchiveDocumentSnapshot(sourceURL: url, format: .zip, entries: snapshots)
}
```

The implementation must use an internal initializer that supplies stable IDs while the document is open; it must not persist raw C pointers in any public Swift value.

- [ ] **Step 6: Prove listing, malformed input, handle cleanup, and repeated open**

Run:

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
swift test --filter ZIPArchiveProviderTests
swift test
```

Expected: provider tests pass, then the complete package test suite passes with no leaked temp fixtures.

- [ ] **Step 7: Commit the real listing provider**

```bash
git add ArchiveWorkbench/Packages/ArchiveKit/Package.swift ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests
git commit -m "feat: list real zip archive entries"
```

### Task 3: Read one entry safely and create a Windows-native ZIP

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/SecureFileMaterializer.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/WindowsZIPProfile.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveSecurityTests/SecureFileMaterializerTests.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests/WindowsZIPCreationTests.swift`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders/ZIPArchiveProvider.swift`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/include/AWBMinizipBridge.h`
- Modify: `ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge/AWBMinizipBridge.c`

**Interfaces:**
- Consumes: the provider's stable entry ID index, `ArchivePathPolicy`, and `ResourceBudget`.
- Produces: `readEntry(id:maximumBytes:)`, `materializeEntry(id:under:budget:)`, and `createWindowsZIP(at:inputs:)`.

- [ ] **Step 1: Write red tests for budget and path publication**

```swift
func testMaterializerRejectsTraversalAndDoesNotCreateOutput() throws {
    let root = try TemporaryDirectory()
    let materializer = SecureFileMaterializer(rootURL: root.url)
    XCTAssertThrowsError(try materializer.write(Data("x".utf8), relativePath: "../escape.txt"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.url.deletingLastPathComponent().appending(path: "escape.txt").path))
}

func testMaterializerRefusesExistingSymlinkLeaf() throws {
    let root = try TemporaryDirectory()
    let outside = root.url.deletingLastPathComponent().appending(path: UUID().uuidString)
    FileManager.default.createFile(atPath: outside.path, contents: Data("keep".utf8))
    try FileManager.default.createSymbolicLink(at: root.url.appending(path: "preview.txt"), withDestinationURL: outside)
    let materializer = SecureFileMaterializer(rootURL: root.url)
    XCTAssertThrowsError(try materializer.write(Data("replace".utf8), relativePath: "preview.txt"))
    XCTAssertEqual(try Data(contentsOf: outside), Data("keep".utf8))
}
```

- [ ] **Step 2: Write red tests for reading and Windows-profile creation**

```swift
func testReadEntryEnforcesByteCeilingBeforeAllocation() async throws {
    let fixture = try ZIPFixture.make(entries: ["large.bin": Data(repeating: 0x41, count: 4097)])
    let provider = ZIPArchiveProvider()
    let snapshot = try await provider.open(url: fixture.archiveURL)
    let id = try XCTUnwrap(snapshot.entries.first?.entry.id)
    await XCTAssertThrowsArchiveError(.resourceLimit) {
        _ = try await provider.readEntry(id: id, maximumBytes: 4096)
    }
}

func testCreateWindowsZIPUsesUTF8AndSuppressesMacMetadata() async throws {
    let source = try InputTree(entries: [
        "资料/报告.txt": Data("跨平台".utf8),
        ".DS_Store": Data("hidden".utf8),
        "资料/._报告.txt": Data("fork".utf8)
    ])
    let output = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".zip")
    let provider = ZIPArchiveProvider()
    try await provider.createWindowsZIP(at: output, inputs: [source.url])
    let reopened = try await provider.open(url: output)
    XCTAssertEqual(reopened.entries.filter { !$0.isDirectory }.map(\.entry.displayPath), ["资料/报告.txt"])
    XCTAssertTrue(try ZIPStructureInspector(url: output).allLocalAndCentralNamesUseUTF8Bit)
}
```

- [ ] **Step 3: Run focused tests and confirm red state**

Run:

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
swift test --filter SecureFileMaterializerTests
swift test --filter WindowsZIPCreationTests
```

Expected: FAIL because secure publication, entry reading, and writer bridge APIs do not exist.

- [ ] **Step 4: Implement descriptor-rooted regular-file publication**

`SecureFileMaterializer.write` validates the relative path, opens the root directory with `O_DIRECTORY | O_CLOEXEC`, creates each directory component with `mkdirat`, reopens each component with `openat(..., O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)`, and creates the leaf with `openat(..., O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600)`. It writes until all bytes are consumed, calls `fsync`, closes every descriptor with `defer`, and unlinks the partial leaf on any write or sync error. It returns the final URL only after success.

- [ ] **Step 5: Implement bounded entry reads**

Before allocating, compare the selected snapshot's `uncompressedSize` with `maximumBytes` and throw `.resourceLimit` when it exceeds the ceiling. Navigate to the stored entry ordinal, reject directories and symlinks, open the current entry, read in 64 KiB chunks, stop if cumulative bytes exceed the ceiling, close the entry on every exit, and require the final byte count to equal the advertised size.

- [ ] **Step 6: Add the bridge writer and Windows profile**

The C writer API must accept an output path and one input at a time, set Deflate compression, never follow or store links, and pass an NFC UTF-8 archive path to `mz_zip_writer_add_file`. The Swift preflight recursively enumerates regular files, rejects symlinks and special files, removes `.DS_Store`, AppleDouble `._*`, and `__MACOSX`, normalizes path components to NFC, rejects Windows device names and trailing spaces/dots, detects case-insensitive/canonical collisions, and sorts output names by UTF-8 bytes for deterministic archives. It writes to a sibling `.<name>.staging-<UUID>` file, closes the writer, calls `fsync` on the staged file and parent directory, and then uses `FileManager.replaceItemAt` only after the source input fingerprint is unchanged.

- [ ] **Step 7: Prove security, round trip, structure, and 7-Zip interoperability**

Run:

```bash
cd ArchiveWorkbench/Packages/ArchiveKit
swift test --filter SecureFileMaterializerTests
swift test --filter ZIPArchiveProviderTests
swift test --filter WindowsZIPCreationTests
swift test
/opt/homebrew/bin/7zz t /tmp/archive-workbench-windows-profile.zip
/opt/homebrew/bin/7zz l -slt /tmp/archive-workbench-windows-profile.zip
```

Expected: all Swift tests pass; `7zz t` reports `Everything is Ok`; the listing contains `资料/报告.txt` and contains none of `.DS_Store`, `._报告.txt`, or `__MACOSX`.

- [ ] **Step 8: Commit safe read and creation**

```bash
git add ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveProviders ArchiveWorkbench/Packages/ArchiveKit/Sources/CMinizipBridge ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveSecurityTests ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveProvidersTests
git commit -m "feat: read and create windows compatible zip archives"
```

### Task 4: Bind a real ZIP document to the native app shell

**Files:**
- Create: `ArchiveWorkbench/App/Sources/ArchiveDocumentLoader.swift`
- Create: `ArchiveWorkbench/AppUnitTests/ArchiveDocumentLoaderTests.swift`
- Modify: `ArchiveWorkbench/App/Sources/AppModel.swift`
- Modify: `ArchiveWorkbench/App/Sources/RootWindowView.swift`
- Modify: `ArchiveWorkbench/App/Sources/ArchiveDocumentView.swift`
- Modify: `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`
- Modify: `ArchiveWorkbench/project.yml`
- Modify: `ArchiveWorkbench/App/Resources/Localizable.xcstrings`
- Modify: `plans/mac_archive_app_requirements_traceability.md`

**Interfaces:**
- Consumes: `ZIPArchiveProvider.open(url:)`, immutable snapshots, and the existing list/media/inspector views.
- Produces: `AppModel.openArchive(url:)`, real loading/error state, provider-backed entries and metadata, and a working native `打开压缩包` command.

- [ ] **Step 1: Write red model tests for real document state**

```swift
@MainActor
func testOpenArchiveReplacesFixtureWithProviderSnapshot() async throws {
    let fixture = try ZIPFixture.make(entries: ["文档/说明.txt": Data("你好".utf8)])
    let model = AppModel(loader: ArchiveDocumentLoader(provider: ZIPArchiveProvider()))
    await model.openArchive(url: fixture.archiveURL)
    XCTAssertTrue(model.hasDocument)
    XCTAssertEqual(model.entries.map(\.displayPath), ["文档/说明.txt"])
    XCTAssertEqual(model.documentTitle, fixture.archiveURL.lastPathComponent)
    XCTAssertNil(model.presentedError)
}

@MainActor
func testOpenMalformedArchiveKeepsWelcomeAndShowsChineseError() async throws {
    let malformed = try MalformedFixture.make()
    let model = AppModel(loader: ArchiveDocumentLoader(provider: ZIPArchiveProvider()))
    await model.openArchive(url: malformed)
    XCTAssertFalse(model.hasDocument)
    XCTAssertEqual(model.presentedError, "无法打开这个压缩包。文件可能已损坏或不是受支持的 ZIP 格式。")
}
```

- [ ] **Step 2: Run the red tests**

Run:

```bash
xcodegen generate --spec ArchiveWorkbench/project.yml
xcodebuild -project ArchiveWorkbench/ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' -only-testing:ArchiveWorkbenchUnitTests/ArchiveDocumentLoaderTests test
```

Expected: FAIL because the loader initializer, title, error, and async open operation do not exist.

- [ ] **Step 3: Implement loader and model transitions**

`ArchiveDocumentLoader` starts security-scoped access only when needed, calls the provider, and stops access in `defer`. `AppModel.openArchive(url:)` sets `isLoading`, clears stale transient state, awaits the snapshot, maps entry sizes and modification dates with localized `ByteCountFormatter`/`DateFormatter`, selects the first regular entry, and on error returns to the welcome state with the reviewed Chinese message. No fixture is loaded on a normal app launch.

- [ ] **Step 4: Wire the native open command and honest capability state**

The welcome screen and File menu use `NSOpenPanel` with `allowsMultipleSelection = false`, `canChooseDirectories = false`, and allowed content types limited to ZIP for this slice. While loading, the content area displays native progress with `正在读取压缩包…`. The toolbar keeps `添加` and `解压缩` disabled until their corresponding complete workflows are wired; `检测完整性` remains inside `操作` and disabled with help text `ZIP 完整性检测将在提供程序验证后启用` rather than appearing as a primary control.

- [ ] **Step 5: Prove app behavior and visual regressions**

Run:

```bash
xcodegen generate --spec ArchiveWorkbench/project.yml
xcodebuild -project ArchiveWorkbench/ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' test
```

Then launch the built app, open the generated UTF-8 fixture, and capture original-resolution screenshots at default width and the 900-point minimum. Expected observations: real filenames and counts replace fixture data; the title is one line with middle truncation; no rounded title badge exists; search, `添加`, `解压缩`, and labeled `操作` do not overlap; no standalone ellipsis or top-level `检测完整性` appears.

- [ ] **Step 6: Update traceability with exact evidence boundaries**

Mark F-001 list/read/create, W-001 open, W-002 browse, X-007 metadata suppression, and S-002/S-006 as “vertical-slice evidence” with the exact test class and screenshot paths. Keep ZIP encryption, split, edit, integrity/repair, preview formats, physical Windows, and production distribution rows open.

- [ ] **Step 7: Commit the app vertical slice**

```bash
git add ArchiveWorkbench/App ArchiveWorkbench/AppUnitTests ArchiveWorkbench/project.yml plans/mac_archive_app_requirements_traceability.md
git commit -m "feat: open real zip archives in native app"
```

### Task 5: Milestone proof, review, and next-provider handoff

**Files:**
- Create: `ArchiveWorkbench/Docs/zip-provider-vertical-slice-acceptance.md`
- Create: `ArchiveWorkbench/context/zip_provider_vertical_slice_context.md`
- Create: `ArchiveWorkbench/reviews/codex_zip_provider_vertical_slice_review.md`
- Create: `ArchiveWorkbench/metrics/zip_provider_vertical_slice_metrics.md`

**Interfaces:**
- Consumes: all Task 1–4 code, tests, screenshots, dependency provenance, and current requirement traceability.
- Produces: an evidence-backed acceptance boundary and the exact entry conditions for the next ZIP edit/encryption/legacy-encoding slice.

- [ ] **Step 1: Run clean proof from generated projects**

```bash
rm -rf /tmp/ArchiveWorkbenchDerivedData
cd ArchiveWorkbench/Packages/ArchiveKit
swift test
cd ../../..
xcodegen generate --spec ArchiveWorkbench/project.yml
xcodebuild -project ArchiveWorkbench/ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/ArchiveWorkbenchDerivedData test
file /tmp/ArchiveWorkbenchDerivedData/Build/Products/Debug/ArchiveWorkbench.app/Contents/MacOS/ArchiveWorkbench
codesign --verify --deep --strict /tmp/ArchiveWorkbenchDerivedData/Build/Products/Debug/ArchiveWorkbench.app
```

Expected: all package and app tests pass; `file` reports arm64; `codesign` verification exits 0.

- [ ] **Step 2: Run dependency and security audits**

Verify the vendored files match the pinned commit except `mz_config.h`, scan production Swift for direct `CMinizipBridge` imports outside `ArchiveProviders`, run malformed/traversal/symlink/budget tests under Address Sanitizer, and inspect bridge allocation/close paths. Any mismatch, direct UI import, sanitizer issue, or source-changing failure blocks acceptance.

- [ ] **Step 3: Run bounded multi-model QC without transferring final authority**

Prepare a fixed allowlist packet. Route Chinese terminology/workflow critique to aishuo MiniMax-M3, attempt GLM-5.2 with the authorized aishuo then buddy fallback, route high-risk bridge/security review to Reasonix `deepseek-pro`, and route screenshot comparison to aishuo Gemini then buddy Kimi only if available. Preserve terminal provider failures, forbid filesystem discovery outside the allowlist, and accept no visual claim that lacks successful image access. Codex independently verifies every accepted finding against source, tests, and original-resolution screenshots.

- [ ] **Step 4: Write the acceptance record**

Record exact commands, exit codes, test counts, hashes, screenshot paths, source commit/license, model route outcomes, applied/rejected findings, and remaining gates. State explicitly that this milestone does not prove ZIP mutation, encryption, split/repair, legacy encodings, Office/media preview, physical Windows interoperability, RAR creation, notarized distribution, or full-product completion.

- [ ] **Step 5: Commit milestone evidence**

```bash
git add ArchiveWorkbench/Docs/zip-provider-vertical-slice-acceptance.md ArchiveWorkbench/context/zip_provider_vertical_slice_context.md ArchiveWorkbench/reviews/codex_zip_provider_vertical_slice_review.md ArchiveWorkbench/metrics/zip_provider_vertical_slice_metrics.md plans/mac_archive_app_requirements_traceability.md
git commit -m "docs: accept real zip provider vertical slice"
```

## Plan Self-Review

- Spec coverage: this plan covers only the first real ZIP slice—pinned engine, UTF-8 list/read, secure single-entry publication, Windows-native create, app binding, and milestone QC. It intentionally leaves mutation, password/encryption, split/integrity/repair, legacy name bytes, rich previews, physical Windows, and other formats to separately reviewable plans.
- Placeholder scan: every implementation instruction is concrete, and every test/build step names its command and expected result.
- Type consistency: `ArchiveDocumentSnapshot`, `ArchiveEntrySnapshot`, `ArchiveProvider`, and `ZIPArchiveProvider` signatures are defined in Task 2 and consumed unchanged in Tasks 3–4; the C bridge stays opaque and is not imported by the app.
- Exit criteria: acceptance requires clean package/app tests, arm64/codesign checks, real fixture screenshots, pinned-source audit, sanitizer/security evidence, and an explicit record of still-open product requirements.
