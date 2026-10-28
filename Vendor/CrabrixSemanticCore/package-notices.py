#!/usr/bin/env python3
"""Package original pinned component notices; no runtime dependency acquisition."""
import argparse,hashlib,json,zipfile
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('--metadata',required=True);p.add_argument('--upstream',required=True);p.add_argument('--rust-source',required=True);p.add_argument('--output',required=True);a=p.parse_args()
metadata=json.loads(Path(a.metadata).read_text());upstream=Path(a.upstream).resolve();rust=Path(a.rust_source).resolve();output=Path(a.output);output.mkdir(parents=True,exist_ok=True)
documents={};index=[]

def add(path,destination,allowed):
    assert not path.is_symlink(),path
    resolved=path.resolve();assert any(resolved.is_relative_to(root) for root in allowed),path
    data=path.read_bytes();assert 0<len(data)<=4*1024*1024,path
    documents[destination]=data
    return destination

for package in sorted(metadata['packages'],key=lambda d:(d['name'],d['version'])):
    if package['name'].startswith('crabrix-semantic-'):continue
    root=Path(package['manifest_path']).parent.resolve();local=root.is_relative_to(upstream)
    allowed=[upstream] if local else [root]
    paths=[]
    for pattern in ['LICENSE*','LICENCE*','COPYING*','NOTICE*','license*','licence*','licenses/*','LICENSES/*']:
        paths.extend(q for q in root.glob(pattern) if q.is_file() and not q.is_symlink())
    if package.get('license_file'):
        license_file=Path(package['license_file']);paths.append(license_file if license_file.is_absolute() else root/license_file)
    if not paths and local:paths=[upstream/'LICENSE-MIT',upstream/'LICENSE-APACHE']
    if not paths:
        name=package['name']
        if name in ['la-arena','line-index']:
            paths=[upstream/'LICENSE-MIT',upstream/'LICENSE-APACHE'];allowed.append(upstream)
        elif name.startswith('ra-ap-rustc_'):
            paths=[rust/'LICENSE-MIT',rust/'LICENSE-APACHE'];allowed.append(rust)
        elif name=='pulldown-cmark-to-cmark':
            # Its pinned repository has no root license file. The published
            # Cargo declaration specifies Apache-2.0; include the complete
            # original standard Apache text and the package's attribution.
            paths=[upstream/'LICENSE-APACHE'];allowed.append(upstream)
        elif name=='valuable':
            extra=Path(__file__).resolve().parent/'notices';paths=[extra/'valuable-0.1.1-LICENSE'];allowed.append(extra)
        else:raise AssertionError(('Original license files missing',name,package.get('license')))
        original=root/'Cargo.toml.orig'
        if original.is_file():paths.append(original)
        if (root/'README.md').is_file():paths.append(root/'README.md')
    docs=[]
    for path in sorted(set(paths)):
        if path.is_relative_to(upstream):destination='upstream/'+path.relative_to(upstream).as_posix()
        elif path.is_relative_to(rust):destination='rust/'+path.relative_to(rust).as_posix()
        elif path.is_relative_to(root):destination=f"crates/{package['name']}-{package['version']}/"+path.relative_to(root).as_posix()
        else:destination='upstream-notices/'+path.name
        docs.append(add(path,destination,allowed))
    index.append({'id':f"semantic/{package['name']}/{package['version']}",'name':package['name']+' '+package['version'],'summary':(package.get('license') or 'See original license')+' · semantic engine source/build inventory','archive':'SemanticVendorNotices','documents':sorted(set(docs))})
legal=[rust/name for name in ['LICENSE-MIT','LICENSE-APACHE','COPYRIGHT','license-metadata.json']]
legal+=sorted(path for path in (rust/'LICENSES').rglob('*') if path.is_file())
docs=[add(path,'rust/'+path.relative_to(rust).as_posix(),[rust]) for path in legal]
index.append({'id':'semantic/rust-standard-library/abc48c0','name':'Rust core, alloc and std source','summary':'MIT OR Apache-2.0 · exact compiler source abc48c0; text-only analysis library','archive':'SemanticVendorNotices','documents':docs})
with zipfile.ZipFile(output/'SemanticVendorNotices.zip','w',compression=zipfile.ZIP_DEFLATED,compresslevel=9)as archive:
    for name,data in sorted(documents.items()):
        entry=zipfile.ZipInfo(name,(2026,10,29,0,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;entry.external_attr=0o100644<<16;archive.writestr(entry,data)
(output/'SemanticNoticeIndex.json').write_text(json.dumps(index,indent=2)+'\n')
print(json.dumps({'components':len(index),'originalDocuments':len(documents),'bytes':(output/'SemanticVendorNotices.zip').stat().st_size,'sha256':hashlib.sha256((output/'SemanticVendorNotices.zip').read_bytes()).hexdigest()}))
