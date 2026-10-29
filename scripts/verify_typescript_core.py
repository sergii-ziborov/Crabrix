#!/usr/bin/env python3
"""Check the fixed offline TypeScript compiler, library and original notices."""
import hashlib, json, os, zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
assets = root/'Crabrix/Resources/TypeScriptCore'
source = root/'Vendor/CrabrixTypeScriptCore'
manifest = json.loads((assets/'manifest.json').read_text())
assert manifest['schemaVersion'] == 1 and manifest['version'] == '5.9.3'
assert manifest['archiveSHA256'] == '10e108c9cf7d5f2879053dff18515fb405abf2ccef63eaaf017d9c571687a1d3'
assert manifest['standardLibraries'] == 100
if os.environ.get('CONFIGURATION', '').lower() == 'release':
    assert not manifest.get('candidateOnly', True), 'Unqualified TypeScript candidate cannot enter a release.'
assert set(manifest['files']) == {'index.html','host.js','worker.js','compiler.js','library.json'}
for name,item in {**manifest['files'], **manifest['notices']}.items():
    data = (assets/name).read_bytes()
    assert len(data) == item['bytes'] and hashlib.sha256(data).hexdigest() == item['sha256'], name
for name in ['host.js','worker.js','index.html']:
    assert (assets/name).read_bytes() == (source/name).read_bytes(), name
assert manifest['files']['compiler.js']['sha256'] == '3ae902c92cc44dace175c0e69e13a4b0899f6983c6121d76b9ab8dd5795e7675'
assert manifest['files']['library.json']['sha256'] == '8843742bf056985266c3eeef11b3f3d8afff3dd3464c39e44fc442113a523351'
libraries = json.loads((assets/'library.json').read_text())
assert len(libraries) == 100 and '/lib/lib.dom.d.ts' in libraries and '/lib/lib.es2024.full.d.ts' in libraries
assert all(name.startswith('/lib/lib.') and name.endswith('.d.ts') for name in libraries)
index = json.loads((assets/'TypeScriptNoticeIndex.json').read_text())
assert len(index)==1 and index[0]['id']=='typescript-5.9.3'
with zipfile.ZipFile(assets/'TypeScriptNotices.zip') as archive:
    assert archive.testzip() is None
    for name in ['LICENSE.txt','ThirdPartyNoticeText.txt']:
        assert archive.read(name) == (assets/name).read_bytes()
print('Pinned TypeScript 5.9.3, 100 original declaration libraries, source-bound Worker and original notices verified.')
