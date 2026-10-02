#!/usr/bin/env python3
"""Fetch a signed, pinned Crabrix toolchain for bundling on the build Mac."""

import base64
import binascii
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata
import uuid
import zipfile

from toolchain_manifest import ROOT, load_manifest


KEYRING = ROOT / "scripts/toolchain-public-keys.json"
VERIFY_SWIFT = ROOT / "scripts/verify_toolchain_descriptor.swift"
HEX = re.compile(r"[0-9a-f]{64}\Z")
MAX_FILES = 4096
MAX_UNCOMPRESSED = 2 * 1024 * 1024 * 1024
LIMITS = {
    "descriptorAsset": 1024 * 1024,
    "compilerAsset": 256 * 1024 * 1024,
    "sysrootAsset": 512 * 1024 * 1024,
    "inventoryAsset": 16 * 1024 * 1024,
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unique_json(payload):
    def pairs(values):
        result = {}
        for key, value in values:
            if key in result:
                raise ValueError(f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(payload, object_pairs_hook=pairs)


def cache_root():
    override = os.environ.get("CRABRIX_ARTIFACT_CACHE")
    if override:
        return Path(override)
    result = subprocess.run(["getconf", "DARWIN_USER_CACHE_DIR"],
                            capture_output=True, text=True, check=False)
    base = result.stdout.strip() if result.returncode == 0 else ""
    if not base:
        base = f"/tmp/crabrix-cache-{os.getuid()}"
    return Path(base) / "com.sergiiziborov.Crabrix" / "signed-toolchain"


def download(source, key, destination):
    asset = source[key]
    if destination.is_file() and destination.stat().st_size <= LIMITS[key] and \
            sha256(destination) == asset["sha256"]:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".download-",
                                     suffix=".partial", delete=False) as temporary:
        partial = Path(temporary.name)
    try:
        subprocess.run([
            "curl", "--fail", "--location", "--retry", "3", "--max-redirs", "5",
            "--proto", "=https", "--proto-redir", "=https",
            "--max-filesize", str(LIMITS[key]), "--output", str(partial),
            source["baseURL"] + "/" + asset["name"],
        ], check=True)
        if partial.stat().st_size > LIMITS[key] or sha256(partial) != asset["sha256"]:
            raise ValueError(f"{key} differs from the app release manifest")
        partial.replace(destination)
    finally:
        partial.unlink(missing_ok=True)


def verify_descriptor(path, release):
    source = release["source"]
    envelope = unique_json(path.read_bytes())
    if not isinstance(envelope, dict) or set(envelope) != {
        "keyID", "payloadBase64", "signatureBase64"
    } or envelope["keyID"] != source["keyID"]:
        raise ValueError("invalid toolchain descriptor envelope")
    keys = unique_json(KEYRING.read_bytes())
    if not isinstance(keys, dict) or keys.get("schemaVersion") != 1 or not isinstance(keys.get("keys"), list):
        raise ValueError("invalid built-in toolchain keyring")
    matches = [key for key in keys["keys"]
               if isinstance(key, dict) and key.get("keyID") == source["keyID"]]
    if len(matches) != 1:
        raise ValueError("toolchain signing key ID is not uniquely trusted")
    try:
        public = base64.b64decode(matches[0]["publicKeyBase64"], validate=True)
    except (KeyError, ValueError, binascii.Error) as error:
        raise ValueError("invalid built-in toolchain public key") from error
    if len(public) != 32:
        raise ValueError("invalid built-in toolchain public key length")
    result = subprocess.run([
        "/usr/bin/swift", str(VERIFY_SWIFT), str(path), source["keyID"],
        matches[0]["publicKeyBase64"],
    ], capture_output=True, check=False)
    if result.returncode != 0:
        raise ValueError("toolchain descriptor signature is invalid")
    payload = unique_json(result.stdout)
    if not isinstance(payload, dict) or payload.get("schemaVersion") != 1:
        raise ValueError("unsupported signed toolchain descriptor")
    for field in ("toolchainID", "target", "rustVersion", "rustcSHA256",
                  "sysrootArchiveSHA256", "sysrootManifestSHA256"):
        if payload.get(field) != release[field]:
            raise ValueError(f"signed toolchain {field} differs from app release input")
    if payload.get("sourceLockSHA256") != source["sourceLockSHA256"] or \
            payload.get("builderSourceCommit") != source["builderSourceCommit"] or \
            payload.get("releaseTag") != source["baseURL"].rsplit("/", 1)[-1]:
        raise ValueError("signed toolchain provenance differs from app release input")
    assets = payload.get("assets")
    if not isinstance(assets, dict) or set(assets) != {
        "rustc.wasm", "sysroot-wasip1.zip", "sysroot-files.json"
    }:
        raise ValueError("signed toolchain asset inventory is incomplete")
    for key in ("compilerAsset", "sysrootAsset", "inventoryAsset"):
        asset = source[key]
        record = assets[asset["name"]]
        if not isinstance(record, dict) or record.get("sha256") != asset["sha256"] or \
                not isinstance(record.get("bytes"), int) or record["bytes"] < 0 or \
                record["bytes"] > LIMITS[key]:
            raise ValueError(f"signed {key} differs from app release input")
    return payload


def verify_sysroot(archive_path, inventory_path, expected_manifest_sha):
    inventory = unique_json(inventory_path.read_bytes())
    if inventory.get("schemaVersion") != 1 or not isinstance(inventory.get("files"), list):
        raise ValueError("invalid source-built sysroot inventory")
    expected = {}
    folded = set()
    total = 0
    for item in inventory["files"]:
        if not isinstance(item, dict):
            raise ValueError("invalid sysroot inventory entry")
        name, size, digest = item.get("path"), item.get("bytes"), item.get("sha256")
        if not isinstance(name, str) or not name.startswith("sysroot-wasip1/") or \
                "\\" in name or "\0" in name or any(part in ("", ".", "..") for part in name.split("/")) or \
                PurePosixPath(name).is_absolute() or name in expected or \
                not isinstance(size, int) or isinstance(size, bool) or size < 0 or \
                not isinstance(digest, str) or not HEX.fullmatch(digest):
            raise ValueError(f"invalid sysroot inventory path or digest: {name}")
        folded_name = unicodedata.normalize("NFC", name).casefold()
        if folded_name in folded:
            raise ValueError(f"colliding sysroot paths: {name}")
        folded.add(folded_name)
        expected[name] = (size, digest)
        total += size
        if len(expected) > MAX_FILES or total > MAX_UNCOMPRESSED:
            raise ValueError("sysroot archive exceeds build-time limits")
    manifest_name = "sysroot-wasip1/manifest.json"
    if manifest_name not in expected or expected[manifest_name][0] > 1024 * 1024:
        raise ValueError("sysroot manifest missing or oversized")
    for name in expected:
        parts = name.split("/")
        if any(unicodedata.normalize("NFC", "/".join(parts[:index])).casefold() in folded
               for index in range(1, len(parts))):
            raise ValueError(f"file and directory path collision: {name}")
    with zipfile.ZipFile(archive_path) as archive:
        infos = archive.infolist()
        if len(infos) != len(expected) or {entry.filename for entry in infos} != set(expected):
            raise ValueError("sysroot ZIP differs from signed inventory")
        for entry in infos:
            if entry.is_dir() or (entry.external_attr >> 16) != 0o100644 or \
                    entry.file_size != expected[entry.filename][0]:
                raise ValueError(f"invalid sysroot ZIP entry: {entry.filename}")
            digest = hashlib.sha256()
            count = 0
            with archive.open(entry) as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    count += len(chunk)
                    if count > expected[entry.filename][0]:
                        raise ValueError("sysroot entry exceeds its signed size")
                    digest.update(chunk)
            if count != expected[entry.filename][0] or digest.hexdigest() != expected[entry.filename][1]:
                raise ValueError(f"sysroot entry differs from signed inventory: {entry.filename}")
        manifest = archive.read(manifest_name)
    if hashlib.sha256(manifest).hexdigest() != expected_manifest_sha:
        raise ValueError("sysroot manifest digest differs from app release input")
    listed = unique_json(manifest)
    logical = sorted(name.removeprefix("sysroot-wasip1/") for name in expected if name != manifest_name)
    if listed != {"files": logical}:
        raise ValueError("sysroot manifest differs from inventory")


def main():
    release = load_manifest()
    source = release["source"]
    if source["kind"] != "crabrix-release-v1":
        raise ValueError("own toolchain fetch requires crabrix-release-v1")
    root = ROOT / "Crabrix/Resources/Toolchain"
    installed = root / release["toolchainID"]
    cache = cache_root() / release["toolchainID"]
    paths = {key: cache / source[key]["name"] for key in LIMITS}
    download(source, "descriptorAsset", paths["descriptorAsset"])
    signed = verify_descriptor(paths["descriptorAsset"], release)
    for key in ("compilerAsset", "sysrootAsset", "inventoryAsset"):
        download(source, key, paths[key])
        asset = source[key]
        if paths[key].stat().st_size != signed["assets"][asset["name"]]["bytes"]:
            raise ValueError(f"downloaded {key} byte count differs from signed descriptor")
    verify_sysroot(paths["sysrootAsset"], paths["inventoryAsset"],
                   release["sysrootManifestSHA256"])
    if installed.exists():
        if (installed / "rustc.wasm").is_file() and \
                sha256(installed / "rustc.wasm") == release["rustcSHA256"] and \
                (installed / "sysroot-wasip1.zip").is_file() and \
                sha256(installed / "sysroot-wasip1.zip") == release["sysrootArchiveSHA256"]:
            print("Verified already staged Crabrix toolchain:", installed)
            return
        raise ValueError(f"incomplete toolchain directory already exists: {installed}")
    root.mkdir(parents=True, exist_ok=True)
    staging = root / (".stage-" + uuid.uuid4().hex)
    try:
        staging.mkdir()
        for key in ("compilerAsset", "sysrootAsset", "inventoryAsset", "descriptorAsset"):
            shutil.copyfile(paths[key], staging / source[key]["name"])
        (staging / "sysroot-wasip1.sha256").write_text(release["sysrootArchiveSHA256"])
        os.replace(staging, installed)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print("Staged signed Crabrix source-built toolchain:", installed)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError,
            zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Crabrix toolchain fetch rejected: {error}") from error
