#!/usr/bin/env bash
# =============================================================================
# ArchiveWorkbench - Release Packaging Script
# =============================================================================
#
# Builds, verifies, and packages MacUnzip for distribution.
# Notarization is still manual — see Distribution/SIGNING_RUNBOOK.md.
#
# Usage:
#   ./Scripts/package_release.sh [--skip-sign] [--version X.Y.Z]
#
# Env:
#   MACUNZIP_SIGNING_IDENTITY  Developer ID Application: Name (TEAMID)
#   MACUNZIP_TEAM_ID           Apple Developer Team ID
#
# Default MARKETING_VERSION is read from project.yml.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration (TODO: Replace placeholder values)
# -----------------------------------------------------------------------------

APP_NAME="MacUnzip"
BUNDLE_ID="com.smkzw.MacUnzip"

# Paths — resolve first so version lookup can read project.yml.
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
# Real entitlements live in App/ (not Distribution/).
ENTITLEMENTS="${PROJECT_DIR}/App/MacUnzip.entitlements"

# Prefer MARKETING_VERSION from project.yml (single source of truth).
DEFAULT_VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' "${PROJECT_DIR}/project.yml" 2>/dev/null | head -1)"
VERSION="${DEFAULT_VERSION:-1.1.6}"

# Override via env (CI/secrets) or --version. Do not hardcode secrets in this file.
SIGNING_IDENTITY="${MACUNZIP_SIGNING_IDENTITY:-Developer ID Application: YOUR NAME (TEAM_ID)}"
TEAM_ID="${MACUNZIP_TEAM_ID:-TEAM_ID}"

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

# Always (re)stage pinned 7zz after clean — never rely on a leftover binary alone.
PINNED_7ZZ_SHA256="3bdfeac2b07b2057cbc2fa3d86aef455739f253cd57733eea3d490065081163e"
echo "  Preparing pinned 7zz via Scripts/prepare_7zz.sh..."
"${PROJECT_DIR}/Scripts/prepare_7zz.sh"
STAGED_7ZZ="${PROJECT_DIR}/App/Binaries/7zz"
[[ -x "${STAGED_7ZZ}" ]] || { echo "ERROR: prepare_7zz.sh did not produce App/Binaries/7zz"; exit 1; }
STAGED_SHA="$(shasum -a 256 "${STAGED_7ZZ}" | awk '{print $1}')"
[[ "${STAGED_SHA}" == "${PINNED_7ZZ_SHA256}" ]] || {
  echo "ERROR: staged 7zz hash mismatch after prepare."
  echo "  expected: ${PINNED_7ZZ_SHA256}"
  echo "  actual:   ${STAGED_SHA}"
  exit 1
}
for notice in 7zz-License.txt 7zz-readme.txt 7zz-SOURCE.txt; do
  [[ -f "${PROJECT_DIR}/App/Binaries/${notice}" ]] || {
    echo "ERROR: missing ${notice} next to staged 7zz"
    exit 1
  }
done

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
  codesign --verify --verbose=2 "${APP_PATH}" || true
else
  # Verify hardened runtime (capture first: grep -q in a pipe would SIGPIPE codesign under pipefail)
  CODESIGN_INFO="$(codesign -dvvv "${APP_PATH}" 2>&1)"
  if grep -q "flags=0x10000(runtime)" <<< "${CODESIGN_INFO}"; then
    echo "  Hardened runtime: YES"
  else
    echo "ERROR: Hardened runtime NOT detected on signed Release build."
    exit 1
  fi

  # Verify signature validity
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
  echo "  Signature: VALID"

  # Verify Gatekeeper assessment (fail closed for Developer ID releases)
  if ! spctl --assess --type execute --verbose "${APP_PATH}"; then
    echo "ERROR: Gatekeeper rejected the signed app."
    exit 1
  fi
fi

# Fail if Homebrew absolute paths remain (embed-dylibs regression).
BIN_FOR_CHECK="${APP_PATH}/Contents/MacOS/${APP_NAME}"
if otool -L "${BIN_FOR_CHECK}" | grep -E '/opt/homebrew|/usr/local/opt' >/dev/null; then
  echo "ERROR: Binary still links Homebrew absolute dylib paths."
  otool -L "${BIN_FOR_CHECK}"
  exit 1
