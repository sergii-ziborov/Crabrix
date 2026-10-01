"""Candidate staging accepts only verified local artifacts and unsigned test apps."""

import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parents[1] / "stage_candidate_toolchain_for_simulator.py"
SPEC = importlib.util.spec_from_file_location("candidate_staging", SCRIPT)
staging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(staging)
SOURCE_MANIFEST = SCRIPT.parents[1] / "Crabrix/Resources/toolchain.lock.json"


class CandidateStagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name)
        self.candidate = root / "candidate-artifacts"
        self.candidate.mkdir()
        self.app = root / "Build/Products/Release-iphonesimulator/Crabrix.app"
        self.app.mkdir(parents=True)
        (self.app / "toolchain.lock.json").write_bytes(SOURCE_MANIFEST.read_bytes())
        self.original_manifest = SOURCE_MANIFEST.read_bytes()
        self.test_run = self.app.parent.parent / "CrabrixCompilerGate.xctestrun"
        self.test_run.write_bytes(plistlib.dumps({"CrabrixTests": {
            "TestHostPath": "__TESTROOT__/Release-iphonesimulator/Crabrix.app",
            "EnvironmentVariables": {"CRABRIX_RUN_COMPILER_GATE": "1"},
        }}))
        self.write_candidate()

    def write_candidate(self, entries=None):
        entries = entries or {"lib/rustlib/wasm32-wasip1/lib/libstd-test.rlib": b"std"}
        manifest = (json.dumps({"files": sorted(entries)}, sort_keys=True,
                               separators=(",", ":")) + "\n").encode()
        archive_entries = {"sysroot-wasip1/" + name: data
                           for name, data in entries.items()}
        archive_entries["sysroot-wasip1/manifest.json"] = manifest
        inventory = []
        with zipfile.ZipFile(self.candidate / "sysroot-wasip1.zip", "w") as archive:
            for name, data in sorted(archive_entries.items()):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data)
                inventory.append({"path": name, "bytes": len(data),
                                  "sha256": hashlib.sha256(data).hexdigest()})
        (self.candidate / "sysroot-files.json").write_text(json.dumps(
            {"schemaVersion": 1, "files": inventory}))
        (self.candidate / "rustc.wasm").write_bytes(b"\0asm\1\0\0\0candidate")
        (self.candidate / "sysroot-wasip1.sha256").write_text(
            staging.sha256(self.candidate / "sysroot-wasip1.zip") + "\n")
        (self.candidate / "toolchain-provenance.json").write_text(json.dumps(
            {"candidate": True, "rustVersion": "1.96.0-dev"}))
        (self.candidate / "CANDIDATE-NOT-FOR-RELEASE.txt").write_text("test only\n")
        self.refresh_checksums()

    def refresh_checksums(self):
        files = sorted(path for path in self.candidate.iterdir()
                       if path.is_file() and path.name != "SHA256SUMS")
        (self.candidate / "SHA256SUMS").write_text("".join(
            f"{staging.sha256(path)}  {path.name}\n" for path in files))

    def test_stages_verified_candidate_without_changing_source_manifest(self):
        staging.stage(self.candidate, self.app)
        release = json.loads((self.app / "toolchain.lock.json").read_text())
        self.assertEqual(release["source"]["kind"], "local-candidate-test-only")
        self.assertEqual(release["rustcSHA256"], staging.sha256(self.candidate / "rustc.wasm"))
        self.assertTrue((self.app / "Toolchain" / release["toolchainID"] / "rustc.wasm").is_file())
        self.assertEqual(SOURCE_MANIFEST.read_bytes(), self.original_manifest)

    def test_rejects_artifact_tampering_before_app_mutation(self):
        (self.candidate / "rustc.wasm").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            staging.stage(self.candidate, self.app)
        self.assertEqual((self.app / "toolchain.lock.json").read_bytes(), self.original_manifest)

    def test_rejects_traversal_even_with_updated_checksums(self):
        self.write_candidate({"../outside": b"escape"})
        with self.assertRaisesRegex(ValueError, "invalid or duplicate"):
            staging.stage(self.candidate, self.app)
        self.assertFalse((self.app / "Toolchain").exists())

    def test_rejects_signed_bundle(self):
        (self.app / "_CodeSignature").mkdir()
        with self.assertRaisesRegex(ValueError, "signed app"):
            staging.stage(self.candidate, self.app)

    def test_prepares_opt_in_heavy_probe_in_a_new_test_configuration(self):
        destination, contents = staging.prepared_test_run(self.test_run, self.app)
        self.assertEqual(destination.name, "CrabrixCompilerGate-candidate.xctestrun")
        environment = plistlib.loads(contents)["CrabrixTests"]["EnvironmentVariables"]
        self.assertEqual(environment["CRABRIX_RUN_COMPILER_GATE"], "1")
        self.assertEqual(environment["CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE"], "1")
        self.assertNotIn(b"CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE", self.test_run.read_bytes())

    def test_rejects_test_configuration_for_a_different_app(self):
        self.test_run.write_bytes(plistlib.dumps({"CrabrixTests": {
            "TestHostPath": "__TESTROOT__/Release-iphonesimulator/Other.app",
            "EnvironmentVariables": {},
        }}))
        with self.assertRaisesRegex(ValueError, "does not target"):
            staging.prepared_test_run(self.test_run, self.app)


if __name__ == "__main__":
    unittest.main()
