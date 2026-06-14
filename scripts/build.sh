#!/usr/bin/env bash
# build.sh — quick local (re)compile of KisMac2 into ./build/
#
# Builds the KisMac2 app and drops the product in the repo-local `build/`
# folder (gitignored), with a convenience symlink at `build/KisMac2.app`.
#
# Usage:
#   scripts/build.sh                # incremental Debug build (signing off)
#   scripts/build.sh --clean        # clean Debug build
#   scripts/build.sh --release      # Release build (universal)
#   scripts/build.sh --run          # build, then launch the app
#   scripts/build.sh --clean --release --run
#
# Signing is disabled by default (no Developer ID needed on a dev machine —
# see scripts/release.sh + docs/release.md for the real signed/notarized build).
set -euo pipefail

# --- locate the repo root (this script lives in <root>/scripts) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

WORKSPACE="KisMac2.xcworkspace"
SCHEME="KisMac2"
CONFIG="Debug"
DERIVED="$ROOT/build"
ACTION="build"
RUN=0

for arg in "$@"; do
  case "$arg" in
    --release) CONFIG="Release" ;;
    --clean)   ACTION="clean build" ;;
    --run|--open) RUN=1 ;;
    -h|--help)
      sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "build.sh: unknown option '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

echo "==> Building $SCHEME ($CONFIG) into $DERIVED  [signing disabled]"
# shellcheck disable=SC2086  # ACTION may be two words (clean build)
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  $ACTION

APP="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"
if [[ ! -d "$APP" ]]; then
  echo "build.sh: build reported success but $APP is missing" >&2
  exit 1
fi

# Convenience: stable symlink at build/KisMac2.app -> the built product.
ln -sfn "Build/Products/$CONFIG/$SCHEME.app" "$DERIVED/$SCHEME.app"

echo "==> Built: $APP"
echo "==> Symlink: $DERIVED/$SCHEME.app"

if [[ "$RUN" -eq 1 ]]; then
  echo "==> Launching $SCHEME.app"
  open "$APP"
fi
