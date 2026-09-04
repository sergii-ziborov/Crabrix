#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLCHAIN_TAG="artifacts-test-7"
TOOLCHAIN_ROOT="$PROJECT_ROOT/Crabrix/Resources/Toolchain"
VERSION_DIR="$TOOLCHAIN_ROOT/$TOOLCHAIN_TAG"
MARKER="$VERSION_DIR/.complete"

RUSTC_ARCHIVE="rustc-wasm.tar.zst"
SYSROOT_ARCHIVE="wasip1-sysroot.tar.zst"
RUSTC_SHA="a96f6d53afff3c95d6387def27f6ddb53a02575679dc6c981d60797c32dcd022"
SYSROOT_SHA="4eedff7b0cd4330bfe226734b67751a97fac5572ac55392e93f9d3e4886a277d"
RUSTC_FILE_SHA="41412081eefc3e08ec5664ed0748902a7e575e1f267898dcc64d412702df7e83"
SYSROOT_MANIFEST_SHA="a89ba732c649a983126750112268614c80b6e7d6bba8c60980cbfd32e04d9892"
BASE_URL="https://github.com/AngelOnFira/wasm-rustc/releases/download/$TOOLCHAIN_TAG"

verify_installed_toolchain() {
  local root="$1"
  [[ -f "$root/rustc.wasm" ]] || return 1
  [[ -f "$root/sysroot-wasip1/manifest.json" ]] || return 1
  [[ "$(shasum -a 256 "$root/rustc.wasm" | awk '{print $1}')" == "$RUSTC_FILE_SHA" ]] || return 1
  [[ "$(shasum -a 256 "$root/sysroot-wasip1/manifest.json" | awk '{print $1}')" == "$SYSROOT_MANIFEST_SHA" ]] || return 1
}

if [[ -f "$MARKER" && -f "$VERSION_DIR/rustc.wasm" && -d "$VERSION_DIR/sysroot-wasip1" ]]; then
  if ! verify_installed_toolchain "$VERSION_DIR"; then
    echo "Pinned toolchain files do not match their release hashes: $VERSION_DIR" >&2
    exit 1
  fi
  exit 0
fi

if [[ -n "${CRABRIX_ARTIFACT_CACHE:-}" ]]; then
  CACHE_DIR="$CRABRIX_ARTIFACT_CACHE"
else
  USER_CACHE_ROOT="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  if [[ -z "$USER_CACHE_ROOT" ]]; then
    USER_CACHE_ROOT="/tmp/crabrix-cache-${UID}"
  fi
  CACHE_DIR="${USER_CACHE_ROOT%/}/com.sergiiziborov.Crabrix/$TOOLCHAIN_TAG"
fi

find_zstd() {
  if command -v zstd >/dev/null 2>&1; then
    command -v zstd
  elif [[ -x /opt/homebrew/bin/zstd ]]; then
    echo /opt/homebrew/bin/zstd
  elif [[ -x /usr/local/bin/zstd ]]; then
    echo /usr/local/bin/zstd
  else
    return 1
  fi
}

ZSTD_BIN="$(find_zstd || true)"
if [[ -z "$ZSTD_BIN" ]]; then
  echo "zstd is required to unpack the pinned Rust toolchain: brew install zstd" >&2
  exit 1
fi

mkdir -p "$CACHE_DIR" "$TOOLCHAIN_ROOT"

download_and_verify() {
  local name="$1"
  local expected="$2"
  local target="$CACHE_DIR/$name"
  if [[ ! -f "$target" ]] || [[ "$(shasum -a 256 "$target" | awk '{print $1}')" != "$expected" ]]; then
    echo "Downloading $name ($TOOLCHAIN_TAG)…"
    curl --fail --location --retry 3 --output "$target.partial" "$BASE_URL/$name"
    local actual
    actual="$(shasum -a 256 "$target.partial" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      echo "SHA-256 mismatch for $name" >&2
      exit 1
    fi
    mv "$target.partial" "$target"
  fi
}

download_and_verify "$RUSTC_ARCHIVE" "$RUSTC_SHA"
download_and_verify "$SYSROOT_ARCHIVE" "$SYSROOT_SHA"

STAGING="$(mktemp -d "$TOOLCHAIN_ROOT/.stage.XXXXXX")"
cleanup() {
  if [[ -d "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
}
trap cleanup EXIT

# Decompressed to a file rather than piped into tar. When tar closes the pipe
# first, zstd dies of SIGPIPE and `set -o pipefail` fails the whole bootstrap —
# which is exactly how CI broke, intermittently and only on the fast runners.
extract() {
  local archive="$1"
  shift
  local tarball="$STAGING/.extract.tar"
  "$ZSTD_BIN" -d -f "$CACHE_DIR/$archive" -o "$tarball"
  /usr/bin/tar -xf "$tarball" -C "$STAGING" --strip-components 1 "$@"
  rm -f "$tarball"
}

extract "$RUSTC_ARCHIVE"
extract "$SYSROOT_ARCHIVE" --exclude 'rustc/sysroot-wasip1.bundle'

if [[ ! -f "$STAGING/rustc.wasm" || ! -d "$STAGING/sysroot-wasip1/lib/rustlib/wasm32-wasip1" ]]; then
  echo "Pinned toolchain archive has an unexpected layout" >&2
  exit 1
fi
if ! verify_installed_toolchain "$STAGING"; then
  echo "Extracted toolchain files do not match their pinned hashes" >&2
  exit 1
fi

echo "$TOOLCHAIN_TAG" > "$STAGING/.complete"
if [[ -e "$VERSION_DIR" ]]; then
  echo "Incomplete toolchain directory already exists: $VERSION_DIR" >&2
  echo "Remove that exact directory and rerun this script." >&2
  exit 1
fi
mv "$STAGING" "$VERSION_DIR"

echo "Bundled toolchain staged at $VERSION_DIR"
