# MacUnzip engineering guide

See the [project homepage](../README.md) for downloads, format support, and usage. The application is distributed under the [MIT License](../LICENSE).

- Open [MacUnzip.xcodeproj](MacUnzip.xcodeproj) in Xcode 26 with the Swift 6.2 toolchain. Select the **MacUnzip** scheme for the app and its tests.
- The v1.3.0 Release build bundles `7zz` 26.03 (arm64) for 7z without requiring Homebrew. Debug builds can use a detected external `7zz`. RAR creation uses the separately installed RARLAB `rar`.
- [project.yml](project.yml) is the XcodeGen source. The checked-in Xcode project should match it.
- [ArchiveKit](Packages/ArchiveKit/Package.swift) is the local Swift package for archive providers, operations, and security policy.
- [Build profiles](Distribution/BUILD_PROFILES.md) cover local builds and direct distribution. See also the [signing runbook](Distribution/SIGNING_RUNBOOK.md) and [third-party notices](Distribution/THIRD_PARTY_NOTICES.md).
- The [website source](../store/README-zh.md) lives in the repository's `store/` directory.

[简体中文](README_zh.md)
