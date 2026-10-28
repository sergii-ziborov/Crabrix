#!/usr/bin/env python3
"""Verify pinned native Git inputs and the offline corresponding-source export.

Use --write-source after changing the Swift service/package. Ordinary builds only
verify; they cannot silently refresh a stale or modified source inventory.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Vendor/CrabrixGitCore"
RESOURCE = ROOT / "Crabrix/Resources/GitCore"


def source_zip():
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(PACKAGE.rglob("*")):
            relative = path.relative_to(PACKAGE)
            if any(p.startswith(".") for p in relative.parts):
                continue
            assert not path.is_symlink(), f"Unexpected source symlink: {relative}"
            if not path.is_file():
                continue
            entry = zipfile.ZipInfo("CrabrixGitCore/" + relative.as_posix(), (2026, 10, 28, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, path.read_bytes())
    return output.getvalue()


def verify(write_source=False):
    manifest = json.loads((PACKAGE / "upstream-manifest.json").read_text())
    original = PACKAGE / "libgit2-v1.9.7-source.tar.gz"
    assert hashlib.sha256(original.read_bytes()).hexdigest() == manifest["sourceArchiveSHA256"]
    assert manifest["sourceVersion"] == "1.9.7"
    code = PACKAGE / "Sources/CLibgit2"
    actual = {p.relative_to(code).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in code.rglob("*") if p.is_file()}
    assert actual == manifest["files"], "Native Git source/configuration inventory differs"
    assert len(manifest["sourceList"]) == 211
    package_text = (PACKAGE / "Package.swift").read_text()
    assert all('"' + p + '"' in package_text for p in manifest["sourceList"])
    with tarfile.open(original) as archive:
        originals = {p.name.split("/", 1)[1]: p for p in archive if p.isfile() and "/" in p.name}
        for path in actual:
            if path in originals:
                assert (code / path).read_bytes() == archive.extractfile(originals[path]).read(), path
        with zipfile.ZipFile(RESOURCE / "GitCoreNotices.zip") as notices:
            assert notices.testzip() is None
            inventory = json.loads((RESOURCE / "GitCoreNoticeIndex.json").read_text())
            for item in inventory:
                for path in item["documents"]:
                    assert notices.read(path) == archive.extractfile(originals[path]).read(), path
    expected = source_zip()
    destination = RESOURCE / "CrabrixGitCoreSource.zip"
    if write_source:
        destination.write_bytes(expected)
    assert destination.read_bytes() == expected, "Stale Git source export; run scripts/verify_git_core.py --write-source"
    print("Native Git 1.9.7: 211 compiled sources, original notices and complete source export verified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-source", action="store_true")
    verify(parser.parse_args().write_source)
