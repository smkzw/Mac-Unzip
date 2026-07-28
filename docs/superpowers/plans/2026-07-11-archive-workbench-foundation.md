# Archive Workbench Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a launchable Apple-Silicon-only macOS 26 archive-workbench shell with tested domain contracts, deterministic capability routing, safe resource policies, operation scheduling, native Chinese UI, and an executable helper/password-transport spike.

**Architecture:** A generated Xcode project hosts a SwiftUI/AppKit macOS app and a local Swift package named `ArchiveKit`. `ArchiveKit` is split into small targets for domain, security, operations, and test fixtures; the app depends only on typed use cases. External archive engines are not integrated in this plan—the plan freezes and proves the contracts they must later implement.

**Tech Stack:** Xcode 26.6, macOS 26.0 SDK, Swift 6.3 strict concurrency, SwiftUI, AppKit bridges, Swift Testing, XcodeGen 2.45.4, Security.framework, Foundation `Process`, POSIX fd APIs.

## Global Constraints

- Deployment target is macOS 26.0; build only `arm64`; do not add Intel slices.
- Display name is `归档工作台`; source/product identifier is `ArchiveWorkbench`.
- Local bundle identifier is `com.smkzw.ArchiveWorkbench`; no upload, notarization, website deployment, or remote Git repository.
- UI strings live in String Catalog; Simplified Chinese is complete and primary, with English and Traditional Chinese catalogs added before distribution.
- The app may use standard SwiftUI/AppKit controls that inherit Liquid Glass; custom glass is limited to navigation and contextual controls.
- No shell execution. Provider commands use fixed executable identity, explicit argv, bounded output, and isolated work directories.
- Passwords never use argv, environment, ordinary/temporary files, clipboard, or shell.
- Tests are written before implementation; each task ends with the exact focused test command and a local commit.
- Xcode/App Sandbox/external-helper uncertainty is resolved by the spike in Task 7 before provider integration starts.

---

## File Map

