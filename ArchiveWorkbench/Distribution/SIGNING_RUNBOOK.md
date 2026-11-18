# Signing & Notarization Runbook

> **WARNING: This is a reference document only. DO NOT execute any of these
> steps until the user explicitly authorizes signing and notarization.**
>
> 未经用户明确命令，不实际 notarize、upload、push 或 deploy。

---

## Prerequisites

- [ ] Apple Developer Program membership (active)
- [ ] Developer ID Application certificate installed in Keychain
- [ ] Xcode 26 with the Swift 6.2 toolchain and command-line tools
- [ ] `xcrun notarytool` configured with App Store Connect API key or Apple ID
- [ ] MacUnzip builds successfully in Release configuration
- [ ] All tests pass
- [ ] Bundled 7zz, embedded dylibs, and release license notices have been verified

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

# Regenerate the Xcode project from project.yml (required if MacUnzip.xcodeproj is absent)
xcodegen generate

xcodebuild archive \
  -project MacUnzip.xcodeproj \
  -scheme MacUnzip \
  -configuration Release \
  -archivePath build/MacUnzip.xcarchive \
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
codesign -dvvv build/MacUnzip.xcarchive/Products/Applications/MacUnzip.app 2>&1 | grep -i "runtime"
# Expected: flags=0x10000(runtime)
```

---

## Step 4: Entitlements

Use the main app's checked-in [entitlements](../App/MacUnzip.entitlements), referenced by its target in [project.yml](../project.yml). Inspect the signed app's entitlements and confirm they match the intended release configuration.

```bash
APP_PATH="build/MacUnzip.xcarchive/Products/Applications/MacUnzip.app"
codesign -d --entitlements - "$APP_PATH"
```

---

## Step 5: Sign Nested Code

If re-signing an archive, sign each embedded dylib, executable, and plug-in before signing the main app. Preserve any entitlement requirements of each target. Confirm that both the Quick Look and Finder extensions are signed, and check the bundled `7zz` and embedded dylibs.

Sign the main app last with its checked-in entitlements and a secure timestamp.

```bash
codesign --force --timestamp --options runtime \
  --entitlements App/MacUnzip.entitlements \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  "$APP_PATH"
```

---

## Step 6: Verify Signature

```bash
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
# Expected: valid on disk, satisfies its Designated Requirement
```

---

## Step 7: Create DMG

Use the staging layout in [the packaging script](../Scripts/package_release.sh), including the MIT license, third-party notices, and Applications link. In the remaining examples, set `DMG` to the versioned release artifact.

```bash
DMG="build/MacUnzip-VERSION.dmg"
```

---

## Step 8: Notarize

```bash
# Submit for notarization (DO NOT RUN without explicit authorization)
xcrun notarytool submit "$DMG" \
  --keychain-profile "AC_NOTARY_PROFILE" \
  --wait

# Alternative: using App Store Connect API key
xcrun notarytool submit "$DMG" \
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
xcrun stapler staple "$DMG"

# Verify stapling
xcrun stapler validate "$DMG"
# Expected: The validate action worked!
```

---

## Step 10: Final Verification

```bash
# Verify and mount the DMG
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
shasum -a 256 "$DMG"

# Use the volume path printed by hdiutil to check the enclosed app.
hdiutil attach "$DMG" -readonly
# Set VOLUME to the mount path reported above.
VOLUME="/Volumes/MacUnzip VERSION"
spctl --assess --type execute --verbose "$VOLUME/MacUnzip.app"
open "$VOLUME/MacUnzip.app"
# Quit the app before detaching.
hdiutil detach "$VOLUME"
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "The signature does not include a secure timestamp" | Use `--timestamp` for Developer ID signing |
| "The binary is not signed" | Check CODE_SIGN_IDENTITY in build settings |
| Notarization fails: "The signature of the binary is invalid" | Re-sign with hardened runtime |
| Notarization fails: unsigned nested code | Sign all .appex/.framework before main app |
| "The staple and validate action failed" | Wait a few minutes after notarization completes |

---

## References

- [Apple: Notarizing macOS Software](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
- [Apple: Developer ID](https://developer.apple.com/developer-id/)
