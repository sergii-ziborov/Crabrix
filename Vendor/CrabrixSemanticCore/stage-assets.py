#!/usr/bin/env python3
"""Bind the built module, text library and legal archive to one local bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument('--receipt', required=True)
args = parser.parse_args()
vendor = Path(__file__).resolve().parent
resource = vendor.parents[1] / 'Crabrix/Resources/SemanticCore'
receipt = json.loads(Path(args.receipt).read_text())
upstream = json.loads((vendor / 'upstream-manifest.json').read_text())
assert receipt['upstream'] == upstream
assert hashlib.sha256((resource / 'engine.wasm').read_bytes()).hexdigest() == receipt['moduleSHA256']
library = json.loads((resource / 'stdlib.json').read_text())
assert library['rustSourceCommit'] == upstream['compilerRustSourceCommit']
shutil.copyfile(args.receipt, resource / 'build-receipt.json')


def identity(name):
    data = (resource / name).read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


manifest = {'schemaVersion': 1, 'toolchainID': upstream['toolchainID'],
            'files': {name: identity(name) for name in ['engine.wasm', 'host.js', 'index.html', 'stdlib.json', 'worker.js']},
            'notices': {name: identity(name) for name in ['SemanticVendorNotices.zip', 'SemanticNoticeIndex.json', 'build-receipt.json']},
            'candidateOnly': True}
(resource / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Bound local semantic assets to the pinned build receipt; qualification is still required.')
