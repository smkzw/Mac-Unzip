#!/usr/bin/env bash
# =============================================================================
# prepare_7zz.sh — Fetch, verify, and stage the pinned arm64 7zz for MacUnzip.
#
# Source of truth: ip7z official 26.03 macOS release (dynamic-link 7zz, not 7zzs).
# Binary is gitignored; this script makes a clean checkout / CI reproducible.
#
# Usage:
#   ./Scripts/prepare_7zz.sh
# =============================================================================
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${PROJECT_DIR}/App/Binaries"
CACHE_DIR="${PROJECT_DIR}/build/7zz-prepare-cache"
WORKDIR="${CACHE_DIR}/work"

ARCHIVE_NAME="7z2603-mac.tar.xz"
ARCHIVE_URL="https://github.com/ip7z/7zip/releases/download/26.03/${ARCHIVE_NAME}"
# Alternate official mirror (same artifact family); primary is GitHub Releases.
ARCHIVE_URL_ALT="https://www.7-zip.org/a/${ARCHIVE_NAME}"
EXPECTED_ARCHIVE_SHA256="5ca87677072c59f5602e5c49baa27d4694bacd2259b4e507f0094249d4281480"
EXPECTED_7ZZ_SHA256="3bdfeac2b07b2057cbc2fa3d86aef455739f253cd57733eea3d490065081163e"
PINNED_VERSION="26.03"
SOURCE_CODE_URL="https://github.com/ip7z/7zip"
PROJECT_HOME_URL="https://www.7-zip.org/"

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

echo "=== prepare_7zz: pinned ${PINNED_VERSION} arm64 ==="
echo "  Project: ${PROJECT_DIR}"
echo "  Output:  ${OUT_DIR}/7zz"

mkdir -p "${CACHE_DIR}" "${WORKDIR}" "${OUT_DIR}"
rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"

ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE_NAME}"
if [[ -f "${ARCHIVE_PATH}" ]]; then
  ACTUAL_ARCHIVE_SHA="$(sha256_file "${ARCHIVE_PATH}")"
  if [[ "${ACTUAL_ARCHIVE_SHA}" != "${EXPECTED_ARCHIVE_SHA256}" ]]; then
    echo "  Cached archive hash mismatch; re-downloading..."
    rm -f "${ARCHIVE_PATH}"
  else
    echo "  Using cached archive (SHA-256 OK)"
  fi
fi

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "  Downloading ${ARCHIVE_URL}"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "${ARCHIVE_PATH}.partial" "${ARCHIVE_URL}"; then
    echo "  Primary download failed; trying ${ARCHIVE_URL_ALT}"
    curl -fsSL --retry 3 --retry-delay 2 -o "${ARCHIVE_PATH}.partial" "${ARCHIVE_URL_ALT}" \
      || die "failed to download ${ARCHIVE_NAME} from official sources"
  fi
  mv "${ARCHIVE_PATH}.partial" "${ARCHIVE_PATH}"
fi

ACTUAL_ARCHIVE_SHA="$(sha256_file "${ARCHIVE_PATH}")"
if [[ "${ACTUAL_ARCHIVE_SHA}" != "${EXPECTED_ARCHIVE_SHA256}" ]]; then
  die "archive SHA-256 mismatch
  expected: ${EXPECTED_ARCHIVE_SHA256}
  actual:   ${ACTUAL_ARCHIVE_SHA}
  Refusing to continue (do not retarget hashes to the download)."
fi
echo "  Archive SHA-256: ${ACTUAL_ARCHIVE_SHA} (OK)"

tar -xJf "${ARCHIVE_PATH}" -C "${WORKDIR}"
FAT_7ZZ="${WORKDIR}/7zz"
[[ -f "${FAT_7ZZ}" ]] || die "archive missing top-level 7zz"
[[ -f "${WORKDIR}/License.txt" ]] || die "archive missing License.txt"

# Official mac package is universal; ship arm64-only slice (pinned hash is arm64).
ARM_7ZZ="${WORKDIR}/7zz.arm64"
lipo -thin arm64 "${FAT_7ZZ}" -output "${ARM_7ZZ}" \
  || die "failed to extract arm64 slice from universal 7zz"

