#!/bin/bash
set -euo pipefail

# The Xcode project is generated, so a clean Cloud checkout needs the same
# bootstrap and pinned SwiftPM graph used by local release builds.
export HOMEBREW_NO_AUTO_UPDATE=1
install_build_dependency() {
  # Independent Cloud actions start on clean hosts. A transient bottle download
  # failure must not invalidate an otherwise reproducible source build.
  local dependency="$1"
  local attempt
  for attempt in 1 2 3; do
    if brew install --force-bottle "$dependency"; then
      return 0
    fi
    if [[ "$attempt" -lt 3 ]]; then
      echo "Retrying build dependency $dependency (attempt $((attempt + 1))/3)" >&2
      sleep "$((attempt * 2))"
    fi
  done
  return 1
}
for dependency in xcodegen zstd; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    install_build_dependency "$dependency"
  fi
done

cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud checkout path is required}"
if [[ "${CI_WORKFLOW:-}" == 'Compiler performance candidate (manual)' ]]; then
  for dependency in python@3.13 llvm@22; do
    if ! brew list --versions "$dependency" >/dev/null 2>&1; then
      install_build_dependency "$dependency"
    fi
  done
  /bin/bash ./scripts/build_cloud_compiler_candidate.sh
fi
./scripts/bootstrap.sh
