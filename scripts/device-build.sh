#!/usr/bin/env bash
# Builds and installs Crabrix on a connected iPhone or iPad.
#
# The signing team is deliberately NOT in project.yml, so nothing personal is
# committed. Provide it in one of these ways, in order of preference:
#
#   1. a .env file in the repo root (git-ignored):  CRABRIX_DEVELOPMENT_TEAM=XXXXXXXXXX
#   2. an exported environment variable:            export CRABRIX_DEVELOPMENT_TEAM=XXXXXXXXXX
#   3. the first argument:                          scripts/device-build.sh XXXXXXXXXX
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a; source .env; set +a
fi

TEAM="${1:-${CRABRIX_DEVELOPMENT_TEAM:-}}"
if [[ -z "$TEAM" ]]; then
  echo "No signing team. Set CRABRIX_DEVELOPMENT_TEAM in .env, export it, or pass it as \$1." >&2
  echo "Find it with: security find-identity -v -p codesigning" >&2
  exit 1
fi

"$SCRIPT_DIR/bootstrap.sh"

DERIVED="${CRABRIX_DERIVED_DATA:-$ROOT/DerivedDataDevice}"
BUNDLE_ID=com.sergiiziborov.Crabrix

echo "==> building for device (team $TEAM)"
xcodebuild -project Crabrix.xcodeproj -scheme Crabrix -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
  -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates "DEVELOPMENT_TEAM=$TEAM" build

APP="$DERIVED/Build/Products/Release-iphoneos/Crabrix.app"
[[ -d "$APP" ]] || { echo "No app product at $APP" >&2; exit 1; }

# Pick the first physical, connected device and read its UUID by shape rather
# than by column position, which shifts with the device name.
# Kept out of the assignment so `set -e` cannot kill the script before the
# explanation below is printed: an empty grep is how "no device" looks.
DEVICE="${CRABRIX_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(xcrun devicectl list devices 2>/dev/null \
    | grep physical | grep -v unavailable \
    | grep -oE '[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}' \
    | head -1 || true)"
fi
if [[ -z "$DEVICE" ]]; then
  echo "No connected device. Plug one in, unlock it, and trust this Mac." >&2
  echo "The signed build is ready at $APP, so re-running this only installs it." >&2
  exit 1
fi

echo "==> installing on $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "==> launching (unlock the device if this fails)"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" || true
