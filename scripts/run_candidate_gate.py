#!/usr/bin/env python3
"""Run exact Simulator candidate gates and reject Xcode's zero-test success."""

import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xctestrun", type=Path, required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--result-bundle", type=Path, required=True)
    parser.add_argument("--test", action="append", required=True)
    args = parser.parse_args()

    run_file = args.xctestrun.resolve()
    result = args.result_bundle.resolve()
    if result.exists():
        parser.error(f"result bundle already exists: {result}")
    record = plistlib.loads(run_file.read_bytes())
    candidate = record.get("CrabrixTests")
    if not isinstance(candidate, dict):
        parser.error("xctestrun has no CrabrixTests target")
    allowed = set(candidate.get("OnlyTestIdentifiers", []))
    selected = sorted(set(args.test))
    if len(selected) != len(args.test) or not set(selected) <= allowed:
        parser.error("tests must be unique exact identifiers in the candidate xctestrun")
    candidate["OnlyTestIdentifiers"] = selected

    # Xcode resolves paths relative to the test-run file. Keep the temporary
    # selection beside the original so its app and test bundle paths survive.
    with tempfile.NamedTemporaryFile(
        dir=run_file.parent, prefix=".crabrix-selected-", suffix=".xctestrun",
        delete=False,
    ) as temporary:
        chosen = Path(temporary.name)
        temporary.write(plistlib.dumps(record))
    try:
        completed = subprocess.run([
            "xcodebuild", "test-without-building", "-xctestrun", str(chosen),
            "-destination", args.destination, "-parallel-testing-enabled", "NO",
            "-resultBundlePath", str(result),
        ], check=False)
    finally:
        chosen.unlink(missing_ok=True)

    if not result.is_dir():
        print("xcodebuild produced no result bundle", file=sys.stderr)
        return 1
    summary_process = subprocess.run([
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result), "--format", "json",
    ], check=False, capture_output=True, text=True)
    if summary_process.returncode:
        print(summary_process.stderr, file=sys.stderr)
        return 1
    summary = json.loads(summary_process.stdout)
    expected = len(selected)
    observed = summary.get("totalTestCount")
    failed = summary.get("failedTests")
    skipped = summary.get("skippedTests")
    passed = summary.get("passedTests")
    print(f"candidate gate: expected={expected} executed={observed} "
          f"passed={passed} failed={failed} skipped={skipped}")
    if completed.returncode or observed != expected or passed != expected or failed or skipped:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
