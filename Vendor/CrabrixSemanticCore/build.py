#!/usr/bin/env python3
"""Build the pinned, import-free semantic module. Never runs at app runtime."""
import argparse,hashlib,json,os,shutil,subprocess,tarfile
from pathlib import Path
from source_identity import verify_source

p=argparse.ArgumentParser();p.add_argument('--rust-source',required=True);p.add_argument('--work',required=True);p.add_argument('--target-dir',required=True);p.add_argument('--stage',action='store_true');a=p.parse_args()
source=Path(a.rust_source).resolve();work=Path(a.work).resolve();target=Path(a.target_dir).resolve();vendor=Path(__file__).resolve().parent;repo=vendor.parents[1]
manifest=json.loads((vendor/'upstream-manifest.json').read_text());work.mkdir(parents=True,exist_ok=True)
archive=work/'upstream.tar'
if not archive.exists():
    with archive.open('wb')as f:subprocess.run(['git','-C',str(source),'archive',manifest['upstreamCommit'],manifest['upstreamSubdirectory']],stdout=f,check=True)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['upstreamArchiveSHA256'],'Pinned upstream archive differs'
upstream=work/'rust-analyzer'
if not upstream.exists():
    with tarfile.open(archive)as package:
        prefix=manifest['upstreamSubdirectory']+'/'
        for entry in package:
            if not entry.name.startswith(prefix):continue
            name=entry.name[len(prefix):]
            if not name:continue
            destination=upstream/name
            assert not Path(name).is_absolute() and '..'not in Path(name).parts
            if entry.isdir():destination.mkdir(parents=True,exist_ok=True)
            elif entry.isfile():destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(package.extractfile(entry).read())
            elif entry.issym():
                assert not Path(entry.linkname).is_absolute()
                destination.parent.mkdir(parents=True,exist_ok=True);assert (destination.parent/entry.linkname).resolve().is_relative_to(upstream.resolve());destination.symlink_to(entry.linkname)
            else:raise AssertionError('Unsupported upstream archive entry')
    for patch in manifest['patches']:
        path=vendor/patch['path'];assert hashlib.sha256(path.read_bytes()).hexdigest()==patch['sha256']
        subprocess.run(['git','-C',str(upstream),'apply',str(path)],check=True)
source_audit=verify_source(upstream,vendor)
core=work/'core'
if core.exists():shutil.rmtree(core)
shutil.copytree(vendor,core,ignore=shutil.ignore_patterns('notices','__pycache__'))
env=os.environ.copy();env['CARGO_TARGET_DIR']=str(target)
env['CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS']=' '.join([
    '--cfg no_salsa_async_drops','-C link-arg=--max-memory=268435456','-C link-arg=-zstack-size=2097152',
    '--remap-path-prefix='+str(work)+'=/crabrix/semantic',
    '--remap-path-prefix='+str(Path.home()/'.cargo/registry/src')+'=/cargo/registry',
])
subprocess.run(['cargo','build','--locked','--manifest-path',str(core/'Cargo.toml'),'--target','wasm32-unknown-unknown','--release','-j','2'],env=env,check=True)
wasm=target/'wasm32-unknown-unknown/release/crabrix_semantic_core.wasm';assert wasm.read_bytes().startswith(b'\0asm')
receipt={'rustc':subprocess.check_output(['rustc','--version'],text=True).strip(),'upstream':manifest,'moduleSHA256':hashlib.sha256(wasm.read_bytes()).hexdigest(),'moduleBytes':wasm.stat().st_size,'sourceFiles':{str(f.relative_to(vendor)):hashlib.sha256(f.read_bytes()).hexdigest()for f in [vendor/'src/lib.rs',vendor/'Cargo.toml',vendor/'Cargo.lock']},'staged':a.stage}
receipt['patchedSourceAudit']={**source_audit,'checkedBeforeBuild':True}
(work/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
if a.stage:shutil.copyfile(wasm,repo/'Crabrix/Resources/SemanticCore/engine.wasm')
print(json.dumps({'moduleBytes':wasm.stat().st_size,'sha256':receipt['moduleSHA256'],'staged':a.stage}))
