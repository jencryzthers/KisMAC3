#!/usr/bin/env bash
# scripts/make_dmg.sh — package the (signed) KisMac2.app into a distributable
# DMG with the existing DMG Artwork background (S8.x / Milestone 14).
#
# Modern hdiutil replacement for the legacy Kismac.dmg aggregate target (which
# used the removed `hdiutil internet-enable` and a fragile Finder AppleScript).
# Produces a compressed (UDZO) DMG with an /Applications symlink and the
# bundled background image staged under .background/.
#
# Usage:
#   scripts/make_dmg.sh [path-to-.app]
# Defaults to $EXPORT_DIR/$APP_NAME.app, falling back to the unsigned Release
# build product if no exported app exists (so the DMG layout can be tested
# without credentials).
#
# Env (optional): DMG_PATH, APP_NAME, DIST_DIR, VOL_NAME.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

command -v hdiutil >/dev/null 2>&1 || die "hdiutil not found — macOS required."

APP="${1:-}"
if [ -z "${APP}" ]; then
  if [ -d "${EXPORT_DIR}/${APP_NAME}.app" ]; then
    APP="${EXPORT_DIR}/${APP_NAME}.app"
  else
    # Fall back to the local Release build product (unsigned) so the DMG
    # packaging itself can be exercised without a Developer ID cert.
    DERIVED="$(xcodebuild -workspace "${WORKSPACE}" -scheme "${SCHEME}" \
      -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
    APP="${DERIVED}/${APP_NAME}.app"
  fi
fi

[ -d "${APP}" ] || die "App not found: ${APP}. Build/export it first (scripts/sign_export.sh)."

VOL_NAME="${VOL_NAME:-${APP_NAME}}"
BG_SRC="${REPO_ROOT}/DMG Artwork/dmgBackground.tiff"
STAGE="${DIST_DIR}/dmg-stage"

log "Staging DMG contents from ${APP}"
mkdir -p "${DIST_DIR}"
rm -rf "${STAGE}" "${DMG_PATH}"
mkdir -p "${STAGE}"

cp -R "${APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

if [ -f "${BG_SRC}" ]; then
  mkdir -p "${STAGE}/.background"
  cp "${BG_SRC}" "${STAGE}/.background/dmgBackground.tiff"
  log "Included DMG background artwork."
else
  warn "DMG background not found at '${BG_SRC}' — building a plain DMG."
fi

log "Creating compressed DMG -> ${DMG_PATH}"
hdiutil create \
  -volname "${VOL_NAME}" \
  -srcfolder "${STAGE}" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "${DMG_PATH}"

rm -rf "${STAGE}"

# Sign the DMG itself if a Developer ID identity is available (DMGs should be
# signed so Gatekeeper trusts the container; harmless to skip when unsigned).
if [ -n "${CODESIGN_IDENTITY:-}" ] && command -v codesign >/dev/null 2>&1; then
  log "Signing DMG with ${CODESIGN_IDENTITY}"
  codesign --sign "${CODESIGN_IDENTITY}" --timestamp "${DMG_PATH}" || \
    warn "DMG signing failed — continuing with an unsigned DMG."
else
  warn "No CODESIGN_IDENTITY set — DMG left unsigned (fine for layout testing)."
fi

log "DMG ready: ${DMG_PATH}"
