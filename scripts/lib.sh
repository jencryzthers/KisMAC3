#!/usr/bin/env bash
# scripts/lib.sh — shared helpers for the KisMac3 release pipeline (S8.x).
#
# Sourced by the other scripts/*.sh. Provides logging, env loading and the
# credential preflight. NOTHING here echoes a secret value: only NAMES and
# presence/absence are ever printed.
#
# shellcheck shell=bash

set -euo pipefail

# --- Paths ----------------------------------------------------------------
# REPO_ROOT is the directory containing this scripts/ folder's parent.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORKSPACE="${WORKSPACE:-${REPO_ROOT}/KisMac2.xcworkspace}"
SCHEME="${SCHEME:-KisMac2}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-KisMac2}"
BUNDLE_ID="${BUNDLE_ID:-com.igrsoft.kismac}"

# Output locations (all gitignored under dist/).
DIST_DIR="${DIST_DIR:-${REPO_ROOT}/dist}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${DIST_DIR}/${APP_NAME}.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-${DIST_DIR}/export}"
DMG_PATH="${DMG_PATH:-${DIST_DIR}/${APP_NAME}.dmg}"

# Secrets.
SECRETS_DIR="${SECRETS_DIR:-${REPO_ROOT}/.secrets}"
ASC_ENV_FILE="${ASC_ENV_FILE:-${SECRETS_DIR}/appstoreconnect.env}"

# --- Logging --------------------------------------------------------------
log()  { printf '\033[1;34m[release]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[release] WARN:\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[release] ERROR:\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# --- Env loading ----------------------------------------------------------
# Load .secrets/appstoreconnect.env if present, WITHOUT printing any value.
# Existing environment variables win (so CI/Keychain can override the file).
load_asc_env() {
  if [ -f "${ASC_ENV_FILE}" ]; then
    log "Loading credentials from ${ASC_ENV_FILE} (values not shown)"
    set -a
    # shellcheck disable=SC1090
    . "${ASC_ENV_FILE}"
    set +a
  else
    log "No ${ASC_ENV_FILE} (relying on environment / Keychain only)"
  fi
}

# Print whether a var is set, never its value.
report_var() {
  local name="$1"
  if [ -n "${!name:-}" ]; then
    printf '  %-22s present\n' "${name}"
  else
    printf '  %-22s MISSING\n' "${name}"
  fi
}

# --- Preflight checks -----------------------------------------------------
# Verify the signing identity and notarization credentials are available.
# Prints exactly what is missing and returns non-zero if anything required
# is absent. Does nothing destructive. Modes: "sign" or "notarize" (notarize
# implies sign).
preflight_credentials() {
  local mode="${1:-notarize}"
  local missing=0

  log "Preflight (${mode}) — checking signing/notarization prerequisites:"

  # Developer ID signing identity must exist in a Keychain.
  if ! command -v security >/dev/null 2>&1; then
    err "  'security' tool not found — not running on macOS?"
    missing=1
  else
    local id_pattern="${CODESIGN_IDENTITY:-Developer ID Application}"
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "${id_pattern}"; then
      printf '  %-22s present (matches "%s")\n' "codesign identity" "${id_pattern}"
    else
      printf '  %-22s MISSING — no codesigning identity matching "%s" in any Keychain\n' \
        "codesign identity" "${id_pattern}"
      missing=1
    fi
  fi

  report_var DEVELOPMENT_TEAM
  [ -z "${DEVELOPMENT_TEAM:-}" ] && missing=1

  if [ "${mode}" = "notarize" ]; then
    report_var ASC_API_KEY_ID
    report_var ASC_API_ISSUER_ID
    report_var ASC_API_KEY_PATH
    [ -z "${ASC_API_KEY_ID:-}" ]    && missing=1
    [ -z "${ASC_API_ISSUER_ID:-}" ] && missing=1
    if [ -z "${ASC_API_KEY_PATH:-}" ]; then
      missing=1
    elif [ ! -f "${ASC_API_KEY_PATH}" ]; then
      printf '  %-22s set, but file not found at the given path\n' "ASC_API_KEY_PATH"
      missing=1
    else
      printf '  %-22s present (.p8 found)\n' "ASC_API_KEY_PATH"
    fi
  fi

  if [ "${missing}" -ne 0 ]; then
    cat >&2 <<EOF

------------------------------------------------------------------------
Cannot run the signed/notarized release: credentials are missing (above).

This machine is NOT provisioned with the Developer ID certificate (team
DMP42GVPJ3, tracked as ENV-1). To run the real release (task slice S8.2):

  1. Install the "Developer ID Application" certificate + private key into
     your login Keychain (export from the team's developer account, or
     create via Xcode > Settings > Accounts > Manage Certificates).
  2. Copy the credentials template and fill it in (gitignored):
       cp .secrets/appstoreconnect.env.example .secrets/appstoreconnect.env
       chmod 600 .secrets/appstoreconnect.env
     Set DEVELOPMENT_TEAM, CODESIGN_IDENTITY, and the ASC_API_* values.
  3. Place the App Store Connect API key at:
       .secrets/private_keys/AuthKey_<KEY_ID>.p8   (chmod 600)
     and point ASC_API_KEY_PATH at it.

Nothing was built or signed. Re-run once the above are in place.
------------------------------------------------------------------------
EOF
    return 1
  fi

  log "Preflight OK — all required credentials present."
  return 0
}
