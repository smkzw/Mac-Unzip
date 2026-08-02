#!/usr/bin/env bash
# =============================================================================
# ArchiveWorkbench - Release Packaging Script (TEMPLATE)
# =============================================================================
#
# This script builds, signs, and packages ArchiveWorkbench for distribution.
# It is a TEMPLATE with placeholder values that must be configured before use.
#
# IMPORTANT: This script does NOT execute notarization. Notarization commands
# are documented but commented out. See Distribution/SIGNING_RUNBOOK.md.
#
# Usage:
#   ./Scripts/package_release.sh [--skip-sign] [--version X.Y.Z]
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration (TODO: Replace placeholder values)
# -----------------------------------------------------------------------------

APP_NAME="MacUnzip"
BUNDLE_ID="com.smkzw.MacUnzip"
VERSION="1.0.0"  # Default; override with --version X.Y.Z (parsed below)

# TODO: Replace with actual Developer ID identity
SIGNING_IDENTITY="Developer ID Application: YOUR NAME (TEAM_ID)"
TEAM_ID="TEAM_ID"  # TODO: Replace with actual team ID

# Paths
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
ENTITLEMENTS="${PROJECT_DIR}/Distribution/${APP_NAME}.entitlements"

# Reproducible build timestamp (2026-07-27T00:00:00Z)
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1785081600}"

SKIP_SIGN=false

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-sign)
      SKIP_SIGN=true
      shift
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--skip-sign] [--version X.Y.Z]"
      exit 1
      ;;
  esac
done

# Computed after arg parsing so --version overrides are reflected in the DMG name.
OUTPUT_DMG="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

# -----------------------------------------------------------------------------
# Step 1: Clean & Build Release
# -----------------------------------------------------------------------------

echo "=== Step 1: Building Release archive ==="
echo "  Project: ${PROJECT_DIR}"
echo "  Version: ${VERSION}"
echo "  SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH}"

# Clean previous build (safe: only removes our build directory)
if [[ -d "${BUILD_DIR}" ]]; then
  echo "  Cleaning previous build directory..."
  find "${BUILD_DIR}" -mindepth 1 -delete
fi
mkdir -p "${BUILD_DIR}"

if [[ "${SKIP_SIGN}" == "true" ]]; then
  echo "  Signing: SKIPPED (ad-hoc)"
  xcodebuild archive \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="1" \
    -quiet
else
  echo "  Signing: ${SIGNING_IDENTITY}"
  xcodebuild archive \
    -project "${PROJECT_DIR}/${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${SIGNING_IDENTITY}" \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    ENABLE_HARDENED_RUNTIME=YES \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="1" \
    -quiet
fi

echo "  Build complete: ${APP_PATH}"

# -----------------------------------------------------------------------------
# Step 2: Verify Architecture (arm64)
# -----------------------------------------------------------------------------

echo ""
echo "=== Step 2: Verifying arm64 architecture ==="

BINARY="${APP_PATH}/Contents/MacOS/${APP_NAME}"
ARCHS=$(lipo -info "${BINARY}" 2>/dev/null | sed 's/.*: //')

if [[ "${ARCHS}" != *"arm64"* ]]; then
  echo "ERROR: Binary does not contain arm64 architecture!"
  echo "  Found: ${ARCHS}"
  exit 1
fi

echo "  Architecture: ${ARCHS} (OK)"

# Verify no x86_64 (arm64-only distribution)
if [[ "${ARCHS}" == *"x86_64"* ]]; then
  echo "WARNING: Binary contains x86_64. Expected arm64-only."
  echo "  Consider setting ARCHS=arm64 in build settings."
fi

# -----------------------------------------------------------------------------
# Step 3: Codesign Verification
# -----------------------------------------------------------------------------

echo ""
echo "=== Step 3: Verifying code signature ==="

if [[ "${SKIP_SIGN}" == "true" ]]; then
  echo "  Signing skipped; verifying ad-hoc signature..."
  codesign --verify --verbose=2 "${APP_PATH}" 2>&1 || true
