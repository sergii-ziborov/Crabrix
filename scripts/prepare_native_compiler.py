#!/usr/bin/env python3
"""Prepare a pinned static compiler library on the build Mac only.

The iOS app never fetches this library. Its native compiler is part of the signed
executable; downloaded projects and macros remain interpreted WASM source work.
Without a qualified native input, the ordinary bundled WASM compiler is used.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def install(library, output):
    target = output / 'libCrabrixNativeCompiler.a'
    if target.exists() and sha(target) == sha(library): return
    temporary = output / '.library.partial'
    temporary.unlink(missing_ok=True)
    try:
        os.link(library, temporary)
    except OSError:
        shutil.copyfile(library, temporary)
    os.replace(temporary, target)


def verify_platform(library):
    archs = subprocess.check_output(['xcrun', 'lipo', '-archs', str(library)], text=True).strip()
    if archs != 'arm64': raise ValueError('Native compiler library must contain only arm64')
    load_commands = subprocess.check_output(['xcrun', 'otool', '-l', str(library)], text=True)
    platforms = [line.strip().split()[-1] for line in load_commands.splitlines() if line.strip().startswith('platform ')]
    if not platforms or any(value not in ('2', 'IOS') for value in platforms):
        raise ValueError('Native compiler objects were not built for the real iOS platform')


def prepare():
    if os.environ.get('PLATFORM_NAME') != 'iphoneos': return
    output = ROOT / 'build/NativeCompiler'
    output.mkdir(parents=True, exist_ok=True)
    candidate = os.environ.get('CRABRIX_NATIVE_COMPILER_CANDIDATE_LIBRARY')
    if candidate:
        flags = os.environ.get('OTHER_SWIFT_FLAGS', '')
        if os.environ.get('ENABLE_TESTABILITY') != 'YES' or 'CRABRIX_LEGACY_FIXTURES' not in flags:
            raise ValueError('A candidate native library is restricted to the explicit compiler test build')
        library = Path(candidate).resolve()
        record = json.loads((library.parent / 'native-compile-provenance.json').read_text())
        if record['target'] != 'arm64-apple-ios18.0' or sha(library) != record['archiveSHA256']:
            raise ValueError('Candidate native library differs from the actual iOS compile record')
        verify_platform(library)
        install(library, output)
        print('Prepared test-only iOS native compiler:', record['compilerWASMSHA256'])
        return
    lock = ROOT / 'scripts/native-compiler.lock.json'
    if not lock.exists():
        # Source builds of the app remain functional before/without a native
        # release. The stub advertises no compiler hash and cannot be selected.
        stub = output / 'fallback.o'
        library = output / 'fallback.a'
        sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
        subprocess.run(['xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios18.0',
            '-isysroot', sdk, '-O1', '-g0', '-DCRABRIX_NATIVE_COMPILER_BUILD_STUB=1', '-c',
            str(ROOT / 'Crabrix/Compiler/Native/NativeCompilerStub.c'), '-o', str(stub)], check=True)
        subprocess.run(['xcrun', '--sdk', 'iphoneos', 'libtool', '-static', '-o', str(library), str(stub)], check=True)
        install(library, output)
        print('Prepared WASM compiler fallback; no qualified native source input is enabled')
        return
    spec = json.loads(lock.read_text())
    release = json.loads((ROOT / 'Crabrix/Resources/toolchain.lock.json').read_text())
    if spec.get('schemaVersion') != 1 or spec.get('compilerWASMSHA256') != release['rustcSHA256']:
        raise ValueError('Native compiler input differs from the signed bundled toolchain')
    asset = spec['libraryAsset']
    if not asset['url'].startswith('https://github.com/sergii-ziborov/crabrix-toolchain/releases/download/') or \
            len(asset['sha256']) != 64 or any(c not in '0123456789abcdef' for c in asset['sha256']):
        raise ValueError('Invalid pinned native compiler asset')
    cache = output / asset['sha256']
    cache.mkdir(exist_ok=True)
    archive = cache / 'native-compiler-iphoneos-arm64.zip'
    if not archive.exists() or sha(archive) != asset['sha256']:
        temporary = archive.with_suffix('.partial')
        subprocess.run(['curl', '--fail', '--location', '--retry', '3', '--max-redirs', '5',
            '--proto', '=https', '--proto-redir', '=https', '--max-filesize', str(512 * 1024**2),
            '--output', str(temporary), asset['url']], check=True)
        if sha(temporary) != asset['sha256']: raise ValueError('Native compiler asset checksum differs')
        temporary.replace(archive)
    with zipfile.ZipFile(archive) as package:
        names = {'libCrabrixNativeCompiler.a', 'native-compile-provenance.json', 'native-binary-provenance.json'}
        if set(package.namelist()) != names or len(package.infolist()) != len(names):
            raise ValueError('Unexpected native compiler archive layout')
        if any(item.file_size > 1024 * 1024**2 or item.external_attr >> 16 != 0o100644 for item in package.infolist()):
            raise ValueError('Invalid native compiler archive entry')
        record = json.loads(package.read('native-compile-provenance.json'))
        origin = json.loads(package.read('native-binary-provenance.json'))
        if record['compilerWASMSHA256'] != spec['compilerWASMSHA256'] or \
                record['target'] != 'arm64-apple-ios18.0' or \
                origin['sourceArchiveSHA256'] != spec['sourceAsset']['sha256']:
            raise ValueError('Native compiler provenance differs from its pinned inputs')
        library = cache / 'libCrabrixNativeCompiler.a'
        if not library.exists() or sha(library) != record['archiveSHA256']:
            with package.open(library.name) as source, library.open('wb') as destination:
                shutil.copyfileobj(source, destination, length=1024 * 1024)
        if sha(library) != record['archiveSHA256']: raise ValueError('Native static library checksum differs')
    verify_platform(library)
    install(library, output)
    print('Prepared pinned, statically linked iOS compiler:', spec['compilerWASMSHA256'])


if __name__ == '__main__':
    try: prepare()
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        raise SystemExit('Native compiler preparation rejected: ' + str(error))
