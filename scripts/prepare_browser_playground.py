#!/usr/bin/env python3
"""Stage pinned compiler assets for the public client-only Playground."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain-directory", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    lock = json.loads((root / "Crabrix/Resources/toolchain.lock.json").read_text())
    compiler = (args.toolchain_directory / "rustc.wasm").read_bytes()
    archive = args.toolchain_directory / "sysroot-wasip1.zip"
    assert sha(compiler) == lock["rustcSHA256"], "Compiler must match the production app pin"
    assert sha(archive.read_bytes()) == lock["sysrootArchiveSHA256"], "Sysroot must match the production app pin"
    compressed = gzip.compress(compiler, compresslevel=6, mtime=0)
    output = root / "site/public/playground-runtime"
    output.mkdir(parents=True, exist_ok=True)
    (output / "rustc.wasm.gz").write_bytes(compressed)
    shutil.copyfile(archive, output / "sysroot.zip")
    manifest = {
        "schemaVersion": 1, "toolchainID": lock["toolchainID"], "rustVersion": lock["rustVersion"], "target": lock["target"],
        "compiler": {"url": "/playground-runtime/rustc.wasm.gz", "sha256": sha(compressed), "bytes": len(compressed),
                     "expandedSHA256": lock["rustcSHA256"], "expandedBytes": len(compiler)},
        "sysroot": {"url": "/playground-runtime/sysroot.zip", "sha256": lock["sysrootArchiveSHA256"], "bytes": archive.stat().st_size},
    }
    (root / "site/lib/playground-toolchain.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"compilerCompressedMiB": round(len(compressed) / 1024**2, 2), "sysrootMiB": round(archive.stat().st_size / 1024**2, 2), "toolchainID": lock["toolchainID"]}))


if __name__ == "__main__":
    main()
