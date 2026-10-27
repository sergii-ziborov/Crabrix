#!/usr/bin/env python3
"""Verify the public archive digest and compare Atlas lesson/check JSON objects."""

import base64
import hashlib
import json
from pathlib import Path
import ssl
import urllib.request
import zipfile

import certifi

ROOT = Path(__file__).resolve().parents[3]
COURSES = ROOT.parent / "crabrix-courses"
OUT = ROOT / "build/academy-audit-20261027/public"
OUT.mkdir(parents=True, exist_ok=True)
opener = urllib.request.build_opener(urllib.request.HTTPSHandler(
    context=ssl.create_default_context(cafile=certifi.where())))


def download(url, path, limit):
    with opener.open(url, timeout=30) as response, path.open("wb") as target:
        size = 0
        while block := response.read(1024 * 1024):
            size += len(block)
            if size > limit: raise ValueError("download exceeds expected size")
            target.write(block)


catalog_url = "https://raw.githubusercontent.com/sergii-ziborov/crabrix-courses/main/catalog.v1.json"
catalog_file = OUT / "catalog.v1.json"
download(catalog_url, catalog_file, 128 * 1024)
envelope = json.loads(catalog_file.read_text())
catalog = json.loads(base64.b64decode(envelope["payloadBase64"]))
entry = next(c for c in catalog["courses"] if c["courseID"] == "algorithms")
archive = OUT / f"algorithms-{entry['contentVersion']}.zip"
if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != entry["archiveSHA256"]:
    download(entry["archiveURL"], archive, entry["archiveBytes"])
assert archive.stat().st_size == entry["archiveBytes"]
assert hashlib.sha256(archive.read_bytes()).hexdigest() == entry["archiveSHA256"]
differences = []
compared = 0
with zipfile.ZipFile(archive) as pack:
    for name in pack.namelist():
        if name.startswith(("lessons/", "checks/")) and name.endswith(".json"):
            compared += 1
            if json.loads(pack.read(name)) != json.loads((COURSES / "courses/algorithms" / name).read_text()):
                differences.append(name)
assert compared == 1200, f"Expected 600 lessons and 600 checks; compared {compared}"
assert not differences, differences
record = {"date": "2026-10-27", "catalogURL": catalog_url,
          "catalogByteIdenticalToLocal": catalog_file.read_bytes() == (COURSES / "catalog.v1.json").read_bytes(),
          "sequence": catalog["sequence"], "courseID": "algorithms", "contentVersion": entry["contentVersion"],
          "archiveURL": entry["archiveURL"], "archiveBytes": archive.stat().st_size,
          "archiveSHA256": entry["archiveSHA256"], "archiveDigestMatchesCatalog": True,
          "lessonAndCheckObjectsCompared": compared, "differences": differences,
          "scope": "Archive SHA-256 and JSON parity; not a fresh Ed25519 verification or iPhone execution"}
Path(__file__).with_name("public-pack.json").write_text(json.dumps(record, indent=2)+"\n")
print(json.dumps(record, indent=2))