fi
echo "  Self-contained dylibs: OK"

# Require pinned bundled 7zz + license notices (7z/RAR/DMG/ISO support).
BUNDLED_7ZZ="${APP_PATH}/Contents/Resources/Binaries/7zz"
if [[ ! -x "${BUNDLED_7ZZ}" ]]; then
  echo "ERROR: Missing bundled 7zz at Contents/Resources/Binaries/7zz."
  echo "  Scripts/prepare_7zz.sh must stage App/Binaries/7zz before packaging."
  exit 1
fi
BUNDLED_SHA="$(shasum -a 256 "${BUNDLED_7ZZ}" | awk '{print $1}')"
if [[ "${BUNDLED_SHA}" != "${PINNED_7ZZ_SHA256}" ]]; then
  echo "ERROR: bundled 7zz SHA-256 mismatch."
  echo "  expected: ${PINNED_7ZZ_SHA256}"
  echo "  actual:   ${BUNDLED_SHA}"
  exit 1
fi
BUNDLED_MODE="$(stat -f '%Lp' "${BUNDLED_7ZZ}")"
if [[ "$((8#${BUNDLED_MODE} & 8#022))" -ne 0 ]]; then
  echo "ERROR: bundled 7zz is group/world writable (${BUNDLED_MODE})"
  exit 1
fi
BUNDLED_BANNER="$("${BUNDLED_7ZZ}" i 2>/dev/null | awk '/7-Zip/{print; exit}')"
echo "  Bundled 7zz banner: ${BUNDLED_BANNER}"
echo "${BUNDLED_BANNER}" | grep -q "26.03" || { echo "ERROR: bundled 7zz version is not 26.03"; exit 1; }
echo "${BUNDLED_BANNER}" | grep -q "arm64" || { echo "ERROR: bundled 7zz is not arm64"; exit 1; }
BUNDLED_ARCH="$(lipo -info "${BUNDLED_7ZZ}" 2>/dev/null || true)"
echo "${BUNDLED_ARCH}" | grep -q "arm64" || { echo "ERROR: lipo missing arm64 for bundled 7zz"; exit 1; }
if echo "${BUNDLED_ARCH}" | grep -q "x86_64"; then
  echo "ERROR: bundled 7zz unexpectedly contains x86_64"
  exit 1
fi
for notice in 7zz-License.txt 7zz-readme.txt 7zz-SOURCE.txt; do
  [[ -f "${APP_PATH}/Contents/Resources/Binaries/${notice}" ]] || {
    echo "ERROR: missing ${notice} in app bundle Resources/Binaries"
    exit 1
  }
done
# Resource executable must remain runnable after packaging (signature-covered path).
"${BUNDLED_7ZZ}" i >/dev/null || { echo "ERROR: bundled 7zz is not executable in-app"; exit 1; }
# Signature must cover the bundled helper when codesign is present.
if [[ "${SKIP_SIGN}" != "true" ]]; then
  codesign --verify --verbose=2 "${BUNDLED_7ZZ}" || {
    echo "ERROR: bundled 7zz is not covered by a valid code signature"
    exit 1
  }
else
  # Ad-hoc archive still seals Resources; deep verify the app payload when possible.
  codesign --verify --deep --verbose=2 "${APP_PATH}" 2>/dev/null || true
fi
echo "  Bundled 7zz: OK (26.03 arm64, pinned hash, notices present)"

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

# Public checksum file must use a relative basename only (never a machine absolute path).
(
  cd "${BUILD_DIR}"
  shasum -a 256 "$(basename "${OUTPUT_DMG}")" > "$(basename "${OUTPUT_DMG}").sha256"
)
echo "  SHA-256: $(cat "${OUTPUT_DMG}.sha256")"
SHA_NAME_FIELD="$(awk '{print $2}' "${OUTPUT_DMG}.sha256")"
[[ "${SHA_NAME_FIELD}" == "$(basename "${OUTPUT_DMG}")" ]] || {
  echo "ERROR: .sha256 filename field must be the public relative DMG name (got: ${SHA_NAME_FIELD})"
  exit 1
}
case "${SHA_NAME_FIELD}" in
  /*|*/*)
    echo "ERROR: .sha256 must not contain absolute or nested paths"
    exit 1
    ;;
esac

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
