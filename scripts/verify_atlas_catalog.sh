#!/usr/bin/env bash
set -euo pipefail
ATLAS_SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
ATLAS_PROJECT_ROOT="$(cd "$ATLAS_SCRIPT_DIRECTORY/.." && pwd)"
if [ "$#" -gt 0 ]; then ATLAS_PROJECT_ROOT="$1"; fi
# Xcode's prebuild environment points SDKROOT at iOS. Signature verification is
# a host tool, so select the macOS SDK/target explicitly for both local and Cloud.
ATLAS_HOST_SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
ATLAS_HOST_ARCH="$(/usr/bin/uname -m)"
/usr/bin/xcrun --sdk macosx swift -sdk "$ATLAS_HOST_SDK" \
  -target "$ATLAS_HOST_ARCH-apple-macosx14.0" \
  "$ATLAS_SCRIPT_DIRECTORY/verify_atlas_catalog.swift" "$ATLAS_PROJECT_ROOT"
