#!/usr/bin/env bash
# =============================================================================
# embed-dylibs.sh — Make MacUnzip self-contained w.r.t. Homebrew libarchive
# =============================================================================
# The app links libarchive (via SwiftPM .systemLibrary pkgConfig), which by
# default hard-codes the absolute Homebrew dylib path. On a Mac without
# `brew install libarchive` the app would fail to launch. This script copies
# libarchive and its Homebrew-only dependencies into the app bundle's
# Contents/Frameworks and rewrites all install names to @rpath so the bundle
# is self-contained. Idempotent: safe to run more than once.
#
# Usage: Scripts/embed-dylibs.sh /path/to/MacUnzip.app
# =============================================================================

set -euo pipefail

APP="${1:?usage: embed-dylibs.sh /path/to/MacUnzip.app}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
EXE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || echo MacUnzip)"
BIN="$APP/Contents/MacOS/$EXE_NAME"
FRAMEWORKS="$APP/Contents/Frameworks"

[[ -f "$BIN" ]] || { echo "error: no Mach-O at $BIN" >&2; exit 1; }

BREW="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"

# base name : Homebrew-relative path (must match the strings in `otool -L`)
libs=(
  "libarchive.13.dylib:opt/libarchive/lib/libarchive.13.dylib"
  "liblzma.5.dylib:opt/xz/lib/liblzma.5.dylib"
  "libzstd.1.dylib:opt/zstd/lib/libzstd.1.dylib"
  "liblz4.1.dylib:opt/lz4/lib/liblz4.1.dylib"
  "libb2.1.dylib:opt/libb2/lib/libb2.1.dylib"
)

mkdir -p "$FRAMEWORKS"

# --- Copy each dylib and set its install id to @rpath/<name> -----------------
for entry in "${libs[@]}"; do
  base="${entry%%:*}"
  rel="${entry#*:}"
  src="$BREW/$rel"
  [[ -e "$src" ]] || { echo "error: missing dependency $src" >&2; exit 1; }
  cp -f "$src" "$FRAMEWORKS/$base"   # cp follows the Homebrew symlink
  chmod u+w "$FRAMEWORKS/$base"
  install_name_tool -id "@rpath/$base" "$FRAMEWORKS/$base"
done

# --- Point libarchive at the embedded copies of its Homebrew deps ------------
LA="$FRAMEWORKS/libarchive.13.dylib"
install_name_tool \
  -change "$BREW/opt/xz/lib/liblzma.5.dylib"    "@rpath/liblzma.5.dylib" \
  -change "$BREW/opt/zstd/lib/libzstd.1.dylib"  "@rpath/libzstd.1.dylib" \
  -change "$BREW/opt/lz4/lib/liblz4.1.dylib"    "@rpath/liblz4.1.dylib" \
  -change "$BREW/opt/libb2/lib/libb2.1.dylib"   "@rpath/libb2.1.dylib" \
  "$LA"

# --- Point the app binary at the embedded libarchive -------------------------
install_name_tool \
  -change "$BREW/opt/libarchive/lib/libarchive.13.dylib" "@rpath/libarchive.13.dylib" \
  "$BIN"

# --- Ensure the app searches @executable_path/../Frameworks ------------------
existing_rpaths="$(otool -l "$BIN" | grep "@executable_path/../Frameworks" || true)"
if [[ -z "$existing_rpaths" ]]; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN"
fi

# --- Re-sign dylibs and app bundle (preserve original identity) ---------------
SIGN_IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)
ENTITLEMENTS="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}/App/MacUnzip.entitlements"

if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != *"adhoc"* ]]; then
  SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --options runtime)
  if [[ -f "$ENTITLEMENTS" ]]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS")
  fi
else
  SIGN_ARGS=(--force --sign -)
fi

for entry in "${libs[@]}"; do
  base="${entry%%:*}"
  if [[ -n "$SIGN_IDENTITY" && "$SIGN_IDENTITY" != *"adhoc"* ]]; then
    if ! codesign --force --sign "$SIGN_IDENTITY" --options runtime "$FRAMEWORKS/$base"; then
      echo "error: failed to sign $base with identity '$SIGN_IDENTITY' (keychain locked or cert expired?); aborting to avoid a mixed-signing bundle" >&2
      exit 1
    fi
  else
    codesign --force --sign - "$FRAMEWORKS/$base"
  fi
done
codesign "${SIGN_ARGS[@]}" "$APP"

echo "Embedded frameworks:"
ls -1 "$FRAMEWORKS"
echo "App libarchive reference now:"
otool -L "$BIN" | grep -i archive || true
