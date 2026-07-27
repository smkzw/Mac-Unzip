# Build Profiles

ArchiveWorkbench supports two distribution profiles:

---

## Profile 1: Direct Distribution (Signed + Notarized)

**Target audience:** End users downloading from smkzw.com or GitHub Releases.

### Characteristics

| Property | Value |
|----------|-------|
| Signing | Developer ID Application certificate |
| Notarization | Apple notarytool (required for Gatekeeper) |
| Hardened Runtime | Enabled |
| Packaging | DMG (UDZO compressed) |
| Architecture | arm64 only |
| Update mechanism | Sparkle or manual (TBD) |

### Build Steps

```bash
# 1. Build Release archive
xcodebuild archive \
  -project ArchiveWorkbench.xcodeproj \
  -scheme ArchiveWorkbench \
  -configuration Release \
  -archivePath build/ArchiveWorkbench.xcarchive \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application: ..." \
  DEVELOPMENT_TEAM=TEAM_ID

# 2. Export .app from archive
# 3. Sign (see SIGNING_RUNBOOK.md)
# 4. Create DMG (see Scripts/package_release.sh)
# 5. Notarize (see SIGNING_RUNBOOK.md)
# 6. Staple (see SIGNING_RUNBOOK.md)
```

### Distribution Channels

- **Website**: Direct DMG download from smkzw.com
- **GitHub Releases**: Attach DMG + SBOM + checksums
- **Homebrew Cask** (future): Formula pointing to GitHub Release URL

### Artifacts

```
ArchiveWorkbench-1.0.0.dmg          # Signed + notarized + stapled
ArchiveWorkbench-1.0.0.dmg.sha256   # Checksum
SBOM.spdx.json                      # Software Bill of Materials
THIRD_PARTY_NOTICES.md              # License attributions
```

---

## Profile 2: OpenSource (Unsigned / Source-Available)

**Target audience:** Developers, contributors, security researchers.

### Characteristics

| Property | Value |
|----------|-------|
| Signing | Ad-hoc (`CODE_SIGN_IDENTITY = -`) or none |
| Notarization | Not applicable |
| Hardened Runtime | Enabled (for local testing) |
| Packaging | Source tarball / git clone |
| Architecture | arm64 (Apple Silicon required) |
| Reproducibility | Pinned toolchain + dependencies |

### Build Steps

```bash
# Clone and build from source
git clone https://github.com/smkzw/ArchiveWorkbench.git
cd ArchiveWorkbench

# Install build dependencies
brew install libarchive

# Generate Xcode project (if using xcodegen)
xcodegen generate

# Build
xcodebuild build \
  -project ArchiveWorkbench.xcodeproj \
  -scheme ArchiveWorkbench \
  -configuration Release \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual

# Or build with SwiftPM (ArchiveKit package only)
cd Packages/ArchiveKit
swift build -c release
```

### Reproducible Build Instructions

To achieve bit-for-bit reproducible builds:

#### 1. Pin Xcode Version

```bash
# Record exact Xcode version
xcodebuild -version
# Expected: Xcode 26.0 (Build 17A...)

# Use xcodes or xcode-select to pin
sudo xcode-select -s /Applications/Xcode-26.0.app
```

#### 2. Pin macOS SDK

```bash
# Verify SDK version
xcrun --show-sdk-version
# Expected: 26.0

xcrun --show-sdk-path
# Expected: /Applications/Xcode-26.0.app/.../MacOSX26.0.sdk
```

#### 3. Pin Dependencies

| Dependency | Version | Pin Method |
|------------|---------|------------|
| minizip-ng | 4.2.1 | Vendored at commit 26b4619 (see ThirdParty/minizip-ng/UPSTREAM.json) |
| libarchive | 3.8.8 | `brew install libarchive` (pin formula version) |
| 7zz | 26.02 | Optional; user-installed |

```bash
# Pin Homebrew libarchive
brew pin libarchive

# Verify version
brew info libarchive | head -1
```

#### 4. Set SOURCE_DATE_EPOCH

Eliminates timestamp-based non-determinism in build outputs:

```bash
# Set to a fixed date (e.g., release date)
export SOURCE_DATE_EPOCH=1785081600  # 2026-07-27T00:00:00Z

# Build with deterministic settings
xcodebuild build \
  -project ArchiveWorkbench.xcodeproj \
  -scheme ArchiveWorkbench \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH \
  SWIFT_COMPILATION_MODE=wholemodule
```

#### 5. Disable Non-Deterministic Features

```bash
# In xcconfig or build settings:
DEBUG_INFORMATION_FORMAT = dwarf        # Avoid dSYM UUID variance
BUILD_LIBRARY_FOR_DISTRIBUTION = NO     # Skip .swiftinterface generation
```

#### 6. Verify Reproducibility

```bash
# Build twice and compare
swift build -c release --scratch-path .build-a
swift build -c release --scratch-path .build-b

# Compare binaries
diff <(shasum -a 256 .build-a/release/ArchiveKit) \
     <(shasum -a 256 .build-b/release/ArchiveKit)
```

### Distribution

- **GitHub**: Source repository with tagged releases
- **Source tarball**: `git archive --format=tar.gz --prefix=ArchiveWorkbench-1.0.0/ v1.0.0`
- **No binary distribution** in this profile (users build locally)

---

## Profile Comparison

| Aspect | Direct | OpenSource |
|--------|--------|------------|
| User effort | Download + open | Clone + build |
| Gatekeeper | Passes (signed + notarized) | Bypass required (right-click > Open) |
| Trust model | Apple Developer ID | Source code audit |
| Update delivery | DMG / Sparkle | git pull + rebuild |
| SBOM included | Yes (in DMG and GitHub) | Yes (in repository) |
| Reproducible | Not required | Required |
| CI/CD | GitHub Actions (macOS runner) | Local or self-hosted |

---

## Environment Requirements (Both Profiles)

- macOS 26.0+ (Apple Silicon / arm64)
- Xcode 26.0+
- Swift 6.2+
- Homebrew (for libarchive)
- xcodegen (if regenerating .xcodeproj from project.yml)

---

*Generated: 2026-07-27 | ArchiveWorkbench Distribution Preparation (Phase G)*
