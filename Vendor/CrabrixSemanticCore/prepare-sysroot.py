#!/usr/bin/env python3
"""Export analysis text from the exact compiler revision, without running it."""
import argparse
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

parser = argparse.ArgumentParser()
parser.add_argument('--rust-source', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
manifest = json.loads((Path(__file__).parent / 'upstream-manifest.json').read_text())
revision = manifest['compilerRustSourceCommit']
archive = subprocess.check_output(['git', '-C', args.rust_source, 'archive', revision,
                                   'library/core', 'library/alloc', 'library/std'])
files = []
with tarfile.open(fileobj=io.BytesIO(archive)) as package:
    for entry in package:
        path = PurePosixPath(entry.name)
        if path.suffix != '.rs' or 'tests' in path.parts or 'benches' in path.parts:
            continue
        assert entry.isfile() and not path.is_absolute() and '..' not in path.parts
        files.append({'path': '__lib/' + '/'.join(path.parts[1:]),
                      'text': package.extractfile(entry).read().decode('utf-8')})
crates = []
for name, dependencies in [('core', []), ('alloc', ['core']), ('std', ['core', 'alloc'])]:
    crates.append({'root': f'__lib/{name}/src/lib.rs', 'name': name, 'kind': name,
                   'edition': '2024', 'dependencies': {d: f'__lib/{d}/src/lib.rs' for d in dependencies}})
result = {'schemaVersion': 1, 'toolchainID': manifest['toolchainID'], 'rustSourceCommit': revision,
          'files': sorted(files, key=lambda f: f['path']), 'crates': crates,
          'scope': 'Exact core/alloc/std sources; auxiliary sysroot dependency crates and external proc macros are not loaded.'}
Path(args.output).write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':')) + '\n')
print(f'Exported {len(files)} pinned Rust source files; no build scripts executed.')
