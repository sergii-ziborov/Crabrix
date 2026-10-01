#!/usr/bin/env python3
"""Stage a verified *candidate* compiler in an unsigned Simulator test app.

This only mutates the built .app under DerivedData after build-for-testing. It
never changes the tracked release manifest or creates a production artifact.
Run test-without-building after staging so Xcode does not fetch the old release.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import sys
import tempfile
import zipfile


SHA256 = re.compile(r"[0-9a-f]{64}\Z")
MAX_SYSROOT_FILES = 4096
MAX_SYSROOT_UNCOMPRESSED_BYTES = 2 * 1024 * 1024 * 1024


def sha256(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def verify_candidate(directory):
    marker = directory / "CANDIDATE-NOT-FOR-RELEASE.txt"
    if not marker.is_file():
        raise ValueError("only marked candidate artifacts may enter this test path")
    provenance = json.loads((directory / "toolchain-provenance.json").read_text())
    if provenance.get("candidate") is not True:
        raise ValueError("candidate provenance is missing")
    checksums = (directory / "SHA256SUMS").read_text().splitlines()
    checked = set()
    for line in checksums:
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if not match:
            raise ValueError("malformed candidate SHA256SUMS")
        digest, name = match.groups()
        if name in checked or sha256(directory / name) != digest:
            raise ValueError(f"candidate artifact digest mismatch: {name}")
        checked.add(name)
    required = {"rustc.wasm", "sysroot-wasip1.zip", "sysroot-files.json",
                "sysroot-wasip1.sha256", "toolchain-provenance.json", marker.name}
    if not required.issubset(checked):
        raise ValueError("candidate checksum list is incomplete")
    rustc = directory / "rustc.wasm"
    with rustc.open("rb") as stream:
        magic = stream.read(8)
    if magic != b"\0asm\1\0\0\0":
        raise ValueError("candidate rustc has no Wasm header")
    archive = directory / "sysroot-wasip1.zip"
    archive_digest = sha256(archive)
    if (directory / "sysroot-wasip1.sha256").read_text().strip() != archive_digest:
        raise ValueError("candidate sysroot checksum file disagrees")
    inventory = json.loads((directory / "sysroot-files.json").read_text())
    if inventory.get("schemaVersion") != 1 or not isinstance(inventory.get("files"), list):
        raise ValueError("candidate sysroot inventory is malformed")
    expected = {}
    total_bytes = 0
    for item in inventory["files"]:
        if not isinstance(item, dict):
            raise ValueError("candidate sysroot inventory entry is malformed")
        name, size, digest = item.get("path"), item.get("bytes"), item.get("sha256")
        if not isinstance(name, str) or not name.startswith("sysroot-wasip1/") \
                or "\\" in name or "\0" in name or PurePosixPath(name).is_absolute() \
                or any(part in ("", ".", "..") for part in name.split("/")) \
                or name in expected or not isinstance(size, int) or size < 0 \
                or not isinstance(digest, str) or not SHA256.fullmatch(digest):
            raise ValueError(f"invalid or duplicate candidate sysroot entry: {name}")
        expected[name] = (size, digest)
        total_bytes += size
        if len(expected) > MAX_SYSROOT_FILES or total_bytes > MAX_SYSROOT_UNCOMPRESSED_BYTES:
            raise ValueError("candidate sysroot exceeds staging verification bounds")
    manifest_name = "sysroot-wasip1/manifest.json"
    if manifest_name not in expected or expected[manifest_name][0] > 1024 * 1024:
        raise ValueError("candidate sysroot manifest is missing or oversized")
    with zipfile.ZipFile(archive) as package:
        infos = package.infolist()
        if len(infos) != len(expected) or {info.filename for info in infos} != set(expected):
            raise ValueError("candidate sysroot ZIP entries differ from inventory")
        for info in infos:
            if info.is_dir() or (info.external_attr >> 16) != 0o100644:
                raise ValueError(f"invalid candidate sysroot ZIP entry type: {info.filename}")
            size, digest = expected[info.filename]
            if info.file_size != size:
                raise ValueError(f"candidate sysroot file size differs: {info.filename}")
            checksum = hashlib.sha256()
            received = 0
            with package.open(info) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    received += len(chunk)
                    if received > size:
                        raise ValueError(f"candidate sysroot file exceeds inventory: {info.filename}")
                    checksum.update(chunk)
            if received != size or checksum.hexdigest() != digest:
                raise ValueError(f"candidate sysroot file differs: {info.filename}")
        manifest_bytes = package.read(manifest_name)
        logical_files = sorted(name.removeprefix("sysroot-wasip1/")
                               for name in expected if name != manifest_name)
        if json.loads(manifest_bytes) != {"files": logical_files}:
            raise ValueError("candidate sysroot app manifest differs from inventory")
    return provenance, sha256(rustc), hashlib.sha256(manifest_bytes).hexdigest(), archive_digest


def stage(directory, app):
    if app.name != "Crabrix.app" or not app.is_dir() or not any(
        parent.name.endswith("-iphonesimulator") for parent in app.parents
    ):
        raise ValueError("target must be a built iOS Simulator Crabrix.app")
    if (app / "_CodeSignature").exists():
        raise ValueError("a signed app bundle cannot be modified for candidate tests")
    manifest_file = app / "toolchain.lock.json"
    manifest = json.loads(manifest_file.read_text())
    if manifest.get("source", {}).get("kind") != "legacy-tar-zstd":
        raise ValueError("test app is not the pinned baseline build")
    provenance, compiler_sha, manifest_sha, archive_sha = verify_candidate(directory)
    version = provenance.get("rustVersion")
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-[A-Za-z0-9.-]+)?", version or "")
    if not match:
        raise ValueError("candidate provenance lacks a Rust version")
    identity = "candidate-" + compiler_sha[:16]
    target = app / "Toolchain" / identity
    if target.exists():
        raise ValueError("candidate is already staged; use a fresh test app")
    target.mkdir(parents=True)
    for name in ("rustc.wasm", "sysroot-wasip1.zip", "sysroot-wasip1.sha256"):
        shutil.copyfile(directory / name, target / name)
    manifest.update({
        "toolchainID": identity,
        "target": "wasm32-wasip1",
        "rustVersion": version,
        "rustVersionComponents": dict(zip(("major", "minor", "patch"), map(int, match.groups()))),
        "rustcSHA256": compiler_sha,
        "sysrootManifestSHA256": manifest_sha,
        "sysrootArchiveSHA256": archive_sha,
        "source": {"kind": "local-candidate-test-only"},
    })
    with tempfile.NamedTemporaryFile("w", dir=app, prefix=".toolchain.lock.",
                                     suffix=".tmp", delete=False) as output:
        temporary = Path(output.name)
        json.dump(manifest, output, indent=2, sort_keys=True)
        output.write("\n")
    os.replace(temporary, manifest_file)
    print(f"TEST ONLY: staged {identity} in unsigned Simulator app; source manifest unchanged")


def prepared_test_run(source, app):
    if source.suffix != ".xctestrun" or source.parent.resolve() != app.parent.parent.resolve():
        raise ValueError("xctestrun must sit beside the Simulator build products")
    configuration = plistlib.loads(source.read_bytes())
    test = configuration.get("CrabrixTests")
    if not isinstance(test, dict) or test.get("TestHostPath") != \
            "__TESTROOT__/Release-iphonesimulator/Crabrix.app":
        raise ValueError("xctestrun does not target the Release Simulator test app")
    environment = test.get("EnvironmentVariables")
    if not isinstance(environment, dict):
        raise ValueError("xctestrun has no test environment")
    environment["CRABRIX_RUN_COMPILER_GATE"] = "1"
    environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"] = "1"
    output = source.with_name(source.stem + "-candidate.xctestrun")
    if output.exists():
        raise ValueError("candidate xctestrun already exists; use fresh build products")
    return output, plistlib.dumps(configuration)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate-dir", type=Path, required=True)
    parser.add_argument("--app-bundle", type=Path, required=True)
    parser.add_argument("--xctestrun", type=Path, required=True)
    args = parser.parse_args()
    try:
        app = args.app_bundle.resolve()
        test_run, test_run_bytes = prepared_test_run(args.xctestrun.resolve(), app)
        stage(args.candidate_dir.resolve(), app)
        with tempfile.NamedTemporaryFile("wb", dir=test_run.parent, prefix=".candidate-test-run.",
                                         suffix=".tmp", delete=False) as output:
            temporary = Path(output.name)
            output.write(test_run_bytes)
        os.replace(temporary, test_run)
        print(f"Candidate test configuration: {test_run}")
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        raise SystemExit(f"candidate staging rejected: {error}") from error


if __name__ == "__main__":
    main()
