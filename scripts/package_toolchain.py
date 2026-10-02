#!/usr/bin/env python3
"""Package the pinned WASI sysroot as compiler data, not loose app libraries.

The ZIP is a signed, bundled resource (never downloaded at runtime). Crabrix
extracts it locally for the bundled interpreter. App Review notes disclose this.
"""
import hashlib
import shutil
import zipfile
from pathlib import Path
from toolchain_manifest import load_manifest

project = Path(__file__).resolve().parent.parent
release = load_manifest()
version = release['toolchainID']
source = project / 'Crabrix/Resources/Toolchain' / version
output = project / 'build/Resources/Toolchain' / version
output.mkdir(parents=True, exist_ok=True)
if release['source']['kind'] == 'crabrix-release-v1':
    compiler = source / 'rustc.wasm'
    archive = source / 'sysroot-wasip1.zip'
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != release['rustcSHA256']:
        raise SystemExit('Own source-built rustc differs from the app release manifest')
    if hashlib.sha256(archive.read_bytes()).hexdigest() != release['sysrootArchiveSHA256']:
        raise SystemExit('Own source-built sysroot differs from the app release manifest')
    with zipfile.ZipFile(archive) as packaged:
        manifest = packaged.read('sysroot-wasip1/manifest.json')
    if hashlib.sha256(manifest).hexdigest() != release['sysrootManifestSHA256']:
        raise SystemExit('Own source-built sysroot manifest differs from the app release manifest')
    shutil.copyfile(compiler, output / 'rustc.wasm')
    shutil.copyfile(archive, output / 'sysroot-wasip1.zip')
    (output / 'sysroot-wasip1.sha256').write_text(release['sysrootArchiveSHA256'])
    # XcodeGen includes this entire folder. Keep a previous build's compiler
    # recoverable outside that folder so the new app does not bundle both.
    resource_root = output.parent
    retired_root = project / 'build/.retired-toolchains'
    for item in resource_root.iterdir():
        if item.name == version:
            continue
        if item.is_symlink() or not item.is_dir() or not (item / '.inputs-sha256').is_file():
            raise SystemExit(f'Unexpected extra bundled toolchain resource: {item}')
        retired = retired_root / item.name
        if retired.exists():
            raise SystemExit(f'Retired toolchain directory already exists: {retired}')
        retired_root.mkdir(parents=True, exist_ok=True)
        item.replace(retired)
    print('Packaged verified Crabrix source-built compiler resources:', output)
    raise SystemExit(0)
archive = output / 'sysroot-wasip1.zip'
# Rebuild when any input changes; deterministic timestamps keep hashes stable.
inputs = sorted(p for p in (source / 'sysroot-wasip1').rglob('*') if p.is_file())
fingerprint = hashlib.sha256()
for path in inputs:
    fingerprint.update(path.relative_to(source).as_posix().encode())
    fingerprint.update(hashlib.sha256(path.read_bytes()).digest())
marker = output / '.inputs-sha256'
identity = fingerprint.hexdigest()
if not archive.exists() or not marker.exists() or marker.read_text() != identity:
    temporary = output / 'sysroot-wasip1.zip.partial'
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as packaged:
        for path in inputs:
            info = zipfile.ZipInfo(path.relative_to(source).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            packaged.writestr(info, path.read_bytes())
    temporary.replace(archive)
    marker.write_text(identity)
archive_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
if archive_digest != release['sysrootArchiveSHA256']:
    raise SystemExit('Packaged sysroot differs from the app release manifest')
(output / 'sysroot-wasip1.sha256').write_text(archive_digest)
compiler = output / 'rustc.wasm'
compiler_digest = hashlib.sha256((source / 'rustc.wasm').read_bytes()).hexdigest()
if compiler_digest != release['rustcSHA256']:
    raise SystemExit('Bundled rustc differs from the app release manifest')
if not compiler.exists() or hashlib.sha256(compiler.read_bytes()).digest() != hashlib.sha256((source / 'rustc.wasm').read_bytes()).digest():
    shutil.copyfile(source / 'rustc.wasm', compiler)
print('Packaged bundled compiler resources:', output)
