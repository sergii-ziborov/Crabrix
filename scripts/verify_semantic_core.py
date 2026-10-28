#!/usr/bin/env python3
"""Verify the source-bound, import-free and memory-bounded local analyzer."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / 'Crabrix/Resources/SemanticCore'
VENDOR = ROOT / 'Vendor/CrabrixSemanticCore'


def leb(data, at):
    value = 0
    for shift in range(0, 35, 7):
        byte = data[at]; at += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, at
    raise AssertionError('Invalid Wasm integer')


def verify():
    manifest = json.loads((RESOURCE / 'manifest.json').read_text())
    receipt = json.loads((RESOURCE / 'build-receipt.json').read_text())
    upstream = json.loads((VENDOR / 'upstream-manifest.json').read_text())
    assert receipt['upstream'] == upstream
    source = json.loads((VENDOR / 'patched-source.json').read_text())
    assert receipt['patchedSourceAudit']['patchedSourceSHA256'] == source['patchedSourceSHA256']
    assert receipt['patchedSourceAudit']['sourceFiles'] == source['sourceFiles']
    assert source['upstreamArchiveSHA256'] == upstream['upstreamArchiveSHA256']
    assert source['patches'] == upstream['patches']
    assert manifest['schemaVersion'] == 1 and manifest['toolchainID'] == upstream['toolchainID']
    assert set(manifest['files']) == {'index.html', 'host.js', 'worker.js', 'engine.wasm', 'stdlib.json'}
    for path, expected in receipt['sourceFiles'].items():
        assert hashlib.sha256((VENDOR / path).read_bytes()).hexdigest() == expected, path
    for patch in upstream['patches']:
        assert hashlib.sha256((VENDOR / patch['path']).read_bytes()).hexdigest() == patch['sha256']
    for name, item in {**manifest['files'], **manifest['notices']}.items():
        data = (RESOURCE / name).read_bytes()
        assert len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256'], name
    module = (RESOURCE / 'engine.wasm').read_bytes()
    assert module[:8] == b'\0asm\x01\0\0\0'
    assert hashlib.sha256(module).hexdigest() == receipt['moduleSHA256']
    offset = 8; memories = 0
    while offset < len(module):
        section = module[offset]; length, start = leb(module, offset + 1); offset = start + length
        assert offset <= len(module)
        if section == 2:
            count, _ = leb(module, start); assert count == 0, 'Engine imports host capabilities'
        if section == 5:
            count, cursor = leb(module, start); assert count == 1
            flags, cursor = leb(module, cursor); minimum, cursor = leb(module, cursor); maximum, cursor = leb(module, cursor)
            assert flags == 1 and 0 < minimum <= maximum == 4096, 'Engine memory is not capped at 256 MiB'
            memories += 1
    assert memories == 1 and not upstream['networkAtRuntime'] and not upstream['externalProcMacros']
    library = json.loads((RESOURCE / 'stdlib.json').read_text())
    assert library['rustSourceCommit'] == upstream['compilerRustSourceCommit']
    assert library['toolchainID'] == manifest['toolchainID']
    assert len(library['files']) == 1011 and len({f['path'] for f in library['files']}) == 1011
    assert len(library['crates']) == 3 and all(f['path'].startswith('__lib/') for f in library['files'])
    index = json.loads((RESOURCE / 'SemanticNoticeIndex.json').read_text())
    assert len(index) == 194 and len({i['id'] for i in index}) == 194
    with zipfile.ZipFile(RESOURCE / 'SemanticVendorNotices.zip') as archive:
        assert archive.testzip() is None
        names = archive.namelist(); assert len(names) == len(set(names))
        assert all(not p.startswith('/') and '..' not in p.split('/') for p in names)
        assert 'rust/license-metadata.json' in names and 'rust/COPYRIGHT' in names
        assert all(item['documents'] and all(p in names for p in item['documents']) for item in index)
    print('Pinned semantic engine, 256 MiB memory cap, 1,011 Rust sources and 194 notice groups verified')


if __name__ == '__main__':
    verify()
