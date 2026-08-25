#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required: brew install xcodegen" >&2
  exit 1
fi

"$SCRIPT_DIR/fetch_toolchain.sh"
xcodegen generate --spec "$PROJECT_ROOT/project.yml" --project "$PROJECT_ROOT"

echo "Generated $PROJECT_ROOT/Crabrix.xcodeproj"