ACTUAL_7ZZ_SHA="$(sha256_file "${ARM_7ZZ}")"
if [[ "${ACTUAL_7ZZ_SHA}" != "${EXPECTED_7ZZ_SHA256}" ]]; then
  die "arm64 7zz SHA-256 mismatch
  expected: ${EXPECTED_7ZZ_SHA256}
  actual:   ${ACTUAL_7ZZ_SHA}
  Refusing to continue (do not retarget hashes to the download)."
fi
echo "  arm64 7zz SHA-256: ${ACTUAL_7ZZ_SHA} (OK)"

# Stage binary + license notices for App bundle / DMG carriage.
# 0755 => not group/world writable (required by runtime discovery).
install -m 0755 "${ARM_7ZZ}" "${OUT_DIR}/7zz"
chmod 0755 "${OUT_DIR}/7zz"

MODE="$(stat -f '%Lp' "${OUT_DIR}/7zz")"
if [[ "$((8#${MODE} & 8#022))" -ne 0 ]]; then
  die "7zz permissions are group/world writable (${MODE})"
fi

cp "${WORKDIR}/License.txt" "${OUT_DIR}/7zz-License.txt"
cp "${WORKDIR}/readme.txt" "${OUT_DIR}/7zz-readme.txt"
# Compact provenance for App/DMG reviewers (not a license rewrite).
cat > "${OUT_DIR}/7zz-SOURCE.txt" <<EOF
MacUnzip bundled 7zz provenance
================================
Version:          ${PINNED_VERSION} (arm64 slice of official macOS package)
Executable SHA-256: ${EXPECTED_7ZZ_SHA256}
Archive:          ${ARCHIVE_NAME}
Archive SHA-256:  ${EXPECTED_ARCHIVE_SHA256}
Download URL:     ${ARCHIVE_URL}
Project home:     ${PROJECT_HOME_URL}
Source code:      ${SOURCE_CODE_URL}
Binary flavor:    7zz (dynamic system library linking) — NOT 7zzs/static, NOT MIT-relicensed, NOT RARLAB rar
License:          See 7zz-License.txt (GNU LGPL + unRAR restriction for some code)
EOF

# Do not clear quarantine globally; only ensure this staged binary is usable if marked.
if command -v xattr >/dev/null 2>&1; then
  if xattr -p com.apple.quarantine "${OUT_DIR}/7zz" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "${OUT_DIR}/7zz" || die "failed to clear quarantine on staged 7zz only"
  fi
fi

# 7zz i prints a leading blank line; take the first banner line.
BANNER="$("${OUT_DIR}/7zz" i 2>/dev/null | awk '/7-Zip/{print; exit}')"
echo "  Banner: ${BANNER}"
echo "${BANNER}" | grep -q "7-Zip" || die "7zz i did not print a 7-Zip banner"
echo "${BANNER}" | grep -q "${PINNED_VERSION}" || die "7zz i version is not ${PINNED_VERSION}"
echo "${BANNER}" | grep -q "arm64" || die "7zz i architecture is not arm64"

FINAL_SHA="$(sha256_file "${OUT_DIR}/7zz")"
[[ "${FINAL_SHA}" == "${EXPECTED_7ZZ_SHA256}" ]] || die "staged 7zz hash drifted after install"

ARCH_INFO="$(lipo -info "${OUT_DIR}/7zz" 2>/dev/null || true)"
echo "  lipo: ${ARCH_INFO}"
echo "${ARCH_INFO}" | grep -q "arm64" || die "staged binary missing arm64"
if echo "${ARCH_INFO}" | grep -q "x86_64"; then
  die "staged binary unexpectedly contains x86_64 (expected arm64-only)"
fi

echo "=== prepare_7zz complete ==="
echo "  ${OUT_DIR}/7zz"
echo "  notices: 7zz-License.txt 7zz-readme.txt 7zz-SOURCE.txt"
