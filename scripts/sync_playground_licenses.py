#!/usr/bin/env python3
"""Copy original notices for the fixed native codec and browser editor/runtime."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
packages = root / 'site/node_modules/.pnpm'
native = ['yjs', 'y-protocols', 'lib0', 'isomorphic.js', '@lezer/common', '@lezer/lr', '@lezer/rust']
web = native + ['y-codemirror.next', 'fflate', '@bjorn3/browser_wasi_shim', '@codemirror/legacy-modes', '@codemirror/lang-markdown', '@codemirror/lang-html', '@codemirror/lang-css', '@codemirror/lang-javascript', '@lezer/markdown', '@lezer/html', '@lezer/css', '@lezer/javascript', '@codemirror/autocomplete', '@codemirror/commands', '@codemirror/lang-rust', '@codemirror/language', '@codemirror/state', '@codemirror/view', '@lezer/highlight', 'crelt', 'style-mod', 'w3c-keyname']
texts = []
for name in web:
    matches = sorted(packages.glob(name.replace('/', '+') + '@*/node_modules/' + name + '/package.json'))
    if not matches: raise SystemExit('Missing installed package: ' + name)
    package = matches[-1].parent
    data = json.loads(matches[-1].read_text())
    licenses = [p for p in package.iterdir() if p.is_file() and (p.name.upper().startswith('LICENSE') or p.name.upper().startswith('COPYING') or p.name.upper() == 'NOTICE')]
    if not licenses: raise SystemExit('Missing original license: ' + name)
    content = '\n'.join(p.read_text() for p in sorted(licenses))
    texts.append(f'\n## {name} {data["version"]}\n\n{content.strip()}\n')
    if name in native:
        filename = name.replace('/', '-').lstrip('@') + '-LICENSE.txt'
        (root / 'Crabrix/Resources/Licenses' / filename).write_text(content)
        (root / 'site/public/licenses' / filename).write_text(content)
(root / 'site/public/licenses/PlaygroundThirdPartyNotices.txt').write_text('Crabrix Playground dependency notices\n\nOriginal license texts for redistributed browser and collaboration components.\n' + '\n'.join(texts))
