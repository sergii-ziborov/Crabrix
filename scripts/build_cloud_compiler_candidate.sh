#!/bin/bash
set -euo pipefail

# This opt-in path runs only in a manually started compiler experiment. Normal
# release workflows continue to fetch the signed production toolchain.
[[ "${CI_XCODE_CLOUD:-}" == TRUE && "${CI_WORKFLOW:-}" == 'Compiler performance candidate (manual)' ]] || {
  echo 'Not the manual compiler candidate workflow.' >&2
  exit 2
}
root="${CI_PRIMARY_REPOSITORY_PATH:?}"
work="${CI_WORKSPACE_PATH:?}/crabrix-compiler-performance"
toolchain="$work/toolchain"
[[ ! -e "$work" ]] || { echo 'Candidate workspace already exists; refusing to replace it.' >&2; exit 1; }
mkdir -p "$work"
git init "$toolchain"
git -C "$toolchain" remote add origin https://github.com/sergii-ziborov/crabrix-toolchain.git
revision=17957449aab5e011f976c55cd762244449f1a803
git -C "$toolchain" fetch --depth 1 origin "$revision"
git -C "$toolchain" checkout --detach FETCH_HEAD
[[ "$(git -C "$toolchain" rev-parse HEAD)" == "$revision" ]]
python_prefix="$(brew --prefix python@3.13)"
export PATH="$python_prefix/libexec/bin:$python_prefix/bin:$PATH"
"$python_prefix/bin/python3.13" "$toolchain/scripts/build-macos-compiler-candidate.py" \
  --work "$work/build" --output "$root/CrabrixTests/CompilerCandidate/Artifact" \
  --llvm-config "$(brew --prefix llvm@22)/bin/llvm-config"
