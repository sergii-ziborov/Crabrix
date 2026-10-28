"""Reject drift in a reused, patched analyzer checkout before compiling it."""
import hashlib
import json
from pathlib import Path


def verify_source(root: Path, vendor: Path):
    manifest = json.loads((vendor / 'upstream-manifest.json').read_text())
    expected = json.loads((vendor / 'patched-source.json').read_text())
    assert expected['upstreamCommit'] == manifest['upstreamCommit']
    assert expected['upstreamArchiveSHA256'] == manifest['upstreamArchiveSHA256']
    assert expected['patches'] == manifest['patches']
    files = {}
    for path in root.rglob('*'):
        name = path.relative_to(root).as_posix()
        if path.is_symlink():
            assert path.resolve().is_relative_to(root.resolve())
            files[name] = ['link', str(path.readlink())]
        elif path.is_file():
            files[name] = ['file', hashlib.sha256(path.read_bytes()).hexdigest()]
    digest = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    assert digest == expected['patchedSourceSHA256'] and len(files) == expected['sourceFiles'], 'Patched analyzer checkout changed; rebuild from the pinned archive and patches'
    return {'patchedSourceSHA256': digest, 'sourceFiles': len(files),
            'upstreamArchiveSHA256': manifest['upstreamArchiveSHA256']}
