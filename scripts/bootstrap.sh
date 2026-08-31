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

# XcodeGen intentionally keeps the generated project out of Git. Restore the
# audited SwiftPM graph after generation so clean CI/device builds cannot float
# transitive dependency versions.
RESOLVED_SOURCE="$PROJECT_ROOT/Dependencies/Package.resolved"
RESOLVED_DIRECTORY="$PROJECT_ROOT/Crabrix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
mkdir -p "$RESOLVED_DIRECTORY"
cp "$RESOLVED_SOURCE" "$RESOLVED_DIRECTORY/Package.resolved"

echo "Generated $PROJECT_ROOT/Crabrix.xcodeproj"
