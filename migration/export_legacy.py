#!/usr/bin/env python3
"""Re-run the immutable Academy baseline from its exact historical Git tree."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_SHA = "c38423e7503a56d6cd97e3a6c17651d5a5c33d62"
SOURCE_FILES = (
    "Crabrix/Learn/RustCourseCatalog.swift",
    "Crabrix/Learn/RustLearningPath.swift",
    "Crabrix/Learn/RustLessonContent.swift",
    "Crabrix/Learn/RustLessonDepth.swift",
    "Crabrix/Learn/RustBasicsExpansion.swift",
    "Crabrix/Learn/RustAdvancedExpansion.swift",
    "Crabrix/Learn/AlgorithmCourseCatalog.swift",
    "Crabrix/Learn/AlgorithmCourseData.swift",
    "Crabrix/Learn/AlgorithmVerificationData.swift",
    "Crabrix/Learn/TermTrainDeck.swift",
    "Crabrix/Compiler/RustSamples.swift",
    "Crabrix/Compiler/RustShowcaseCatalog.swift",
    "Crabrix/Compiler/RustShowcaseExpansionCatalog.swift",
    "Crabrix/Compiler/RustVisualShowcaseCatalog.swift",
    "Crabrix/Compiler/RustCanvasOutput.swift",
)


def main() -> int:
    if len(sys.argv) > 3:
        raise SystemExit("usage: migration/export_legacy.sh [output.json] [content-version]")
    source_sha = os.environ.get("CRABRIX_COURSE_SOURCE_SHA", DEFAULT_SOURCE_SHA)
    if re.fullmatch(r"[0-9a-f]{40}", source_sha) is None:
        raise SystemExit("CRABRIX_COURSE_SOURCE_SHA must be an exact Git commit")
    commit = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", f"{source_sha}^{{commit}}"],
        text=True,
    ).strip()
    if commit != source_sha:
        raise SystemExit("source SHA did not resolve to the exact requested commit")
    output = sys.argv[1] if len(sys.argv) >= 2 else "migration/baseline-inventory.json"
    version = sys.argv[2] if len(sys.argv) >= 3 else "1.0.1"

    with tempfile.TemporaryDirectory(prefix="crabrix-legacy-export-") as temporary:
        workspace = Path(temporary)
        sources = []
        for name in SOURCE_FILES:
            source = workspace / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(subprocess.check_output(
                ["git", "-C", str(ROOT), "show", f"{source_sha}:{name}"]
            ))
            sources.append(str(source))
        binary = workspace / "export-legacy"
        subprocess.run(
            ["swiftc", "-O", "-D", "DEBUG", "-o", str(binary),
             str(ROOT / "migration/LegacyExportStubs.swift"),
             str(ROOT / "migration/export_legacy.swift"), *sources],
            check=True,
            cwd=ROOT,
        )
        subprocess.run([str(binary), source_sha, version, output], check=True, cwd=ROOT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
