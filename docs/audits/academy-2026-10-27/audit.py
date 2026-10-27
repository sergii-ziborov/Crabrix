#!/usr/bin/env python3
"""Read-only curriculum audit and executable counterexamples.

Run: python3 docs/audits/academy-2026-10-27/audit.py --courses ../crabrix-courses
No source content, signed pack, progress or production service is modified.
Rust checks use the local native compiler, not the iPhone/WASI runtime.
"""

import argparse
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess

from reference_algorithms import solve

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / "build/academy-audit-20261027"


def read(path):
    return json.loads(path.read_text())


def run(command, cwd=None):
    p = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=45)
    return {"exitCode": p.returncode, "stdout": p.stdout, "stderr": p.stderr[:1600]}


def rust_probe(name, source, *, compilation_fails=False):
    folder = WORK / name
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "main.rs").write_text(source)
    compiled = run(["rustc", "--edition=2024", "-C", "panic=unwind", "main.rs", "-o", "probe"], folder)
    if compilation_fails:
        assert compiled["exitCode"] != 0, name
        return {"compile": compiled}
    assert compiled["exitCode"] == 0, (name, compiled)
    return {"compile": compiled, "run": run([str(folder / "probe")], folder)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--courses", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("results.json"))
    args = parser.parse_args()
    course_repo = args.courses.resolve()
    WORK.mkdir(parents=True, exist_ok=True)
    snapshot = read(ROOT / "site/content/courses.json")
    rows = [(c, u, l) for c in snapshot["courses"] for u in c["units"] for l in u["lessons"]]
    structural = {"lessons": len(rows), "websiteAuthoringDifferences": [],
                  "imageDifferences": [], "invalidQuestionIndices": [],
                  "validatorQuestionDifferences": [], "invalidParentReferences": []}
    checks = {}
    for course, unit, lesson in rows:
        cid, lid = course["id"], lesson["id"]
        base = course_repo / "courses" / cid
        authored = read(base / "lessons" / f"{lid}.json")
        if authored != lesson: structural["websiteAuthoringDifferences"].append([cid, lid])
        if lesson["parentID"] != unit["id"] or lid not in unit["lessonIDs"]:
            structural["invalidParentReferences"].append([cid, lid])
        image = lesson["illustration"]["path"]
        website_image = ROOT / "site/content/learn-media" / cid / Path(image).name
        if not website_image.exists() or (base / image).read_bytes() != website_image.read_bytes():
            structural["imageDifferences"].append([cid, lid])
        w = lesson["writing"]
        if not 0 <= w["correctAnswer"] < len(w["answers"]):
            structural["invalidQuestionIndices"].append([cid, lid])
        check = read(base / "checks" / f"{lid}.json")
        checks[cid, lid] = check
        if check["evidence"]["kind"] == "reasoning" and check["evidence"]["correctAnswer"] != w["correctAnswer"]:
            structural["validatorQuestionDifferences"].append([cid, lid])

    # The oracles follow the published task literally. Missing implementations
    # are listed so coverage is explicit; they are not counted as passes.
    answers = {"checkedPatterns": 0, "checkedCases": 0, "mismatches": [], "notIndependentlyComputed": []}
    unique_cases, question_texts, sketches = Counter(), Counter(), defaultdict(list)
    for course, unit, lesson in rows:
        if course["id"] != "algorithms": continue
        a = lesson["algorithm"]
        question_texts[lesson["writing"]["question"]] += 1
        if a["stage"] == "model": sketches[a["rustSketch"]].append(a["patternID"])
        if a["stage"] != "challenge": continue
        cases = checks[course["id"], lesson["id"]]["challenge"]["verificationCases"]
        unique_cases[len({c["input"].strip() for c in cases})] += 1
        try:
            computed = [solve(a["patternID"], c["input"]) for c in cases]
        except NotImplementedError:
            answers["notIndependentlyComputed"].append(a["patternID"])
            continue
        answers["checkedPatterns"] += 1
        answers["checkedCases"] += len(cases)
        for c, actual in zip(cases, computed):
            if c["expectedAnswer"] != actual:
                answers["mismatches"].append({"pattern": a["patternID"], "kind": c["kind"], "input": c["input"],
                                               "published": c["expectedAnswer"], "computed": actual})

    def compile_example(row):
        course, _, lesson = row
        code = lesson["writing"]["exampleCode"]
        source = code if re.search(r"fn\s+main\s*\(", code) else "fn main() {\n" + code + "\n}\n"
        folder = WORK / "worked-examples" / course["id"] / lesson["id"]
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "sample.rs").write_text(source)
        p = run(["rustc", "--edition=2024", "--crate-name", "lesson_sample", "sample.rs", "-o", "sample"], folder)
        return {"course": course["id"], "lesson": lesson["id"],
                "status": "compiled" if p["exitCode"] == 0 else "requiresContextOrIntentionalFailure",
                "diagnostic": p["stderr"] if p["exitCode"] else ""}

    rust_rows = [r for r in rows if r[0]["id"] != "algorithms"]
    with ThreadPoolExecutor(max_workers=2) as pool:
        rust_examples = list(pool.map(compile_example, rust_rows))

    proofs = {}
    # Equal serialized values do not encode identity of list nodes. Both of
    # these graphs have the exact visible input but different intersections.
    class Node:
        def __init__(self, value, next_node=None):
            self.value, self.next = value, next_node

    def chain(values, tail=None):
        for value in reversed(values): tail = Node(value, tail)
        return tail

    def nodes(head):
        while head is not None:
            yield head
            head = head.next

    def intersection(a, b):
        seen = set(nodes(a))
        return next((n.value for n in nodes(b) if n in seen), None)

    list_cases = []
    for shared_values, prefix_a, prefix_b in [([8, 4, 5], [4, 1], [5, 6, 1]),
                                             ([1, 8, 4, 5], [4], [5, 6])]:
        shared = chain(shared_values)
        a, b = chain(prefix_a, shared), chain(prefix_b, shared)
        serialized = 'A=' + '->'.join(str(n.value) for n in nodes(a)) + '; B=' + '->'.join(str(n.value) for n in nodes(b))
        list_cases.append({"serializedInput": serialized, "firstSharedNodeValue": intersection(a, b)})
    assert list_cases[0]["serializedInput"] == list_cases[1]["serializedInput"]
    assert list_cases[0]["firstSharedNodeValue"] != list_cases[1]["firstSharedNodeValue"]
    proofs["listIntersectionInputDoesNotEncodeNodeIdentity"] = list_cases
    reservoir_cases = []
    for values, choices in [([10,20,30,40], [0,1,1,3]), ([5,6,7], [0,0,2])]:
        zero, current_index = values[0], values[0]
        for i, (value, choice) in enumerate(zip(values, choices)):
            assert 0 <= choice <= i
            if choice == 0: zero = value
            if choice == i: current_index = value
        reservoir_cases.append({"values": values, "choices": choices,
                                "replaceWhenChoiceIsZero": zero, "replaceWhenChoiceIsCurrentIndex": current_index})
    proofs["reservoirNeedsAnExplicitReplacementRule"] = reservoir_cases
    proofs["pinStringCanMoveInSafeRust"] = rust_probe("pin-string", r'''
use std::pin::Pin;
fn main() {
    let mut value = String::from("crab");
    let pinned = Pin::new(&mut value);
    let moved = std::mem::take(Pin::into_inner(pinned));
    assert_eq!(moved, "crab");
    assert!(value.is_empty());
    println!("String moved out through Pin without unsafe");
}
''')
    proofs["unwrapDoesNotAlwaysEndProcess"] = rust_probe("catch-panic", r'''
fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    let result = std::panic::catch_unwind(|| -> String {
        let result: Result<String, &str> = Err("unavailable");
        result.unwrap()
    });
    assert!(result.is_err());
    println!("process continued after unwinding unwrap panic");
}
''')
    proofs["futureCanBeDroppedBeforeFirstPoll"] = rust_probe("cancel-unpolled", r'''
use std::cell::Cell;
fn main() {
    let started = Cell::new(false);
    let future = async { started.set(true); };
    drop(future);
    assert!(!started.get());
    println!("future cancelled before its body started");
}
''')
    proofs["disabledCfgStillNeedsValidSyntax"] = rust_probe("cfg-syntax", r'''
#[cfg(any())]
fn disabled() { let = ; }
fn main() {}
''', compilation_fails=True)

    # Feed correct, general solutions to the actual packaged Rust harnesses.
    # Exit 1 is the reproduced bug, not a passing user solution.
    solutions = {
        "imos-sweep": r'''
pub fn solve(input: &str) -> String {
    let nums: Vec<i64> = input.split(|c: char| !c.is_ascii_digit() && c != '-')
        .filter(|s| !s.is_empty()).map(|s| s.parse().unwrap()).collect();
    let n = nums[0] as usize;
    let mut differences = vec![0_i64; n + 1];
    for update in nums[1..].chunks_exact(3) {
        differences[update[0] as usize] += update[2];
        differences[update[1] as usize + 1] -= update[2];
    }
    let mut current = 0_i64;
    let mut maximum = i64::MIN;
    for delta in &differences[..n] {
        current += delta;
        maximum = maximum.max(current);
    }
    maximum.to_string()
}
''',
        "complement-lookup": r'''
pub fn solve(input: &str) -> String {
    let nums: Vec<i32> = input.split(|c: char| !c.is_ascii_digit() && c != '-')
        .filter(|s| !s.is_empty()).map(|s| s.parse().unwrap()).collect();
    let (target, values) = nums.split_last().unwrap();
    // Pick the smallest left index; the task specifies no tie-breaking rule.
    // A set of suffix values keeps this O(n) expected time and O(n) space.
    let mut remaining = std::collections::HashMap::<i32, usize>::new();
    for &x in values { *remaining.entry(x).or_default() += 1; }
    for (i, &x) in values.iter().enumerate() {
        *remaining.get_mut(&x).unwrap() -= 1;
        if remaining.get(&(target - x)).copied().unwrap_or(0) > 0 {
            let j = i + 1 + values[i+1..].iter().position(|&y| x+y == *target).unwrap();
            return format!("{i},{j}");
        }
    }
    "-1,-1".into()
}
''',
    }
    for pattern, source in solutions.items():
        folder = WORK / f"harness-{pattern}"
        folder.mkdir(parents=True, exist_ok=True)
        challenge = checks["algorithms", f"algorithm.{pattern}.challenge"]["challenge"]
        (folder / "solution.rs").write_text(source)
        proofs[f"packagedHarnessRejectsCorrect-{pattern}"] = rust_probe(
            f"harness-{pattern}", challenge["verificationSource"])
        assert proofs[f"packagedHarnessRejectsCorrect-{pattern}"]["run"]["exitCode"] == 1

    feature_root = WORK / "feature-unification"
    files = {
        "Cargo.toml": '[workspace]\nmembers = ["app", "dep", "bridge"]\nresolver = "2"\n',
        "dep/Cargo.toml": '[package]\nname = "audit-dep"\nversion = "0.1.0"\nedition = "2024"\n[features]\ndefault = ["std"]\nstd = []\n',
        "dep/src/lib.rs": 'pub fn enabled() -> bool { cfg!(feature = "std") }\n',
        "bridge/Cargo.toml": '[package]\nname = "audit-bridge"\nversion = "0.1.0"\nedition = "2024"\n[dependencies]\naudit-dep = { path = "../dep" }\n',
        "bridge/src/lib.rs": 'pub fn enabled() -> bool { audit_dep::enabled() }\n',
        "app/Cargo.toml": '[package]\nname = "audit-app"\nversion = "0.1.0"\nedition = "2024"\n[dependencies]\naudit-dep = { path = "../dep", default-features = false }\naudit-bridge = { path = "../bridge" }\n',
        "app/src/main.rs": 'fn main() { assert!(audit_dep::enabled()); assert!(audit_bridge::enabled()); println!("std remains enabled by another dependency"); }\n',
    }
    for name, text in files.items():
        path = feature_root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    proofs["defaultFeaturesFalseIsNotGraphWideDisable"] = run(["cargo", "run", "--offline", "--quiet", "-p", "audit-app"], feature_root)
    assert proofs["defaultFeaturesFalseIsNotGraphWideDisable"]["exitCode"] == 0
    for key in ["pinStringCanMoveInSafeRust", "unwrapDoesNotAlwaysEndProcess", "futureCanBeDroppedBeforeFirstPoll"]:
        assert proofs[key]["run"]["exitCode"] == 0, key

    result = {"date": "2026-10-27", "scope": "Read-only content audit; no publication or curriculum correction",
              "appRepositoryCommit": run(["git", "rev-parse", "HEAD"], ROOT)["stdout"].strip(),
              "authoringCommit": run(["git", "rev-parse", "HEAD"], course_repo)["stdout"].strip(),
              "websiteSnapshotSourceCommit": snapshot["sourceCommit"],
              "snapshotSHA256": hashlib.sha256((ROOT / "site/content/courses.json").read_bytes()).hexdigest(),
              "rustc": run(["rustc", "--version"])["stdout"].strip(),
              "structural": structural, "independentAnswers": answers,
              "atlas": {"patterns": sum(map(len, sketches.values())), "uniqueSketches": len(sketches),
                        "sketchGroups": [{"code": code, "patterns": ids} for code, ids in sketches.items()],
                        "questionTemplates": dict(question_texts), "distinctTrimmedInputsPerChallenge": dict(unique_cases),
                        "lessonsWithGenericTraceInstruction": sum(
                            any('Apply one legal update' in step['detail'] for step in lesson['depth']['traceSteps'])
                            for course, _, lesson in rows if course['id'] == 'algorithms')},
              "rustExamples": {"total": len(rust_examples), "counts": dict(Counter(r["status"] for r in rust_examples)), "rows": rust_examples},
              "counterexamples": proofs}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"structural": structural,
                      "independentAnswers": {k:v for k,v in answers.items() if k != "notIndependentlyComputed"},
                      "rustExampleCounts": result["rustExamples"]["counts"],
                      "counterexamples": len(proofs), "report": str(args.output)}, indent=2))


if __name__ == "__main__":
    main()
