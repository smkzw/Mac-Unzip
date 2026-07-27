# Signing & Notarization Runbook

> **WARNING: This is a reference document only. DO NOT execute any of these
> steps until the user explicitly authorizes signing and notarization.**
>
> 未经用户明确命令，不实际 notarize、upload、push 或 deploy。

---

## Prerequisites

- [ ] Apple Developer Program membership (active)
- [ ] Developer ID Application certificate installed in Keychain
- [ ] Xcode 26+ with command-line tools
- [ ] `xcrun notarytool` configured with App Store Connect API key or Apple ID
- [ ] ArchiveWorkbench builds successfully in Release configuration
- [ ] All tests pass

---

## Step 1: Verify Certificate

```bash
# List available signing identities
security find-identity -v -p codesigning

# Expected output includes:
#   1) ABCDEF1234... "Developer ID Application: Your Name (TEAM_ID)"
```

Note the identity string for use in subsequent steps.

---

## Step 2: Build Release Archive

```bash
cd /path/to/ArchiveWorkbench

xcodebuild archive \
  -project ArchiveWorkbench.xcodeproj \
  -scheme ArchiveWorkbench \
  -configuration Release \
  -archivePath build/ArchiveWorkbench.xcarchive \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" \
  DEVELOPMENT_TEAM=TEAM_ID \
  ENABLE_HARDENED_RUNTIME=YES
```

---

## Step 3: Verify Hardened Runtime

Hardened runtime is already enabled in `Config/Base.xcconfig`:
```
ENABLE_HARDENED_RUNTIME = YES
```

And in `project.yml`:
```yaml
OTHER_CODE_SIGN_FLAGS: --options=runtime
```

Verify after build:
```bash
codesign -dvvv build/ArchiveWorkbench.xcarchive/Products/Applications/ArchiveWorkbench.app 2>&1 | grep -i "runtime"
# Expected: flags=0x10000(runtime)
```

---

## Step 4: Entitlements

Create `Distribution/ArchiveWorkbench.entitlements` if not present:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened runtime exceptions -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>

    <!-- App Sandbox (if distributing via direct download, sandbox is optional) -->
    <!-- Enable if submitting to App Store later -->
    <!--
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.bookmarks.app-scope</key>
    <true/>
    -->

    <!-- Network (not needed for local archive operations) -->
    <!--
    <key>com.apple.security.network.client</key>
    <true/>
    -->
</dict>
</plist>
```

Apply entitlements during signing:
```bash
codesign --force --options runtime \
  --entitlements Distribution/ArchiveWorkbench.entitlements \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  build/ArchiveWorkbench.xcarchive/Products/Applications/ArchiveWorkbench.app
```

---

## Step 5: Sign Nested Code

Sign all nested frameworks/helpers before signing the main app:

```bash
APP_PATH="build/ArchiveWorkbench.xcarchive/Products/Applications/ArchiveWorkbench.app"

# Sign Quick Look extension
codesign --force --options runtime \
  --entitlements Distribution/ArchiveWorkbench.entitlements \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  "$APP_PATH/PlugIns/ArchiveWorkbenchQLExtension.appex"

# Sign main app (must be last)
codesign --force --options runtime \
  --entitlements Distribution/ArchiveWorkbench.entitlements \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  "$APP_PATH"
```

---

## Step 6: Verify Signature

```bash
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# Expected: valid on disk, satisfies its Designated Requirement

spctl --assess --type execute --verbose "$APP_PATH"
# Expected: accepted, source=Developer ID
```

---

## Step 7: Create DMG (before notarization)

```bash
# See Scripts/package_release.sh for full DMG creation
hdiutil create -volname "ArchiveWorkbench" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  build/ArchiveWorkbench-1.0.0.dmg
```

---

## Step 8: Notarize

```bash
# Submit for notarization (DO NOT RUN without explicit authorization)
xcrun notarytool submit build/ArchiveWorkbench-1.0.0.dmg \
  --keychain-profile "AC_NOTARY_PROFILE" \
  --wait

# Alternative: using App Store Connect API key
xcrun notarytool submit build/ArchiveWorkbench-1.0.0.dmg \
  --key ~/private_keys/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_ID \
  --wait
```

### Setting up notarytool credentials (one-time)

```bash
xcrun notarytool store-credentials "AC_NOTARY_PROFILE" \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password"
```

### Check notarization status

```bash
xcrun notarytool info SUBMISSION_ID \
  --keychain-profile "AC_NOTARY_PROFILE"
```

### View notarization log (if issues)

```bash
xcrun notarytool log SUBMISSION_ID \
  --keychain-profile "AC_NOTARY_PROFILE"
```

---

## Step 9: Staple

After notarization succeeds:

```bash
xcrun stapler staple build/ArchiveWorkbench-1.0.0.dmg

# Verify stapling
xcrun stapler validate build/ArchiveWorkbench-1.0.0.dmg
# Expected: The validate action worked!
```

---

## Step 10: Final Verification

```bash
# Verify the DMG opens and app launches
hdiutil attach build/ArchiveWorkbench-1.0.0.dmg
open /Volumes/ArchiveWorkbench/ArchiveWorkbench.app

# Verify Gatekeeper acceptance
spctl --assess --type open --context context:primary-signature \
  --verbose /Volumes/ArchiveWorkbench/ArchiveWorkbench.app

hdiutil detach /Volumes/ArchiveWorkbench
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "The signature does not include a secure timestamp" | Ensure `--options runtime` is used |
| "The binary is not signed" | Check CODE_SIGN_IDENTITY in build settings |
| Notarization fails: "The signature of the binary is invalid" | Re-sign with hardened runtime |
| Notarization fails: unsigned nested code | Sign all .appex/.framework before main app |
| "The staple and validate action failed" | Wait a few minutes after notarization completes |

---

## References

- [Apple: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Apple: Developer ID](https://developer.apple.com/developer-id/)

---

*Generated: 2026-07-27 | ArchiveWorkbench Distribution Preparation (Phase G)*
*This document is a runbook only. No signing or notarization has been performed.*
