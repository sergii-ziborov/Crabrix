"""Vendor pinned offline compiler tools; never evaluate project code here."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import tarfile

p = argparse.ArgumentParser()
p.add_argument('--vendor-dir', required=True, type=Path)
args = p.parse_args()
root = Path(__file__).resolve().parents[1]
records = json.loads((args.vendor_dir / 'source-lock.json').read_text())
parts = ['// Bundled, pinned Babel and node-semver. Compiler tools, not project code.\n']
for record in records:
    archive = args.vendor_dir / (record['name'].split('/')[-1] + '.tgz')
    algorithm, integrity = record['dist']['integrity'].split('-', 1)
    assert algorithm == 'sha512'
    assert base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode() == integrity
    with tarfile.open(archive) as packed:
        def read(name): return packed.extractfile('package/' + name).read().decode()
        license_name = 'babel-standalone' if record['name'] == '@babel/standalone' else 'node-semver'
        (root / 'Crabrix/Resources/Licenses' / (license_name + '-LICENSE.txt')).write_text(read('LICENSE'))
        if record['name'] == '@babel/standalone':
            parts.append(read('babel.min.js') + '\n')
        else:
            modules = {e.name[8:]: packed.extractfile(e).read().decode()
                       for e in packed if e.isfile() and e.name.endswith('.js') and not e.name.startswith('package/bin/')}
            parts.append('var CrabrixNpmSemver = (() => { const process={env:{}}; const factories={\n')
            for name, source in sorted(modules.items()):
                parts.append(json.dumps(name) + ':function(module,exports,require){\n' + source + '\n},\n')
            parts.append('''}; const cache=Object.create(null);
function resolve(from,spec){
 if(!spec.startsWith('.'))throw Error('Unexpected bundled semver dependency '+spec);
 const a=from.split('/');a.pop();for(const p of spec.split('/')){if(p==='..')a.pop();else if(p!=='.')a.push(p)}
 const path=a.join('/');return factories[path]?path:factories[path+'.js']?path+'.js':path+'/index.js';
}
function load(id){if(cache[id])return cache[id].exports;const m=cache[id]={exports:{}};
 if(!factories[id])throw Error('Missing bundled semver module '+id);
 factories[id](m,m.exports,s=>load(resolve(id,s)));return m.exports;}
return load('index.js');})();\n''')
output = ''.join(parts)
(root / 'Crabrix/Resources/WebCompilerRuntime.js').write_text(output)
lock = {'tools': [{'name': r['name'], 'version': r['version'], 'integrity': r['dist']['integrity'],
                  'tarball': r['dist']['tarball']} for r in records],
        'bundleSHA256': hashlib.sha256(output.encode()).hexdigest(),
        'scope': 'Bundled trusted transformation and version-range tools; no project code executes in JavaScriptCore.'}
(root / 'scripts/web-compiler-source-lock.json').write_text(json.dumps(lock, indent=2) + '\n')
print('Vendored offline compiler:', len(output.encode()), 'bytes')
