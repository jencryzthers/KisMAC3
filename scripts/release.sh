#!/usr/bin/env bash
# scripts/release.sh — orchestrate the full KisMac3 release pipeline
# (S8.x / Milestone 14): build -> sign/export -> notarize -> staple -> DMG ->
# notarize+staple DMG.
#
# Runs a credential PREFLIGHT first and EXITS with guidance if the Developer
# ID certificate / App Store Connect API key are not present (so it is safe to
# run on any machine without doing anything destructive). This is the cert-
# dependent half (S8.2); the scaffolding it drives is S8.1.
#
# Usage:
#   scripts/release.sh              # full signed + notarized release
#   scripts/release.sh --preflight  # only check prerequisites, then exit
#
# Env: see scripts/lib.sh and .secrets/appstoreconnect.env.example.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

load_asc_env

log "KisMac3 release pipeline — preflight"
if ! preflight_credentials notarize; then
  # preflight_credentials already printed the remediation steps.
  exit 1
fi

if [ "${1:-}" = "--preflight" ]; then
  log "Preflight only — all prerequisites present. Stopping before build."
  exit 0
fi

log "Step 1/5: build signed Release archive"
"${SCRIPT_DIR}/build_release.sh"

log "Step 2/5: export Developer ID + hardened-runtime app"
"${SCRIPT_DIR}/sign_export.sh"

APP="${EXPORT_DIR}/${APP_NAME}.app"

log "Step 3/5: notarize + staple the app"
"${SCRIPT_DIR}/notarize.sh" "${APP}"

log "Step 4/5: build DMG from the notarized app"
"${SCRIPT_DIR}/make_dmg.sh" "${APP}"

log "Step 5/5: notarize + staple the DMG"
"${SCRIPT_DIR}/notarize.sh" "${DMG_PATH}"

log "Release complete."
log "  App:  ${APP}"
log "  DMG:  ${DMG_PATH}"
log "Both are Developer ID signed, hardened-runtime, notarized and stapled."
