# Build and distribution profiles

MacUnzip targets macOS 26 or later on Apple silicon (arm64). Use Xcode 26 with Swift 6.2. The build commands below run from `ArchiveWorkbench/`.

## Local development

Install Homebrew build dependencies and open the checked-in project.

```sh
brew install libarchive xz zstd lz4 libb2
open MacUnzip.xcodeproj
```

Select the **MacUnzip** scheme and **My Mac** in Xcode. The project resolves its Swift packages as needed. If you change project sources or settings in [project.yml](../project.yml), use XcodeGen and check the resulting project diff.

```sh
xcodegen generate
git diff -- MacUnzip.xcodeproj/project.pbxproj
```

The ArchiveKit package can be tested separately using `swift test` from [Packages/ArchiveKit](../Packages/ArchiveKit/Package.swift). A Debug build from source can use a detected external `7zz` executable. RAR creation uses a separately installed RARLAB `rar`.

## Direct distribution

The [packaging script](../Scripts/package_release.sh) builds and checks the app, then creates the DMG and checksum. It runs [prepare_7zz.sh](../Scripts/prepare_7zz.sh) to verify the pinned official 7-Zip 26.03 macOS archive and stage the arm64 `7zz` in `App/Binaries/`. The Release app includes the executable and upstream notices, so end users can use 7z without Homebrew. The script takes the default app version from [project.yml](../project.yml).

For a Developer ID release, use the [signing and notarization runbook](SIGNING_RUNBOOK.md). Check the staged app on a clean macOS installation, including engine detection and the embedded dylibs. Publish the DMG and its checksum on [GitHub Releases](https://github.com/smkzw/Mac-Unzip/releases) once the release checks pass.

The DMG staging script copies [the application license](LICENSE.md) and [third-party notices](THIRD_PARTY_NOTICES.md). The repository [SPDX inventory](SBOM.spdx.json) covers the source and build configuration. It pins the upstream 7-Zip archive and the arm64 executable separately. Use the verified release contents to record the resolved dylibs and other artifact-specific metadata. Reconcile the in-app component list with the verified release contents.

## GitHub Actions

The [workflow](../../.github/workflows/build.yml) defines separate ArchiveKit and app jobs. The app job regenerates the Xcode project, checks project-file drift, and uploads a CI ZIP. Check the toolchain logged by each job against the Swift 6.2 requirement. Signing, notarization, and DMG publication are separate release steps.