else
  # Verify hardened runtime (capture first: grep -q in a pipe would SIGPIPE codesign under pipefail)
  CODESIGN_INFO="$(codesign -dvvv "${APP_PATH}" 2>&1)"
  if grep -q "flags=0x10000(runtime)" <<< "${CODESIGN_INFO}"; then
    echo "  Hardened runtime: YES"
  else
    echo "  WARNING: Hardened runtime NOT detected!"
  fi

  # Verify signature validity
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
  echo "  Signature: VALID"

  # Verify Gatekeeper assessment
  spctl --assess --type execute --verbose "${APP_PATH}" 2>&1 || true
fi

# -----------------------------------------------------------------------------
# Step 4: Create DMG
# -----------------------------------------------------------------------------

echo ""
echo "=== Step 4: Creating DMG ==="

DMG_STAGING="${BUILD_DIR}/dmg-staging"

# Create staging directory (clean if exists)
if [[ -d "${DMG_STAGING}" ]]; then
  find "${DMG_STAGING}" -mindepth 1 -delete
fi
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"

# Add supporting files to DMG
if [[ -f "${PROJECT_DIR}/Distribution/THIRD_PARTY_NOTICES.md" ]]; then
  cp "${PROJECT_DIR}/Distribution/THIRD_PARTY_NOTICES.md" "${DMG_STAGING}/"
fi
if [[ -f "${PROJECT_DIR}/Distribution/LICENSE.md" ]]; then
  cp "${PROJECT_DIR}/Distribution/LICENSE.md" "${DMG_STAGING}/"
fi

# Create symlink to /Applications for drag-install UX
ln -s /Applications "${DMG_STAGING}/Applications"

# Create DMG
hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "${DMG_STAGING}" \
  -ov \
  -format UDZO \
  "${OUTPUT_DMG}"

# Cleanup staging
find "${DMG_STAGING}" -mindepth 1 -delete
rmdir "${DMG_STAGING}"

echo "  DMG created: ${OUTPUT_DMG}"
echo "  Size: $(du -h "${OUTPUT_DMG}" | cut -f1)"

# -----------------------------------------------------------------------------
# Step 5: Generate Checksums
# -----------------------------------------------------------------------------

echo ""
echo "=== Step 5: Generating checksums ==="

shasum -a 256 "${OUTPUT_DMG}" > "${OUTPUT_DMG}.sha256"
echo "  SHA-256: $(cat "${OUTPUT_DMG}.sha256")"

# -----------------------------------------------------------------------------
# Step 6: Notarization (NOT EXECUTED - DOCUMENTED ONLY)
# -----------------------------------------------------------------------------

echo ""
echo "=== Step 6: Notarization ==="
echo "  STATUS: NOT EXECUTED (template mode)"
echo ""
echo "  To notarize, run the following commands manually:"
echo ""
echo "  # Submit for notarization:"
echo "  xcrun notarytool submit ${OUTPUT_DMG} \\"
echo "    --keychain-profile \"AC_NOTARY_PROFILE\" \\"
echo "    --wait"
echo ""
echo "  # After notarization succeeds, staple:"
echo "  xcrun stapler staple ${OUTPUT_DMG}"
echo ""
echo "  # Verify:"
echo "  xcrun stapler validate ${OUTPUT_DMG}"
echo ""
echo "  See Distribution/SIGNING_RUNBOOK.md for full instructions."

# TODO: Uncomment below ONLY when user explicitly authorizes notarization
# -----------------------------------------------------------------------
# xcrun notarytool submit "${OUTPUT_DMG}" \
#   --keychain-profile "AC_NOTARY_PROFILE" \
#   --wait
#
# xcrun stapler staple "${OUTPUT_DMG}"
# xcrun stapler validate "${OUTPUT_DMG}"
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "=== Packaging Complete ==="
echo ""
echo "  App:     ${APP_PATH}"
echo "  DMG:     ${OUTPUT_DMG}"
echo "  SHA-256: ${OUTPUT_DMG}.sha256"
echo "  Version: ${VERSION}"
echo "  Arch:    ${ARCHS}"
echo ""
echo "  Next steps:"
echo "    1. Review and notarize (see SIGNING_RUNBOOK.md)"
echo "    2. Upload to distribution channel"
echo "    3. Update SBOM checksums in Distribution/SBOM.spdx.json"
echo ""
