#!/usr/bin/env python3
"""Stage a local-only browser experiment from the app's pinned toolchain.

No compiler rebuild, app resource change, backend compiler, or production publish.
The downloaded WASI shim is pinned and verified before extracting regular files.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import zipfile

SHIM_URL = "https://registry.npmjs.org/@bjorn3/browser_wasi_shim/-/browser_wasi_shim-0.4.2.tgz"
SHIM_SHA512 = "/iHkCVUG3VbcbmEHn5iIUpIrh7a7WPiwZ3sHy4HZKZzBdSadwdddYDZAII2zBvQYV0Lfi8naZngPCN7WPHI/hA=="


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_relative(name):
    path = PurePosixPath(name)
    if path.is_absolute() or not path.parts or any(part in ("..", ".") for part in path.parts):
        raise ValueError(f"Unsafe archive entry: {name}")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain-directory", type=Path, required=True, help="Contains the pinned rustc.wasm and sysroot-wasip1.zip")
    parser.add_argument("--output", type=Path, default=Path("build/browser-rust-feasibility-20261027"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    lock = json.loads((repo / "Crabrix/Resources/toolchain.lock.json").read_text())
    compiler = (args.toolchain_directory / "rustc.wasm").resolve()
    sysroot_zip = args.toolchain_directory / "sysroot-wasip1.zip"
    assert digest(compiler.read_bytes()) == lock["rustcSHA256"], "Compiler does not match the app pin"
    assert digest(sysroot_zip.read_bytes()) == lock["sysrootArchiveSHA256"], "Sysroot does not match the app pin"
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    compiler_link = output / "rustc.wasm"
    if not compiler_link.exists():
        compiler_link.symlink_to(compiler)
    assert compiler_link.resolve() == compiler
    archive = subprocess.check_output(["curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "60", "--max-filesize", "1000000", SHIM_URL])
    assert base64.b64encode(hashlib.sha512(archive).digest()).decode() == SHIM_SHA512, "WASI shim integrity mismatch"
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        for entry in tar.getmembers():
            if entry.isfile() and entry.name.startswith("package/"):
                name = safe_relative(entry.name.removeprefix("package/"))
                path = output / "shim" / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(tar.extractfile(entry).read())
    files = []
    with zipfile.ZipFile(sysroot_zip) as archive:
        for name in archive.namelist():
            if name.endswith("/") or name.endswith("manifest.json"):
                continue
            relative = safe_relative(name.removeprefix("sysroot-wasip1/"))
            data = archive.read(name)
            path = output / "sysroot" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            files.append({"path": str(relative), "url": "/sysroot/" + str(relative), "sha256": digest(data), "bytes": len(data)})
    (output / "assets.json").write_text(json.dumps({"compiler": {"url": "/rustc.wasm", "sha256": lock["rustcSHA256"], "bytes": compiler.stat().st_size}, "sysroot": files}))
    for name in ("index.html", "worker.mjs"):
        shutil.copyfile(Path(__file__).with_name(name), output / name)
    print(f"Staged {len(files)} sysroot files in {output}; WASI shim source and license texts retained under shim/.")
    print(f"Serve: python3 -m http.server 3392 --bind 127.0.0.1 --directory {output}")


if __name__ == "__main__":
    main()
