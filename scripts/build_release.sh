#!/usr/bin/env bash
# scripts/build_release.sh — clean Release archive of KisMac2 with hardened
# runtime enabled (S8.x / Milestone 14).
#
# Produces an .xcarchive at $ARCHIVE_PATH. Signing identity / team come from
# the environment (.secrets/appstoreconnect.env or CI). With no credentials
# this runs an UNSIGNED archive only if --unsigned is passed (useful for CI
# smoke); otherwise it preflights and exits with guidance.
#
# Usage:
#   scripts/build_release.sh            # signed archive (needs Developer ID)
#   scripts/build_release.sh --unsigned # unsigned archive (no creds, CI/smoke)
#
# Env (optional): DEVELOPMENT_TEAM, CODESIGN_IDENTITY, CONFIGURATION,
#                 ARCHIVE_PATH, WORKSPACE, SCHEME.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

UNSIGNED=0
[ "${1:-}" = "--unsigned" ] && UNSIGNED=1

load_asc_env

if [ "${UNSIGNED}" -eq 0 ]; then
  if ! preflight_credentials sign; then
    exit 1
  fi
fi

mkdir -p "${DIST_DIR}"
rm -rf "${ARCHIVE_PATH}"

log "Archiving ${SCHEME} (${CONFIGURATION}) -> ${ARCHIVE_PATH}"

# Common args. ENABLE_HARDENED_RUNTIME is the notarization requirement and is
# forced on here regardless of the project default. It is inert for an
# unsigned build (no signature is produced), so it is safe in both modes.
COMMON_ARGS=(
  -workspace "${WORKSPACE}"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -archivePath "${ARCHIVE_PATH}"
  ENABLE_HARDENED_RUNTIME=YES
)

if [ "${UNSIGNED}" -eq 1 ]; then
  warn "Building UNSIGNED archive (smoke only — not distributable)."
  xcodebuild "${COMMON_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    clean archive
else
  log "Building SIGNED archive (team ${DEVELOPMENT_TEAM})."
  xcodebuild "${COMMON_ARGS[@]}" \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}" \
    clean archive
fi

log "Archive complete: ${ARCHIVE_PATH}"
