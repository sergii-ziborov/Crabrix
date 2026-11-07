"""A compiler update and repeated branch switches package exactly one toolchain."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPTS = Path(__file__).resolve().parents[1]

def digest(data):
    return hashlib.sha256(data).hexdigest()

class ToolchainPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        for name in ('package_toolchain.py', 'toolchain_manifest.py'):
            shutil.copyfile(SCRIPTS / name, self.root / 'scripts' / name)
        self.resources = self.root / 'Crabrix/Resources'
        self.resources.mkdir(parents=True)
        self.manifests = {}
        for variant in ('a', 'b'):
            identity = 'crabrix-rust-' + variant
            source = self.resources / 'Toolchain' / identity
            source.mkdir(parents=True)
            compiler = b'\0asm\1\0\0\0' + variant.encode()
            (source / 'rustc.wasm').write_bytes(compiler)
            manifest = b'{"files":[]}\n'
            archive = source / 'sysroot-wasip1.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr('sysroot-wasip1/manifest.json', manifest)
            archive_sha = digest(archive.read_bytes())
            (source / 'sysroot-wasip1.sha256').write_text(archive_sha)
            self.manifests[variant] = {
                'schemaVersion': 1, 'toolchainID': identity, 'target': 'wasm32-wasip1',
                'rustVersion': '1.96.0-dev', 'rustVersionComponents': {'major': 1, 'minor': 96, 'patch': 0},
                'rustcSHA256': digest(compiler), 'sysrootManifestSHA256': digest(manifest),
                'sysrootArchiveSHA256': archive_sha,
                'source': {'kind': 'crabrix-release-v1',
                    'baseURL': 'https://github.com/sergii-ziborov/crabrix-toolchain/releases/download/test-' + variant,
                    'keyID': 'test', 'sourceLockSHA256': 'a' * 64, 'builderSourceCommit': 'b' * 40,
                    'compilerAsset': {'name': 'rustc.wasm', 'sha256': digest(compiler)},
                    'sysrootAsset': {'name': archive.name, 'sha256': archive_sha},
                    'inventoryAsset': {'name': 'sysroot-files.json', 'sha256': 'c' * 64},
                    'descriptorAsset': {'name': 'toolchain.descriptor.json', 'sha256': 'd' * 64}}}

    def package(self, variant, succeeds=True):
        (self.resources / 'toolchain.lock.json').write_text(json.dumps(self.manifests[variant]))
        result = subprocess.run([sys.executable, str(self.root / 'scripts/package_toolchain.py')], capture_output=True, text=True)
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def test_signed_resources_without_legacy_marker_retire_safely(self):
        self.package('a'); self.package('b')
        self.assertEqual([p.name for p in (self.root / 'build/Resources/Toolchain').iterdir()], ['crabrix-rust-b'])
        old = self.root / 'build/.retired-toolchains/crabrix-rust-a'
        self.assertEqual((old / 'rustc.wasm').read_bytes(), b'\0asm\1\0\0\0a')

    def test_repeated_branch_switches_preserve_identical_recovery_copy(self):
        for variant in ('a', 'b', 'a', 'b'):
            self.package(variant)
        self.assertEqual([p.name for p in (self.root / 'build/Resources/Toolchain').iterdir()], ['crabrix-rust-b'])
        self.assertEqual((self.root / 'build/.retired-toolchains/crabrix-rust-a/rustc.wasm').read_bytes(), b'\0asm\1\0\0\0a')

    def test_different_retired_copy_is_never_overwritten(self):
        self.package('a'); self.package('b'); self.package('a')
        retained = self.root / 'build/.retired-toolchains/crabrix-rust-a/rustc.wasm'
        retained.write_bytes(b'different retained bytes')
        result = self.package('b', succeeds=False)
        self.assertIn('Retired toolchain differs', result.stderr)
        self.assertEqual(retained.read_bytes(), b'different retained bytes')
        self.assertTrue((self.root / 'build/Resources/Toolchain/crabrix-rust-a/rustc.wasm').exists())

    def test_unrecognized_generated_folder_is_preserved(self):
        self.package('a')
        unknown = self.root / 'build/Resources/Toolchain/unrecognized'
        unknown.mkdir(); (unknown / 'keep.txt').write_text('keep')
        result = self.package('b', succeeds=False)
        self.assertIn('Unexpected extra bundled toolchain resource', result.stderr)
        self.assertEqual((unknown / 'keep.txt').read_text(), 'keep')

if __name__ == '__main__':
    unittest.main()