- `ArchiveWorkbench/project.yml`: reproducible XcodeGen project, target graph, schemes, macOS/arm64 settings.
- `ArchiveWorkbench/Config/Base.xcconfig`: shared Swift, deployment, warning, and architecture settings.
- `ArchiveWorkbench/Config/Local.xcconfig`: local signing and bundle identity only.
- `ArchiveWorkbench/App/Sources/ArchiveWorkbenchApp.swift`: app entry and Settings scene.
- `ArchiveWorkbench/App/Sources/AppModel.swift`: main-actor window/document state composition.
- `ArchiveWorkbench/App/Sources/RootWindowView.swift`: welcome/document shell switch.
- `ArchiveWorkbench/App/Sources/ArchiveDocumentView.swift`: one-sidebar/list-or-media/inspector stable shell.
- `ArchiveWorkbench/App/Resources/Localizable.xcstrings`: all visible and accessibility strings.
- `ArchiveWorkbench/Packages/ArchiveKit/Package.swift`: local package manifest.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/*`: value models and typed errors.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/*`: path and resource-budget policy.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveOperations/*`: actor scheduler and operation state.
- `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveFixtures/*`: deterministic mock archives and malicious-path fixtures.
- `ArchiveWorkbench/Packages/ArchiveKit/Tests/*`: Swift Testing suites.
- `ArchiveWorkbench/HelperSpike/*`: password transport and child-process isolation spike.
- `ArchiveWorkbench/AppTests/*`: app-shell and accessibility launch tests.

## Execution Order

Execute **Task 2 before Task 1** because the XcodeGen project in Task 1 resolves the local `ArchiveKit` package path created by Task 2. Then execute Tasks 3–8 numerically. Task 1's Xcode build/UI-test steps require full Xcode 26.6; if macOS is still waiting for local administrator authentication, complete and review Task 2 first, keep Task 1 open, and continue only with package-only Tasks 3–5 until Xcode is available.

---

### Task 1: Reproducible macOS project and first launch

**Files:**
- Create: `ArchiveWorkbench/project.yml`
- Create: `ArchiveWorkbench/Config/Base.xcconfig`
- Create: `ArchiveWorkbench/Config/Local.xcconfig`
- Create: `ArchiveWorkbench/App/Sources/ArchiveWorkbenchApp.swift`
- Create: `ArchiveWorkbench/App/Sources/RootWindowView.swift`
- Create: `ArchiveWorkbench/App/Resources/Localizable.xcstrings`
- Create: `ArchiveWorkbench/AppTests/AppLaunchTests.swift`

**Interfaces:**
- Consumes: XcodeGen 2.45.4, Xcode 26.6, and the local `ArchiveKit` package created by Task 2.
- Produces: scheme `ArchiveWorkbench`, test target `ArchiveWorkbenchAppTests`, local app bundle.

- [ ] **Step 1: Write the launch test**

```swift
import XCTest

final class AppLaunchTests: XCTestCase {
    func testWelcomeWindowHasChinesePrimaryActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["打开压缩包"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["创建归档"].exists)
    }
}
```

- [ ] **Step 2: Create the XcodeGen specification**

```yaml
name: ArchiveWorkbench
options:
  deploymentTarget:
    macOS: "26.0"
configs:
  Debug: debug
  Release: release
configFiles:
  Debug: Config/Local.xcconfig
  Release: Config/Base.xcconfig
packages:
  ArchiveKit:
    path: Packages/ArchiveKit
targets:
  ArchiveWorkbench:
    type: application
    platform: macOS
    sources:
      - App/Sources
    resources:
      - App/Resources
    dependencies:
      - package: ArchiveKit
        product: ArchiveDomain
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.smkzw.ArchiveWorkbench
        PRODUCT_NAME: ArchiveWorkbench
        INFOPLIST_KEY_CFBundleDisplayName: 归档工作台
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_STYLE: Automatic
        ARCHS: arm64
        VALID_ARCHS: arm64
    scheme:
      testTargets:
        - ArchiveWorkbenchAppTests
  ArchiveWorkbenchAppTests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - AppTests
    dependencies:
      - target: ArchiveWorkbench
```

- [ ] **Step 3: Create deterministic build settings**

```xcconfig
MACOSX_DEPLOYMENT_TARGET = 26.0
ARCHS = arm64
ONLY_ACTIVE_ARCH = YES
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
CLANG_WARN_DOCUMENTATION_COMMENTS = YES
ENABLE_HARDENED_RUNTIME = YES
CODE_SIGN_IDENTITY = -
```

`Local.xcconfig` includes `Base.xcconfig` and sets `CODE_SIGN_STYLE = Manual` plus `DEVELOPMENT_TEAM =` for ad-hoc local builds.

- [ ] **Step 4: Implement the minimum native welcome window**

```swift
import SwiftUI

@main
struct ArchiveWorkbenchApp: App {
    var body: some Scene {
        WindowGroup { RootWindowView() }
            .defaultSize(width: 1180, height: 760)
        Settings { Text("设置") }
    }
}

struct RootWindowView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("打开压缩包") { }
                .accessibilityIdentifier("打开压缩包")
            Button("创建归档") { }
                .accessibilityIdentifier("创建归档")
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}
```

- [ ] **Step 5: Generate, build, and prove the test**

Run:

```bash
cd ArchiveWorkbench
xcodegen generate
xcodebuild -project ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' build
xcodebuild -project ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' test
```

Expected: project generation succeeds; build contains only arm64; `AppLaunchTests` passes.

- [ ] **Step 6: Commit**

```bash
git add ArchiveWorkbench
git commit -m "build: bootstrap native archive workbench app"
```

---

### Task 2: Archive domain values and typed errors

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Package.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveFormat.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveEntry.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveError.swift`
- Test: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveDomainTests/ArchiveDomainTests.swift`

**Interfaces:**
- Produces: `ArchiveFormat`, `ArchiveEntry`, `ArchiveEntryID`, `ArchivePathBytes`, `ArchiveError`.

- [ ] **Step 1: Write failing value-semantics tests**

```swift
import Testing
@testable import ArchiveDomain

@Test func rawPathBytesRemainSeparateFromDisplayName() {
    let bytes = ArchivePathBytes([0x83, 0x65, 0x83, 0x58, 0x83, 0x67])
    let entry = ArchiveEntry(id: .init(), rawPath: bytes, displayPath: "テスト")
    #expect(entry.rawPath == bytes)
    #expect(entry.displayPath == "テスト")
}

@Test func userFacingErrorsAreDistinct() {
    #expect(ArchiveError.passwordRequired != .wrongPassword)
    #expect(ArchiveError.wrongPassword != .unsupportedEncryption)
}
```

- [ ] **Step 2: Run and observe the expected failure**

Run: `cd ArchiveWorkbench/Packages/ArchiveKit && swift test --filter ArchiveDomainTests`

Expected: FAIL because `ArchiveDomain` types do not exist.

- [ ] **Step 3: Implement immutable Sendable domain types**

Create the package manifest first:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArchiveKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ArchiveDomain", targets: ["ArchiveDomain"]),
        .library(name: "ArchiveSecurity", targets: ["ArchiveSecurity"]),
        .library(name: "ArchiveOperations", targets: ["ArchiveOperations"]),
        .library(name: "ArchiveFixtures", targets: ["ArchiveFixtures"]),
    ],
    targets: [
        .target(name: "ArchiveDomain"),
        .target(name: "ArchiveSecurity", dependencies: ["ArchiveDomain"]),
        .target(name: "ArchiveOperations", dependencies: ["ArchiveDomain"]),
        .target(name: "ArchiveFixtures", dependencies: ["ArchiveDomain"]),
        .testTarget(name: "ArchiveDomainTests", dependencies: ["ArchiveDomain"]),
        .testTarget(name: "ArchiveSecurityTests", dependencies: ["ArchiveSecurity", "ArchiveFixtures"]),
        .testTarget(name: "ArchiveOperationsTests", dependencies: ["ArchiveOperations"]),
    ]
)
```

Then add the domain types:

```swift
public enum ArchiveFormat: String, Codable, Sendable, CaseIterable {
    case zip, sevenZip, tar, gzip, bzip2, xz, zstandard, rar, dmg, iso
}

public struct ArchiveEntryID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct ArchivePathBytes: Hashable, Codable, Sendable {
    public let bytes: [UInt8]
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
}

public struct ArchiveEntry: Hashable, Codable, Sendable {
    public let id: ArchiveEntryID
    public let rawPath: ArchivePathBytes
    public let displayPath: String
    public init(id: ArchiveEntryID, rawPath: ArchivePathBytes, displayPath: String) {
        self.id = id; self.rawPath = rawPath; self.displayPath = displayPath
    }
}

public enum ArchiveError: String, Error, Codable, Sendable {
    case unsupportedFormat, unsupportedMethod, passwordRequired, wrongPassword
    case unsupportedEncryption, corruptedArchive, missingVolume, unsafePath
    case resourceLimit, sourceChanged, helperFailed
}
```

- [ ] **Step 4: Run all package tests**

Run: `cd ArchiveWorkbench/Packages/ArchiveKit && swift test`

Expected: all `ArchiveDomainTests` pass with zero warnings.

- [ ] **Step 5: Commit**

```bash
git add ArchiveWorkbench/Packages/ArchiveKit
git commit -m "feat: define archive domain contracts"
```

---

### Task 3: Deterministic capability registry

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveCapability.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveDomain/ArchiveCapabilityRegistry.swift`
- Test: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveDomainTests/CapabilityRegistryTests.swift`

**Interfaces:**
- Consumes: `ArchiveFormat`.
- Produces: `ArchiveAction`, `ProviderID`, `ArchiveCapabilitySnapshot`, `ArchiveCapabilityRegistry.snapshot(format:)`.

- [ ] **Step 1: Write table-driven failing tests**

```swift
@Test(arguments: [ArchiveFormat.zip, .sevenZip])
func writableFormatsExposeCreation(_ format: ArchiveFormat) {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: format)
    #expect(snapshot.actions.contains(.create))
    #expect(snapshot.primaryProvider != nil)
}

@Test func dmgIsReadOnly() {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .dmg)
    #expect(snapshot.actions.contains(.browse))
    #expect(!snapshot.actions.contains(.create))
    #expect(!snapshot.actions.contains(.update))
}

@Test func rarCreateRequiresValidatedExternalProvider() {
    let snapshot = ArchiveCapabilityRegistry.productionBaseline.snapshot(format: .rar)
    #expect(!snapshot.actions.contains(.create))
    #expect(snapshot.unavailableReasons[.create] == .externalProviderNotValidated)
}
```

- [ ] **Step 2: Run expected failures**

Run: `swift test --filter CapabilityRegistryTests`

Expected: FAIL because capability types are undefined.

- [ ] **Step 3: Implement the immutable baseline table**

```swift
public enum ArchiveAction: String, Codable, Hashable, Sendable {
    case list, read, preview, create, update, encrypt, split, test, repair
}

public enum ProviderID: String, Codable, Hashable, Sendable {
    case minizipNG, libarchive, sevenZZ, rarLab, diskImage
}

public enum CapabilityUnavailableReason: String, Codable, Hashable, Sendable {
    case formatReadOnly, externalProviderNotValidated, unsupportedByProvider
}

public struct ArchiveCapabilitySnapshot: Equatable, Sendable {
    public let actions: Set<ArchiveAction>
    public let primaryProvider: ProviderID?
    public let unavailableReasons: [ArchiveAction: CapabilityUnavailableReason]
}

public struct ArchiveCapabilityRegistry: Sendable {
    private let snapshots: [ArchiveFormat: ArchiveCapabilitySnapshot]

    public static let productionBaseline = ArchiveCapabilityRegistry(snapshots: [
        .zip: .init(actions: [.list, .read, .preview, .create, .update, .encrypt, .split, .test, .repair], primaryProvider: .minizipNG, unavailableReasons: [:]),
        .sevenZip: .init(actions: [.list, .read, .preview, .create, .update, .encrypt, .split, .test], primaryProvider: .sevenZZ, unavailableReasons: [.repair: .unsupportedByProvider]),
        .tar: .init(actions: [.list, .read, .preview, .create, .test], primaryProvider: .libarchive, unavailableReasons: [.update: .unsupportedByProvider]),
        .gzip: .init(actions: [.read, .create, .test], primaryProvider: .libarchive, unavailableReasons: [.update: .unsupportedByProvider]),
        .bzip2: .init(actions: [.read, .create, .test], primaryProvider: .libarchive, unavailableReasons: [.update: .unsupportedByProvider]),
        .xz: .init(actions: [.read, .create, .test], primaryProvider: .libarchive, unavailableReasons: [.update: .unsupportedByProvider]),
        .zstandard: .init(actions: [.read, .create, .test], primaryProvider: .libarchive, unavailableReasons: [.update: .unsupportedByProvider]),
        .rar: .init(actions: [.list, .read, .preview, .test], primaryProvider: .sevenZZ, unavailableReasons: [.create: .externalProviderNotValidated, .update: .externalProviderNotValidated, .repair: .unsupportedByProvider]),
        .dmg: .init(actions: [.list, .read, .preview], primaryProvider: .diskImage, unavailableReasons: [.create: .formatReadOnly, .update: .formatReadOnly]),
        .iso: .init(actions: [.list, .read, .preview], primaryProvider: .libarchive, unavailableReasons: [.create: .formatReadOnly, .update: .formatReadOnly]),
    ])

    public init(snapshots: [ArchiveFormat: ArchiveCapabilitySnapshot]) { self.snapshots = snapshots }
    public func snapshot(format: ArchiveFormat) -> ArchiveCapabilitySnapshot {
        snapshots[format] ?? .init(actions: [], primaryProvider: nil, unavailableReasons: [:])
    }
    public func withValidatedRARLAB() -> Self {
        var copy = snapshots
        copy[.rar] = .init(actions: [.list, .read, .preview, .create, .update, .test], primaryProvider: .sevenZZ, unavailableReasons: [.repair: .unsupportedByProvider])
        return .init(snapshots: copy)
    }
}
```

- [ ] **Step 4: Prove deterministic routing**

Run: `swift test --filter CapabilityRegistryTests`

Expected: all matrix tests pass and no test depends on environment state.

- [ ] **Step 5: Commit**

```bash
git add ArchiveWorkbench/Packages/ArchiveKit
git commit -m "feat: add deterministic capability registry"
```

---

### Task 4: Path and decompression-budget security policies

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ArchivePathPolicy.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveSecurity/ResourceBudget.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveFixtures/MaliciousPaths.swift`
- Test: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveSecurityTests/ArchivePathPolicyTests.swift`
- Test: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveSecurityTests/ResourceBudgetTests.swift`

**Interfaces:**
- Produces: `ArchivePathPolicy.validate(components:)`, `ResourceBudget.evaluate(_:)`, `BudgetDecision`.

- [ ] **Step 1: Write malicious-path and ratio tests**

```swift
@Test(arguments: ["../escape", "/absolute", "a//b", "a\0b"])
func rejectsStructurallyUnsafePaths(_ path: String) {
    #expect(throws: ArchiveSecurityError.self) {
        try ArchivePathPolicy().validate(path)
    }
}

@Test func previewRatioAboveFiftyIsNeverOverrideable() {
    let input = ResourceEstimate(compressedBytes: 1_000_000, expandedBytes: 60_000_000, entries: 1, depth: 1)
    #expect(ResourceBudget.previewDefault.evaluate(input) == .blockNonOverrideable(.compressionRatio))
}

@Test func extractionRatioAboveOneHundredNeedsExplicitOverride() {
    let input = ResourceEstimate(compressedBytes: 1_000_000, expandedBytes: 101_000_000, entries: 1, depth: 1)
    #expect(ResourceBudget.extractionDefault.evaluate(input) == .blockOverrideable(.compressionRatio))
}
```

- [ ] **Step 2: Run and confirm failures**

Run: `swift test --filter ArchiveSecurityTests`

Expected: FAIL because security policy types are missing.

- [ ] **Step 3: Implement pure policy code**

```swift
public enum ArchiveSecurityError: Error, Equatable, Sendable {
    case absolutePath, parentTraversal, emptyComponent, controlCharacter
}

public struct ArchivePathPolicy: Sendable {
    public init() {}
    public func validate(_ path: String) throws {
        if path.hasPrefix("/") { throw ArchiveSecurityError.absolutePath }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7f }) {
            throw ArchiveSecurityError.controlCharacter
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: { $0.isEmpty }) { throw ArchiveSecurityError.emptyComponent }
        if components.contains(where: { $0 == ".." }) { throw ArchiveSecurityError.parentTraversal }
    }
}

public struct ResourceEstimate: Equatable, Sendable {
    public let compressedBytes: UInt64
    public let expandedBytes: UInt64
    public let entries: UInt64
    public let depth: UInt64
}

public enum BudgetReason: Equatable, Sendable { case itemBytes, totalBytes, entryCount, depth, compressionRatio }
public enum BudgetDecision: Equatable, Sendable {
    case allow
    case blockOverrideable(BudgetReason)
    case blockNonOverrideable(BudgetReason)
}

public struct ResourceBudget: Sendable {
    public let maxExpandedBytes: UInt64
    public let maxEntries: UInt64
    public let maxDepth: UInt64
    public let maxRatio: UInt64
    public let overrideAllowed: Bool

    public static let previewDefault = Self(maxExpandedBytes: 256 << 20, maxEntries: 1, maxDepth: 1, maxRatio: 50, overrideAllowed: false)
    public static let extractionDefault = Self(maxExpandedBytes: 50 << 30, maxEntries: 1_000_000, maxDepth: 128, maxRatio: 100, overrideAllowed: true)

    public func evaluate(_ estimate: ResourceEstimate) -> BudgetDecision {
        let reason: BudgetReason?
        if estimate.expandedBytes > maxExpandedBytes { reason = .totalBytes }
        else if estimate.entries > maxEntries { reason = .entryCount }
        else if estimate.depth > maxDepth { reason = .depth }
        else if estimate.compressedBytes == 0 || estimate.expandedBytes / max(estimate.compressedBytes, 1) > maxRatio { reason = .compressionRatio }
        else { reason = nil }
        guard let reason else { return .allow }
        return overrideAllowed ? .blockOverrideable(reason) : .blockNonOverrideable(reason)
    }
}
```

- [ ] **Step 4: Add Unicode and Windows-name fixtures without changing source names**

```swift
public enum MaliciousPaths {
    public static let multilingual = ["中文/资料.txt", "日本語/資料.txt", "العربية/ملف.txt", "emoji/📦.txt"]
    public static let windowsConflicts = ["CON", "LPT¹", "name. ", "Readme", "README"]
}

@Test func renameProposalNeverMutatesRawBytes() {
    let raw = ArchivePathBytes(Array("CON".utf8))
    let proposal = WindowsNamePolicy().proposal(displayPath: "CON", rawPath: raw)
    #expect(proposal.outputPath == "CON_文件")
    #expect(proposal.sourceRawPath == raw)
}
```

- [ ] **Step 5: Run and commit**

Run: `swift test --filter ArchiveSecurityTests`

Expected: all security-policy tests pass.

```bash
git add ArchiveWorkbench/Packages/ArchiveKit
git commit -m "feat: enforce archive path and resource policies"
```

---

### Task 5: Serializable operation scheduler

**Files:**
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveOperations/ArchiveOperation.swift`
- Create: `ArchiveWorkbench/Packages/ArchiveKit/Sources/ArchiveOperations/OperationScheduler.swift`
- Test: `ArchiveWorkbench/Packages/ArchiveKit/Tests/ArchiveOperationsTests/OperationSchedulerTests.swift`

**Interfaces:**
- Produces: `ArchiveOperation`, `ArchiveOperationState`, actor `OperationScheduler.submit(_:)`, `cancel(_:)`, `moveToFront(_:)`.

- [ ] **Step 1: Write actor scheduling tests**

```swift
@Test func limitsExternalJobsToTwo() async {
    let probe = ConcurrencyProbe()
    let scheduler = OperationScheduler(maxExternalJobs: 2)
    await withTaskGroup(of: Void.self) { group in
        for index in 0..<4 {
            group.addTask { await scheduler.run(.externalRead(id: "job-\(index)"), probe: probe) }
        }
    }
    #expect(await probe.maximumConcurrent == 2)
}

@Test func serializesMutationsForOneArchive() async {
    let probe = ConcurrencyProbe()
    let scheduler = OperationScheduler(maxExternalJobs: 2)
    await scheduler.runPair(.mutation(archiveID: "A"), .mutation(archiveID: "A"), probe: probe)
    #expect(await probe.maximumConcurrentMutations(for: "A") == 1)
}
```

- [ ] **Step 2: Run the expected failures**

Run: `swift test --filter ArchiveOperationsTests`

Expected: FAIL because the actor and fixtures do not exist.

- [ ] **Step 3: Implement FIFO + move-to-front + cancellation**

```swift
public struct ArchiveOperationID: Hashable, Codable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum ArchiveOperationKind: Codable, Sendable {
    case read(archiveID: String)
    case externalRead(archiveID: String)
    case mutation(archiveID: String)
}

public enum ArchiveOperationState: String, Codable, Sendable {
    case queued, waitingForSave, running, canceling, canceled, succeeded, failed
}

public struct ArchiveOperation: Codable, Sendable {
    public let id: ArchiveOperationID
    public let kind: ArchiveOperationKind
    public var state: ArchiveOperationState
}

public actor OperationScheduler {
    private let maxExternalJobs: Int
    private var runningExternal = 0
    private var mutatingArchives: Set<String> = []
    private var queue: [ArchiveOperation] = []

    public init(maxExternalJobs: Int = 2) { self.maxExternalJobs = maxExternalJobs }

    public func submit(_ operation: ArchiveOperation) { queue.append(operation) }
    public func cancel(_ id: ArchiveOperationID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].state = .canceled
    }
    public func moveToFront(_ id: ArchiveOperationID) {
        guard let index = queue.firstIndex(where: { $0.id == id && $0.state == .queued }) else { return }
        queue.insert(queue.remove(at: index), at: 0)
    }
}
```

Extend this actor in the same file with an internal permit loop that increments/decrements `runningExternal` in `defer`, inserts/removes archive IDs in `mutatingArchives`, and resumes queued continuations FIFO. The permit state—not a shell string or closure—is the only serialized operation state.

- [ ] **Step 4: Prove cancellation and persistence redaction**

```swift
@Test func encodedOperationContainsNoPasswordOrPrivatePath() throws {
    let operation = ArchiveOperation(id: .init(), kind: .externalRead(archiveID: "opaque-archive-id"), state: .queued)
    let json = String(decoding: try JSONEncoder().encode(operation), as: UTF8.self)
    #expect(!json.contains("password"))
    #expect(!json.contains("/Users/"))
}
```

Add a controllable `SuspendingProbe` fixture so a running operation can be canceled while suspended; assert state order equals `[.running, .canceling, .canceled]` and its completion handler is invoked exactly once.

- [ ] **Step 5: Run and commit**

Run: `swift test --filter ArchiveOperationsTests`

Expected: all scheduler tests pass under Thread Sanitizer in the Xcode scheme.

```bash
git add ArchiveWorkbench/Packages/ArchiveKit
git commit -m "feat: add bounded archive operation scheduler"
```

---

### Task 6: Native one-sidebar list/media shell

**Files:**
- Create: `ArchiveWorkbench/App/Sources/AppModel.swift`
- Create: `ArchiveWorkbench/App/Sources/ArchiveDocumentView.swift`
- Create: `ArchiveWorkbench/App/Sources/ArchiveSidebarView.swift`
- Create: `ArchiveWorkbench/App/Sources/ArchiveListView.swift`
- Create: `ArchiveWorkbench/App/Sources/MediaPreviewView.swift`
- Create: `ArchiveWorkbench/App/Sources/ArchiveInspectorView.swift`
- Create: `ArchiveWorkbench/App/Sources/DocumentToolbar.swift`
- Modify: `ArchiveWorkbench/App/Sources/RootWindowView.swift`
- Modify: `ArchiveWorkbench/App/Resources/Localizable.xcstrings`
- Test: `ArchiveWorkbench/AppTests/DocumentShellTests.swift`

**Interfaces:**
- Consumes: `ArchiveEntry`, `ArchiveCapabilitySnapshot`.
- Produces: `AppModel`, `ArchiveViewMode.list/media`, stable selection and inspector bindings.

- [ ] **Step 1: Write UI tests for approved structure**

```swift
func testMediaShellHasOneSidebarAndNoRejectedControls() {
    app.launchArguments = ["-ui-testing", "-fixture", "media"]
    app.launch()
    XCTAssertEqual(app.outlines.matching(identifier: "压缩包侧边栏").count, 1)
    XCTAssertTrue(app.images["首页主视觉.png"].exists)
    XCTAssertTrue(app.groups["媒体条带"].exists)
    XCTAssertFalse(app.staticTexts["附近的项目"].exists)
    XCTAssertFalse(app.staticTexts["更多文件…"].exists)
    XCTAssertFalse(app.buttons["创建归档"].exists)
}
```

- [ ] **Step 2: Run and confirm failure against welcome-only app**

Run: `cd ArchiveWorkbench && xcodebuild -project ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' test -only-testing:ArchiveWorkbenchAppTests/DocumentShellTests`

Expected: FAIL because the document shell is absent.

- [ ] **Step 3: Implement the stable SwiftUI shell**

```swift
enum ArchiveViewMode: String, CaseIterable, Sendable { case list, media }

@MainActor
@Observable
final class AppModel {
    var hasDocument = false
    var viewMode: ArchiveViewMode = .list
    var inspectorVisible = true
    var searchText = ""
    var selectedEntryID: ArchiveEntryID?
    var entries: [ArchiveEntry] = []
}

struct ArchiveDocumentView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            ArchiveSidebarView(entries: model.entries, selection: $model.selectedEntryID)
                .accessibilityIdentifier("压缩包侧边栏")
        } detail: {
            Group {
                switch model.viewMode {
                case .list: ArchiveListView(entries: model.entries, selection: $model.selectedEntryID)
                case .media: MediaPreviewView(entries: model.entries, selection: $model.selectedEntryID)
                }
            }
            .inspector(isPresented: $model.inspectorVisible) {
                ArchiveInspectorView(selection: model.selectedEntryID)
                    .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
            }
        }
        .searchable(text: $model.searchText, prompt: "搜索压缩包内容")
        .toolbar { DocumentToolbar(model: model) }
    }
}
```

`MediaPreviewView` contains only the selected safe preview and an unlabeled horizontal strip with accessibility identifier `媒体条带`. Use standard controls so macOS 26 applies Liquid Glass automatically. Do not add a second location sidebar, inline zoom toolbar, inspector `<<`, web pagination, or operation-history tree.

- [ ] **Step 4: Implement mode preservation and media recommendation**

```swift
struct MediaRecommendationPolicy: Sendable {
    func shouldRecommend(totalFiles: Int, safeMediaFiles: Int, userSelectedMode: Bool) -> Bool {
        guard !userSelectedMode, totalFiles > 0, safeMediaFiles >= 4 else { return false }
        return Double(safeMediaFiles) / Double(totalFiles) >= 0.70
    }
}

@Test(arguments: [(10, 7, false, true), (10, 6, false, false), (4, 4, true, false)])
func mediaRecommendationCases(_ value: (Int, Int, Bool, Bool)) {
    #expect(MediaRecommendationPolicy().shouldRecommend(totalFiles: value.0, safeMediaFiles: value.1, userSelectedMode: value.2) == value.3)
}
```

Keep selection, current directory, scroll anchor, search text and pending changes as separate `AppModel` properties; changing `viewMode` mutates none of them.

- [ ] **Step 5: Add Chinese accessibility labels and audit test**

Every symbol button receives a String Catalog label and help text. Add UI assertions for `列表视图`, `媒体预览`, `信息`, `添加`, `解压缩`, `检测完整性`, and `当前操作`; run `performAccessibilityAudit()` and keep zero uncategorized failures.

- [ ] **Step 6: Compare the running app with visual target v3**

Capture 1487 × 1058 light mode and the same window in dark/reduce-transparency/increase-contrast states. Create a side-by-side comparison image with `design/assets/adaptive-finder-media-visual-target-v3.png`; inspect original resolution and fix visible hierarchy, padding, truncation, border and toolbar differences.

- [ ] **Step 7: Run and commit**

Run the full app test scheme; expected: launch, structural and accessibility tests pass.

```bash
git add ArchiveWorkbench
git commit -m "feat: build native archive document shell"
```

---

### Task 7: Helper isolation and password-transport security spike

**Files:**
- Create: `ArchiveWorkbench/HelperSpike/PasswordTransport.swift`
- Create: `ArchiveWorkbench/HelperSpike/HelperLauncher.swift`
- Create: `ArchiveWorkbench/HelperSpike/SpikeCommand.swift`
- Create: `ArchiveWorkbench/HelperSpikeTests/PasswordTransportTests.swift`
- Create: `ArchiveWorkbench/HelperSpikeTests/HelperIsolationTests.swift`
- Modify: `ArchiveWorkbench/project.yml`
- Create: `ArchiveWorkbench/Docs/security-spike-results.md`

**Interfaces:**
- Produces: `HelperLauncher.run(executable:arguments:password:limits:)`, `HelperResult`, evidence for Sandbox/hardened-runtime decision.

- [ ] **Step 1: Write tests proving forbidden channels stay empty**

```swift
@Test func passwordUsesOnlyPrivateInputChannel() async throws {
    var password = SecureBytes(Array("正确马电池订书钉".utf8))
    let result = try await HelperLauncher().run(
        executable: fixtureExecutable,
        arguments: ["--interactive-password"],
        password: &password,
        limits: .testDefault
    )
    #expect(result.argvDump.contains("正确马电池订书钉") == false)
    #expect(result.environmentDump.contains("正确马电池订书钉") == false)
    #expect(result.receivedPasswordSHA256 == expectedPasswordSHA256)
    #expect(password.isZeroed)
}
```

The fixture child prints hashes of argv/environment and reads one line from its private stdin/PTY. Capture its process description during the suspended read and assert the literal password is absent there and in all bounded logs.

- [ ] **Step 2: Implement pipe/PTY transport with close-on-exec discipline**

```swift
struct SecureBytes: ~Copyable {
    private var storage: ContiguousArray<UInt8>
    init(_ bytes: [UInt8]) { storage = ContiguousArray(bytes) }
    borrowing func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try storage.withUnsafeBytes(body)
    }
    mutating func zero() { storage.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
    var isZeroed: Bool { storage.allSatisfy { $0 == 0 } }
    deinit { storage.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
}

struct HelperLimits: Sendable {
    let stdoutBytes: Int
    let stderrBytes: Int
    let timeout: Duration
    static let testDefault = Self(stdoutBytes: 64 * 1024, stderrBytes: 64 * 1024, timeout: .seconds(5))
}
```

Implement `HelperLauncher` with `posix_spawn_file_actions`: create the pipe/PTY with close-on-exec, duplicate only the child endpoint to stdin, close all parent-only fds in the child actions, pass an explicit argv array, and concurrently drain stdout/stderr into capped buffers. The API accepts an already validated executable URL, never a command string.

- [ ] **Step 3: Run a fixed local 7zz interactive-password probe**

Create an encrypted fixture with the pinned 7zz build, then list/test/extract using the interactive prompt switch and private stdin/PTY. Expected: password never appears in `ps`, captured diagnostics or task JSON; extracted SHA-256 matches source. If the fixed build cannot pass, record `encryptedSevenZip = disabled` and do not use `-pPASSWORD`.

The probe record uses this exact shape:

```swift
struct ProviderSpikeResult: Codable, Sendable {
    enum Status: String, Codable, Sendable { case pass, fail, capabilityDisabled }
    let provider: ProviderID
    let version: String
    let status: Status
    let commandArgumentHash: String
    let outputSHA256: String?
    let failureCode: String?
}
```

- [ ] **Step 4: Run App Sandbox/bookmark/helper/DMG matrix**

For sandboxed and hardened-non-sandboxed host configurations, record: user-selected bookmark access, bundled helper execution, external user-selected executable execution, read-only DMG attach/detach, and Quick Look extension boundary. Each row is `pass`, `fail`, or `capability disabled` with command/output evidence; no ambiguous “works”.

- [ ] **Step 5: Run security tests and commit**

Run: `cd ArchiveWorkbench && xcodebuild -project ArchiveWorkbench.xcodeproj -scheme ArchiveWorkbench -destination 'platform=macOS,arch=arm64' test -only-testing:HelperSpikeTests`

Expected: password-channel tests and fd-leak tests pass; environment-dependent failures become explicit capability-disabled records, not test skips.

```bash
git add ArchiveWorkbench/HelperSpike ArchiveWorkbench/HelperSpikeTests ArchiveWorkbench/Docs ArchiveWorkbench/project.yml
git commit -m "test: prove helper and password isolation contracts"
```

---

### Task 8: Foundation proof, QC, and handoff to provider plans

**Files:**
- Create: `ArchiveWorkbench/Docs/foundation-acceptance.md`
- Modify: `plans/mac_archive_app_requirements_traceability.md`

**Interfaces:**
- Consumes: all Task 1–7 artifacts.
- Produces: a closed foundation acceptance packet and frozen provider interfaces.

- [ ] **Step 1: Run the complete proof matrix**

Run package tests, Xcode app/UI tests, Thread Sanitizer scheduler tests, arm64 slice inspection, String Catalog scan, accessibility audit, and security spike. Record exact commands, exit codes and artifact hashes in `foundation-acceptance.md`.

- [ ] **Step 2: Perform skeptical self-review**

Inspect the 5 most likely failures: accidental dual-sidebar UI, unsupported capability shown as enabled, raw path bytes lost during display decoding, scheduler mutation overlap, and password leakage. Link each to a passing test or keep the requirement open.

- [ ] **Step 3: Run required model QC**

Create bounded read-only packets for aishuo/MiniMax-M3 (Chinese/UI/workflow), aishuo/GLM-5.2 (technical contracts), Reasonix `deepseek-pro` (security), and verified image-grounded visual review. Model output is advisory; Codex reruns the real app/tests and owns acceptance.

- [ ] **Step 4: Update traceability without overclaiming**

Mark only foundation requirements with direct evidence. ZIP/7z/libarchive/RAR/Windows full workflows remain pending provider plans until their actual engine and cross-platform tests pass.

- [ ] **Step 5: Commit the acceptance packet**

```bash
git add ArchiveWorkbench/Docs plans/mac_archive_app_requirements_traceability.md runs metrics reviews
git commit -m "docs: accept archive workbench foundation"
```

## Subsequent Independent Plans

After this plan freezes interfaces, execute separate plans for: (1) ZIP/minizip-ng transactional editing; (2) libarchive TAR/filter/ISO and DMG workflows; (3) 7zz 7z/RAR provider plus multipart/password handling; (4) external RARLAB create/update validation; (5) Finder/Quick Look integrations; (6) complete creation/extraction/editor UI; (7) Windows interoperability, performance, malicious fixtures, packaging and local/direct/open-source profiles. Each plan must deliver a working vertical slice and may not mark another plan's requirements complete.
