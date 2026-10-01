#!/usr/bin/env python3
"""Validate the app's single toolchain release input before fetching or packing."""

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "Crabrix/Resources/toolchain.lock.json"
HEX = re.compile(r"[0-9a-f]{64}\Z")
COMPONENT = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\Z")


def load_manifest():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1 or data.get("target") != "wasm32-wasip1":
        raise ValueError("unsupported app toolchain manifest schema or target")
    if not isinstance(data.get("toolchainID"), str) or not COMPONENT.fullmatch(data["toolchainID"]):
        raise ValueError("invalid toolchain ID")
    if not isinstance(data.get("rustVersion"), str) or not re.fullmatch(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?", data["rustVersion"]):
        raise ValueError("invalid Rust version")
    version = data.get("rustVersionComponents")
    if not isinstance(version, dict) or not all(
        isinstance(version.get(key), int) and not isinstance(version[key], bool) and version[key] >= 0
        for key in ("major", "minor", "patch")
    ):
        raise ValueError("invalid Rust version components")
    version_base = f'{version["major"]}.{version["minor"]}.{version["patch"]}'
    if data["rustVersion"] != version_base and not data["rustVersion"].startswith(version_base + "-"):
        raise ValueError("Rust version and components disagree")
    for key in ("rustcSHA256", "sysrootManifestSHA256", "sysrootArchiveSHA256"):
        if not isinstance(data.get(key), str) or not HEX.fullmatch(data[key]):
            raise ValueError(f"invalid {key}")
    source = data.get("source")
    if not isinstance(source, dict) or source.get("kind") != "legacy-tar-zstd":
        raise ValueError("this bootstrap only supports the pinned legacy baseline")
    legacy_release = "https://github.com/AngelOnFira/wasm-rustc/releases/download/artifacts-test-7"
    if source.get("baseURL") != legacy_release:
        raise ValueError("invalid legacy release URL")
    for key in ("compilerAsset", "sysrootAsset"):
        asset = source.get(key)
        if not isinstance(asset, dict) or not isinstance(asset.get("name"), str) or not COMPONENT.fullmatch(asset["name"]):
            raise ValueError(f"invalid {key} name")
        if not asset["name"].endswith(".tar.zst") or not isinstance(asset.get("sha256"), str) or not HEX.fullmatch(asset["sha256"]):
            raise ValueError(f"invalid {key} digest or format")
    return data


def main():
    data = load_manifest()
    if len(sys.argv) == 2 and sys.argv[1] == "validate":
        print(f'Validated {data["toolchainID"]} release input')
    elif len(sys.argv) == 2 and sys.argv[1] == "legacy-tsv":
        source = data["source"]
        print("\t".join((
            data["toolchainID"], source["baseURL"],
            source["compilerAsset"]["name"], source["compilerAsset"]["sha256"],
            source["sysrootAsset"]["name"], source["sysrootAsset"]["sha256"],
            data["rustcSHA256"], data["sysrootManifestSHA256"],
        )))
    else:
        raise SystemExit("usage: toolchain_manifest.py validate|legacy-tsv")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise SystemExit(f"invalid app toolchain manifest: {error}") from error
