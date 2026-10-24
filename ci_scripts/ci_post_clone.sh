#!/bin/bash
set -euo pipefail

# The Xcode project is generated, so a clean Cloud checkout needs the same
# bootstrap and pinned SwiftPM graph used by local release builds.
export HOMEBREW_NO_AUTO_UPDATE=1
for dependency in xcodegen zstd; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    brew install "$dependency"
  fi
done

cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud checkout path is required}"
if [[ "${CI_WORKFLOW:-}" == 'Compiler performance candidate (manual)' ]]; then
  for dependency in python@3.13 llvm@22; do
    if ! brew list --versions "$dependency" >/dev/null 2>&1; then
      brew install --force-bottle "$dependency"
    fi
  done
  /bin/bash ./scripts/build_cloud_compiler_candidate.sh
fi
./scripts/bootstrap.sh
