"""A packaging identity change must preserve source and original build provenance."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import qualify_semantic_toolchain as subject


def sha(data):
    return hashlib.sha256(data).hexdigest()


class SemanticToolchainQualificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.resource, self.vendor, self.release = [root / name for name in ('resource', 'vendor', 'release')]
        for directory in (self.resource, self.vendor, self.release):
            directory.mkdir()
        self.revision = 'a' * 40
        upstream = {'toolchainID': 'old-toolchain', 'compilerRustSourceCommit': self.revision}
        (self.vendor / 'upstream-manifest.json').write_text(json.dumps(upstream))
        self.library = b'{"toolchainID":"old-toolchain","files":[{"text":"unchanged Rust"}]}\n'
        (self.resource / 'stdlib.json').write_bytes(self.library)
        self.export = root / 'reexport.json'
        self.export.write_bytes(self.library)
        module = b'\0asm\1\0\0\0unit-fixture'
        (self.resource / 'engine.wasm').write_bytes(module)
        self.original_receipt = json.dumps({'upstream': upstream, 'moduleSHA256': sha(module)}).encode()
        (self.resource / 'build-receipt.json').write_bytes(self.original_receipt)
        manifest = {'toolchainID': 'old-toolchain', 'files': {
            name: {'bytes': len(data), 'sha256': sha(data)}
            for name, data in [('stdlib.json', self.library), ('engine.wasm', module)]},
            'notices': {'build-receipt.json': {'bytes': len(self.original_receipt), 'sha256': sha(self.original_receipt)}}}
        (self.resource / 'manifest.json').write_text(json.dumps(manifest))
        descriptor = b'unit descriptor; signature boundary is mocked'
        (self.release / 'toolchain.descriptor.json').write_bytes(descriptor)
        self.active = {'toolchainID': 'new-toolchain', 'rustVersion': '1.96.0-dev',
            'rustcSHA256': 'b' * 64, 'sysrootManifestSHA256': 'c' * 64,
            'source': {'builderSourceCommit': 'd' * 40,
                'descriptorAsset': {'sha256': sha(descriptor)}}}
        self.write_lock(self.revision)
        for target, name, value in [(subject, 'load_manifest', lambda: self.active),
                (subject.semantic, 'RESOURCE', self.resource), (subject.semantic, 'VENDOR', self.vendor),
                (subject.semantic, 'verify', lambda: None),
                (subject.fetcher, 'verify_descriptor', lambda *_: self.signed)]:
            item = patch.object(target, name, value)
            item.start(); self.addCleanup(item.stop)

    def write_lock(self, revision):
        data = json.dumps({'rust': {'revision': revision, 'actualVersion': '1.96.0-dev'}}).encode()
        (self.release / 'toolchain.lock.json').write_bytes(data)
        self.active['source']['sourceLockSHA256'] = sha(data)
        self.signed = {'releaseFiles': {'toolchain.lock.json': {'sha256': sha(data)}}}

    def test_preserves_original_receipt_and_every_source_byte(self):
        subject.qualify(self.release, self.export)
        self.assertEqual((self.resource / 'build-receipt.json').read_bytes(), self.original_receipt)
        updated = (self.resource / 'stdlib.json').read_bytes()
        self.assertEqual(updated.replace(b'new-toolchain', b'old-toolchain', 1), self.library)
        manifest = json.loads((self.resource / 'manifest.json').read_text())
        self.assertEqual(manifest['toolchainCompatibility']['originalStdlibSHA256'], sha(self.library))

    def test_changed_rust_revision_requires_a_rebuild_before_mutation(self):
        self.write_lock('e' * 40)
        with self.assertRaisesRegex(AssertionError, 'Rust source changed'):
            subject.qualify(self.release, self.export)
        self.assertEqual((self.resource / 'stdlib.json').read_bytes(), self.library)
        self.assertEqual((self.resource / 'build-receipt.json').read_bytes(), self.original_receipt)

    def test_different_source_reexport_is_rejected_before_mutation(self):
        self.export.write_bytes(self.library.replace(b'unchanged', b'changed'))
        with self.assertRaisesRegex(AssertionError, 'source export differs'):
            subject.qualify(self.release, self.export)
        self.assertEqual((self.resource / 'stdlib.json').read_bytes(), self.library)


if __name__ == '__main__':
    unittest.main()
