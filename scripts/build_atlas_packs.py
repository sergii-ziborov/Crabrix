#!/usr/bin/env python3
"""Package verified site Atlas recordings as separately signed offline sections.

Only data is published: no compiler, runtime, executable or account material.
Signing requires the existing publisher seed supplied explicitly outside Git.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import zipfile

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def signed(value, domain, key, key_id):
    payload = canonical(value)
    return canonical({"keyID": key_id, "payloadBase64": base64.b64encode(payload).decode(),
                      "signatureBase64": base64.b64encode(key.sign(domain + payload)).decode()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--courses", type=Path, required=True)
    parser.add_argument("--traces", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--catalog-out", type=Path, required=True)
    parser.add_argument("--key-file", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--base-url", required=True)
    args = parser.parse_args()
    assert args.base_url.startswith(
        "https://github.com/sergii-ziborov/crabrix-courses/releases/download/")
    assert not args.key_id.startswith("test-")
    key = Ed25519PrivateKey.from_private_bytes(args.key_file.read_bytes())
    course = next(c for c in json.loads(args.courses.read_text())["courses"]
                  if c["id"] == "algorithms")
    manifest = json.loads((args.traces / "manifest.json").read_text())
    assert manifest["version"] == 1 and len(manifest["lessons"]) == 600
    args.out.mkdir(parents=True, exist_ok=True)
    entries, counts = [], []
    for unit in course["units"]:
        method = unit["algorithmMethod"]["id"]
        assert re.fullmatch(r"[a-z0-9-]+", method)
        pack_id, version = "atlas-" + method, "1.0.0"
        files, lessons = {}, {}
        for lesson in unit["lessons"]:
            trace_key = manifest["lessons"][lesson["id"]]
            assert re.fullmatch(r"[a-z0-9-]+", trace_key)
            data = (args.traces / (trace_key + ".json")).read_bytes()
            assert len(data) <= 2 * 1024 * 1024
            trace = json.loads(data)
            source_hash = digest(lesson["writing"]["exampleCode"].encode())
            assert trace["version"] == 1 and trace["sourceHash"] == source_hash
            assert trace["source"] == lesson["writing"]["exampleCode"]
            assert trace["category"] == method and trace["pattern"] == lesson["algorithm"]["patternID"]
            assert trace["verification"]["stdoutMatchesOriginal"] is True
            assert trace["verification"]["independentOracle"] is True
            assert 1 < len(trace["frames"]) <= 50_000
            files["traces/" + trace_key + ".json"] = data
            lessons[lesson["id"]] = {"key": trace_key, "sourceHash": source_hash}
        index = {"version": 1, "methodID": method, "title": unit["title"],
                 "courseContentVersion": course["contentVersion"], "lessons": lessons,
                 "recordings": {Path(path).stem: {"sha256": digest(data), "bytes": len(data)}
                                for path, data in sorted(files.items())}}
        files["index.json"] = canonical(index)
        inventory = {"schemaVersion": 1, "courseID": pack_id, "language": "en",
                     "contentVersion": version,
                     "files": [{"path": path, "bytes": len(data), "sha256": digest(data)}
                               for path, data in sorted(files.items())]}
        files["manifest.json"] = canonical(inventory)
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path, data in sorted(files.items()):
                info = zipfile.ZipInfo(path, (2026, 10, 28, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data)
        archive_data = output.getvalue()
        assert len(archive_data) <= 8 * 1024 * 1024
        archive_name = pack_id + "-" + version + ".zip"
        descriptor_name = pack_id + "-" + version + ".descriptor.json"
        descriptor = {"schemaVersion": 1, "courseID": pack_id, "language": "en",
                      "contentVersion": version, "archiveName": archive_name,
                      "archiveBytes": len(archive_data), "archiveSHA256": digest(archive_data),
                      "courseDigest": digest(files["index.json"]), "minimumAppVersion": "1.1.3",
                      "requiredCapabilities": ["atlas-replay-v1"]}
        descriptor_data = signed(descriptor, b"Crabrix.CourseDescriptor.v1\n", key, args.key_id)
        (args.out / archive_name).write_bytes(archive_data)
        (args.out / descriptor_name).write_bytes(descriptor_data)
        entries.append({k: descriptor[k] for k in [
            "courseID", "language", "contentVersion", "archiveBytes", "archiveSHA256",
            "minimumAppVersion", "requiredCapabilities"]} |
            {"descriptorURL": args.base_url + "/" + descriptor_name,
             "descriptorSHA256": digest(descriptor_data),
             "archiveURL": args.base_url + "/" + archive_name})
        counts.append({"method": method, "lessons": len(lessons),
                       "recordings": len(files) - 2, "archiveBytes": len(archive_data)})
    assert len(entries) == 20 and sum(c["lessons"] for c in counts) == 600
    assert sum(c["recordings"] for c in counts) == 400
    catalog = {"schemaVersion": 1, "sequence": 1,
               "releaseNotes": "400 verified source-bound Atlas recordings in 20 optional offline sections.",
               "courses": entries}
    catalog_data = signed(catalog, b"Crabrix.CourseCatalog.v1\n", key, args.key_id)
    args.catalog_out.parent.mkdir(parents=True, exist_ok=True)
    args.catalog_out.write_bytes(catalog_data)
    (args.out / "catalog.v1.json").write_bytes(catalog_data)
    (args.out / "qualification.json").write_bytes(canonical({
        "version": 1, "courseContentVersion": course["contentVersion"],
        "catalogSHA256": digest(catalog_data), "sections": counts,
        "totalArchiveBytes": sum(c["archiveBytes"] for c in counts)}))
    print(json.dumps({"sections": 20, "lessons": 600, "recordings": 400,
                      "downloadBytes": sum(c["archiveBytes"] for c in counts)}))


if __name__ == "__main__":
    main()
