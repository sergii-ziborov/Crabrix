import base64
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import fetch_crabrix_toolchain as own
import toolchain_manifest


PUBLIC_TEST_KEY = "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="
SIGNED_TEST_SIGNATURE = "q9z2/tKthqRow0+NO47YFwFhPxAha9uRhOJ4s1iKr2bn6BoqdEQwW4ZEMmNSUdrM4jjKfmTuo1BiXSE33hoJBg=="


class CrabrixToolchainFetchTests(unittest.TestCase):
    def signed_release(self):
        rustc, sysroot, manifest, inventory = "c" * 64, "d" * 64, "e" * 64, "f" * 64
        payload = {
            "schemaVersion": 1, "releaseTag": "test-1", "toolchainID": "test-toolchain",
            "target": "wasm32-wasip1", "rustVersion": "1.96.0-dev",
            "rustcSHA256": rustc, "sysrootArchiveSHA256": sysroot,
            "sysrootManifestSHA256": manifest, "sourceLockSHA256": "a" * 64,
            "builderSourceCommit": "b" * 40,
            "assets": {
                "rustc.wasm": {"bytes": 8, "sha256": rustc},
                "sysroot-wasip1.zip": {"bytes": 10, "sha256": sysroot},
                "sysroot-files.json": {"bytes": 20, "sha256": inventory},
            },
        }
        release = {
            "schemaVersion": 1, "toolchainID": "test-toolchain",
            "target": "wasm32-wasip1", "rustVersion": "1.96.0-dev",
            "rustVersionComponents": {"major": 1, "minor": 96, "patch": 0},
            "rustcSHA256": rustc, "sysrootArchiveSHA256": sysroot,
            "sysrootManifestSHA256": manifest,
            "source": {
                "kind": "crabrix-release-v1",
                "baseURL": "https://github.com/sergii-ziborov/crabrix-toolchain/releases/download/test-1",
                "keyID": "public-test-key",
                "sourceLockSHA256": "a" * 64,
                "builderSourceCommit": "b" * 40,
                "compilerAsset": {"name": "rustc.wasm", "sha256": rustc},
                "sysrootAsset": {"name": "sysroot-wasip1.zip", "sha256": sysroot},
                "inventoryAsset": {"name": "sysroot-files.json", "sha256": inventory},
                "descriptorAsset": {"name": "toolchain.descriptor.json", "sha256": "0" * 64},
            },
        }
        return release, payload

    def test_signed_descriptor_and_release_manifest_match(self):
        release, payload = self.signed_release()
        with tempfile.TemporaryDirectory(prefix="crabrix-own-toolchain-test-") as temporary:
            root = Path(temporary)
            source = root / "toolchain.lock.json"
            source.write_text(json.dumps(release))
            with patch.object(toolchain_manifest, "MANIFEST", source):
                self.assertEqual(toolchain_manifest.load_manifest(), release)
            keyring = root / "keys.json"
            keyring.write_text(json.dumps({"schemaVersion": 1, "keys": [
                {"keyID": "public-test-key", "publicKeyBase64": PUBLIC_TEST_KEY}
            ]}))
            raw = (json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n").encode()
            descriptor = root / "toolchain.descriptor.json"
            envelope = {
                "keyID": "public-test-key",
                "payloadBase64": base64.b64encode(raw).decode(),
                "signatureBase64": SIGNED_TEST_SIGNATURE,
            }
            descriptor.write_text(json.dumps(envelope))
            with patch.object(own, "KEYRING", keyring):
                self.assertEqual(own.verify_descriptor(descriptor, release), payload)
                envelope["payloadBase64"] = base64.b64encode(raw.replace(b"test-1", b"test-2")).decode()
                descriptor.write_text(json.dumps(envelope))
                with self.assertRaisesRegex(ValueError, "signature is invalid"):
                    own.verify_descriptor(descriptor, release)
                descriptor.write_text('{"keyID":"public-test-key","keyID":"public-test-key",'
                                      '"payloadBase64":"x","signatureBase64":"y"}')
                with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                    own.verify_descriptor(descriptor, release)

    def test_sysroot_inventory_rejects_extra_and_tampered_entries(self):
        with tempfile.TemporaryDirectory(prefix="crabrix-sysroot-test-") as temporary:
            root = Path(temporary)
            files = {
                "sysroot-wasip1/manifest.json": b'{"files":["lib/libstd-test.rlib"]}\n',
                "sysroot-wasip1/lib/libstd-test.rlib": b"std",
            }
            archive = root / "sysroot-wasip1.zip"
            with zipfile.ZipFile(archive, "w") as package:
                for name, content in sorted(files.items()):
                    info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                    info.external_attr = 0o100644 << 16
                    package.writestr(info, content)
            inventory = root / "sysroot-files.json"
            inventory.write_text(json.dumps({"schemaVersion": 1, "files": [
                {"path": name, "bytes": len(content),
                 "sha256": hashlib.sha256(content).hexdigest()}
                for name, content in sorted(files.items())
            ]}))
            manifest_sha = hashlib.sha256(files["sysroot-wasip1/manifest.json"]).hexdigest()
            own.verify_sysroot(archive, inventory, manifest_sha)
            broken = json.loads(inventory.read_text())
            broken["files"].append({"path": "sysroot-wasip1/../escape",
                                    "bytes": 0, "sha256": "0" * 64})
            inventory.write_text(json.dumps(broken))
            with self.assertRaisesRegex(ValueError, "invalid sysroot inventory"):
                own.verify_sysroot(archive, inventory, manifest_sha)
            broken["files"].pop()
            broken["files"].append({"path": "sysroot-wasip1/LIB/libstd-test.rlib",
                                    "bytes": 0, "sha256": "0" * 64})
            inventory.write_text(json.dumps(broken))
            with self.assertRaisesRegex(ValueError, "colliding sysroot paths"):
                own.verify_sysroot(archive, inventory, manifest_sha)

    def test_packager_copies_verified_own_assets_without_rewriting_zip(self):
        release, _ = self.signed_release()
        with tempfile.TemporaryDirectory(prefix="crabrix-own-package-test-") as temporary:
            root = Path(temporary)
            scripts = root / "scripts"
            scripts.mkdir()
            for name in ("toolchain_manifest.py", "package_toolchain.py"):
                shutil.copyfile(SCRIPTS / name, scripts / name)
            source = root / "Crabrix/Resources/Toolchain/test-toolchain"
            source.mkdir(parents=True)
            compiler = source / "rustc.wasm"
            compiler.write_bytes(b"\0asm\1\0\0\0")
            archive = source / "sysroot-wasip1.zip"
            manifest = b'{"files":["lib/libstd-test.rlib"]}\n'
            with zipfile.ZipFile(archive, "w") as package:
                package.writestr("sysroot-wasip1/manifest.json", manifest)
            release["rustcSHA256"] = hashlib.sha256(compiler.read_bytes()).hexdigest()
            release["sysrootArchiveSHA256"] = hashlib.sha256(archive.read_bytes()).hexdigest()
            release["sysrootManifestSHA256"] = hashlib.sha256(manifest).hexdigest()
            release["source"]["compilerAsset"]["sha256"] = release["rustcSHA256"]
            release["source"]["sysrootAsset"]["sha256"] = release["sysrootArchiveSHA256"]
            lock = root / "Crabrix/Resources/toolchain.lock.json"
            lock.write_text(json.dumps(release))
            previous = root / "build/Resources/Toolchain/artifacts-test-7"
            previous.mkdir(parents=True)
            (previous / ".inputs-sha256").write_text("old-generated-inputs")
            (previous / "rustc.wasm").write_bytes(b"old compiler")
            command = ["/usr/bin/python3", str(scripts / "package_toolchain.py")]
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            packaged = root / "build/Resources/Toolchain/test-toolchain"
            self.assertEqual((packaged / "rustc.wasm").read_bytes(), compiler.read_bytes())
            self.assertEqual((packaged / "sysroot-wasip1.zip").read_bytes(), archive.read_bytes())
            self.assertFalse(previous.exists())
            self.assertEqual((root / "build/.retired-toolchains/artifacts-test-7/rustc.wasm").read_bytes(),
                             b"old compiler")
            archive.write_bytes(archive.read_bytes() + b"tampered")
            result = subprocess.run(command, capture_output=True, text=True, check=False)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("sysroot differs", result.stderr)


if __name__ == "__main__":
    unittest.main()
