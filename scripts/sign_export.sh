#!/usr/bin/env bash
# scripts/sign_export.sh — export the .xcarchive as a Developer ID,
# hardened-runtime .app (S8.x / Milestone 14).
#
# Generates an exportOptions plist (method: developer-id) on the fly from the
# environment, then runs `xcodebuild -exportArchive`. The exported app is
# Developer ID signed with the hardened runtime and the project entitlements.
#
# Usage: scripts/sign_export.sh
# Requires: a prior scripts/build_release.sh (SIGNED) producing $ARCHIVE_PATH,
#           and the Developer ID credentials (preflighted).
#
# Env (optional): DEVELOPMENT_TEAM, CONFIGURATION, ARCHIVE_PATH, EXPORT_DIR.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "${SCRIPT_DIR}/lib.sh"

load_asc_env

if ! preflight_credentials sign; then
  exit 1
fi

[ -d "${ARCHIVE_PATH}" ] || die "Archive not found at ${ARCHIVE_PATH}. Run scripts/build_release.sh first."

mkdir -p "${EXPORT_DIR}"
PLIST="${EXPORT_DIR}/exportOptions.plist"

log "Writing exportOptions plist -> ${PLIST}"
cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${DEVELOPMENT_TEAM}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<!-- Hardened runtime is required for notarization. -->
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF

log "Exporting Developer ID app from archive -> ${EXPORT_DIR}"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${PLIST}"

APP="${EXPORT_DIR}/${APP_NAME}.app"
[ -d "${APP}" ] || die "Exported app not found at ${APP}"

log "Verifying signature + hardened runtime on ${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
# Confirm the hardened runtime flag (CodeDirectory runtime flag) is set.
if codesign -dvvv "${APP}" 2>&1 | grep -q "flags=.*runtime"; then
  log "Hardened runtime: ENABLED"
else
  warn "Hardened runtime flag NOT detected on the exported app — notarization will reject it."
fi

log "Export complete: ${APP}"
