#!/usr/bin/env python3
"""Package the pinned WASI sysroot as compiler data, not loose app libraries.

The ZIP is a signed, bundled resource (never downloaded at runtime). Crabrix
extracts it locally for the bundled interpreter. App Review notes disclose this.
"""
import hashlib
import shutil
import zipfile
from pathlib import Path

project = Path(__file__).resolve().parent.parent
version = 'artifacts-test-7'
source = project / 'Crabrix/Resources/Toolchain' / version
output = project / 'build/Resources/Toolchain' / version
output.mkdir(parents=True, exist_ok=True)
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
(output / 'sysroot-wasip1.sha256').write_text(hashlib.sha256(archive.read_bytes()).hexdigest())
compiler = output / 'rustc.wasm'
if not compiler.exists() or hashlib.sha256(compiler.read_bytes()).digest() != hashlib.sha256((source / 'rustc.wasm').read_bytes()).digest():
    shutil.copyfile(source / 'rustc.wasm', compiler)
print('Packaged bundled compiler resources:', output)
