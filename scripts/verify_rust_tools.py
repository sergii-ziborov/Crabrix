#!/usr/bin/env python3
"""Check the exact offline formatter inputs and source/notices inventory."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "Crabrix/Resources/RustTools"


def verify():
    manifest = json.loads((RESOURCE / "manifest.json").read_text())
    artifact = (RESOURCE / "rust_fmt.wasm").read_bytes()
    assert artifact[:4] == b"\0asm", "Not a WASM artifact"
    assert len(artifact) == manifest["byteLength"], "Formatter size differs"
    assert hashlib.sha256(artifact).hexdigest() == manifest["artifactSHA256"], "Formatter hash differs"
    archive = RESOURCE / "RustfmtVendorNotices.zip"
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == manifest["licenseArchiveSHA256"], "Notices hash differs"
    inventory = json.loads((RESOURCE / "RustfmtNoticeIndex.json").read_text())
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None, "Invalid notices archive"
        names = set(package.namelist())
        assert len(names) == len(package.namelist()), "Duplicate archive paths"
        assert "crates/option-ext-0.2.0/src/lib.rs" in names, "MPL source missing"
        assert "crates/option-ext-0.2.0/src/impl.rs" in names, "MPL source missing"
        for item in inventory:
            assert item["documents"], "Empty notice inventory"
            assert all(name in names for name in item["documents"]), "Missing original notice"
        for name in names:
            assert not name.startswith("/") and ".." not in name.split("/"), "Unsafe archive path"
    assert not manifest["networkAtRuntime"]
    print("Pinned rustfmt and", len(inventory), "offline notice groups verified")


if __name__ == "__main__":
    verify()
