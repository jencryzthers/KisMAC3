#!/usr/bin/env bash
# scripts/notarize.sh — submit the signed app/DMG to Apple notarization and
# staple the ticket (S8.x / Milestone 14).
#
# Uses `xcrun notarytool submit --wait` with an App Store Connect API key
# loaded from .secrets/appstoreconnect.env. Credential VALUES are never
# echoed. After a successful submission the notarization ticket is stapled
# with `xcrun stapler staple`.
#
# Usage:
#   scripts/notarize.sh [path-to-.app-or-.dmg]
# Defaults to the exported app ($EXPORT_DIR/$APP_NAME.app) if no path given.
#
# Env (required for the real run): ASC_API_KEY_ID, ASC_API_ISSUER_ID,
#   ASC_API_KEY_PATH. (See .secrets/appstoreconnect.env.example.)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

load_asc_env

if ! preflight_credentials notarize; then
  exit 1
fi

TARGET="${1:-${EXPORT_DIR}/${APP_NAME}.app}"
[ -e "${TARGET}" ] || die "Notarization target not found: ${TARGET}"

command -v xcrun >/dev/null 2>&1 || die "xcrun not found — Xcode command line tools required."

# notarytool needs a single file. For a .app, zip it first; a .dmg submits
# directly and is also what gets stapled.
SUBMIT_PATH="${TARGET}"
CLEANUP_ZIP=""
case "${TARGET}" in
  *.app)
    SUBMIT_PATH="${DIST_DIR}/$(basename "${TARGET}").zip"
    log "Zipping app for submission -> ${SUBMIT_PATH}"
    /usr/bin/ditto -c -k --keepParent "${TARGET}" "${SUBMIT_PATH}"
    CLEANUP_ZIP="${SUBMIT_PATH}"
    ;;
esac

log "Submitting to notarytool (this can take several minutes)..."
# Key values are passed by reference; nothing is printed.
xcrun notarytool submit "${SUBMIT_PATH}" \
  --key "${ASC_API_KEY_PATH}" \
  --key-id "${ASC_API_KEY_ID}" \
  --issuer "${ASC_API_ISSUER_ID}" \
  --wait

log "Notarization accepted. Stapling ticket to ${TARGET}"
# Staple the original artifact (the .app or the .dmg), not the zip.
xcrun stapler staple "${TARGET}"
xcrun stapler validate "${TARGET}"

[ -n "${CLEANUP_ZIP}" ] && rm -f "${CLEANUP_ZIP}"

log "Notarization + stapling complete for ${TARGET}"
