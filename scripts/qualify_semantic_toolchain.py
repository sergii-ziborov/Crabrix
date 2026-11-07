#!/usr/bin/env python3
"""Rebind unchanged analysis sources only after verifying the signed Rust source lock."""
import argparse
import hashlib
import json
from pathlib import Path

import fetch_crabrix_toolchain as fetcher
import verify_semantic_core as semantic
from toolchain_manifest import load_manifest


def digest(data):
    return hashlib.sha256(data).hexdigest()


def qualify(release_dir, exported_library):
    active = load_manifest()
    resource = semantic.RESOURCE
    manifest_path = resource / 'manifest.json'
    manifest = json.loads(manifest_path.read_text())
    upstream = json.loads((semantic.VENDOR / 'upstream-manifest.json').read_text())
    assert 'toolchainCompatibility' not in manifest, 'Already qualified; inspect existing binding'
    assert manifest['toolchainID'] == upstream['toolchainID'] != active['toolchainID']
    descriptor = release_dir / 'toolchain.descriptor.json'
    assert digest(descriptor.read_bytes()) == active['source']['descriptorAsset']['sha256']
    signed = fetcher.verify_descriptor(descriptor, active)
    lock_bytes = (release_dir / 'toolchain.lock.json').read_bytes()
    assert digest(lock_bytes) == active['source']['sourceLockSHA256']
    assert signed['releaseFiles']['toolchain.lock.json']['sha256'] == digest(lock_bytes)
    lock = json.loads(lock_bytes)
    assert lock['rust']['revision'] == upstream['compilerRustSourceCommit'], 'Rust source changed; rebuild the analyzer'
    assert lock['rust']['actualVersion'] == active['rustVersion']
    library_path = resource / 'stdlib.json'
    original = library_path.read_bytes()
    # The existing exporter reads all 1,011 files from git archive at the
    # pinned compiler revision. Require byte equality before changing metadata.
    assert original == exported_library.read_bytes(), 'Analysis source export differs'
    assert digest(original) == manifest['files']['stdlib.json']['sha256']
    for name, entry in {**manifest['files'], **manifest['notices']}.items():
        data = (resource / name).read_bytes()
        assert len(data) == entry['bytes'] and digest(data) == entry['sha256'], name
    receipt = json.loads((resource / 'build-receipt.json').read_text())
    assert receipt['upstream'] == upstream
    assert digest((resource / 'engine.wasm').read_bytes()) == receipt['moduleSHA256']
    old_id, new_id = upstream['toolchainID'].encode(), active['toolchainID'].encode()
    assert original.count(old_id) == 1
    updated = original.replace(old_id, new_id, 1)
    manifest['toolchainID'] = active['toolchainID']
    manifest['files']['stdlib.json'] = {'bytes': len(updated), 'sha256': digest(updated)}
    manifest['toolchainCompatibility'] = {
        'schemaVersion': 1,
        'analysisBuildToolchainID': upstream['toolchainID'],
        'activeToolchainID': active['toolchainID'],
        'compilerRustSourceCommit': lock['rust']['revision'],
        'compilerSourceLockSHA256': digest(lock_bytes),
        'compilerBuilderSourceCommit': active['source']['builderSourceCommit'],
        'compilerArtifactIdentity': active['rustcSHA256'] + ':' + active['sysrootManifestSHA256'],
        'unchangedEngineSHA256': receipt['moduleSHA256'],
        'originalStdlibSHA256': digest(original),
        'method': 'Exact re-export from the same pinned Rust revision; packaging identity only; original build receipt unchanged',
    }
    library_path.write_bytes(updated)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    semantic.verify()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--signed-toolchain', type=Path, required=True)
    parser.add_argument('--exported-library', type=Path, required=True)
    args = parser.parse_args()
    qualify(args.signed_toolchain, args.exported_library)
