#!/usr/bin/env python3
"""Compile and run every Rust block of the 1.100 article with rustc 1.100.0; check 1.99 rejects `!`."""
import hashlib, json, subprocess, sys, tempfile
from pathlib import Path
HERE = Path(__file__).resolve().parent
posts = json.loads((HERE.parents[2] / "site/content/posts.json").read_text())
post = next(p for p in posts if p["slug"] == "rust-1-100-never-type-dropguard-cargo-cooldowns")
tc = Path.home() / ".rustup/toolchains"
r100, r99 = tc / "1.100.0-aarch64-apple-darwin/bin/rustc", tc / "1.99.0-aarch64-apple-darwin/bin/rustc"
results, ok = [], True
with tempfile.TemporaryDirectory() as tmp:
    for i, s in enumerate(x for x in post["sections"] if x.get("codeLanguage") == "rust"):
        src = Path(tmp) / f"block{i}.rs"; src.write_text(s["code"]); exe = Path(tmp) / f"block{i}"
        edition = "2021" if "never-type fallback" in s["code"] else "2024"
        c = subprocess.run([str(r100), "--edition", edition, str(src), "-o", str(exe)], capture_output=True, text=True)
        run = subprocess.run([str(exe)], capture_output=True, text=True) if c.returncode == 0 else None
        row = {"section": s["heading"], "sha256": hashlib.sha256(s["code"].encode()).hexdigest(), "edition": edition,
               "compiled": c.returncode == 0, "stderr": c.stderr, "exit": run.returncode if run else None,
               "stdout": run.stdout if run else None}
        ok &= row["compiled"] and row["exit"] == 0 and not c.stderr.strip()
        results.append(row)
    never = next(x["code"] for x in post["sections"] if "type Error = !" in (x.get("code") or ""))
    src = Path(tmp) / "never99.rs"; src.write_text(never)
    c99 = subprocess.run([str(r99), "--edition", "2021", str(src), "-o", str(Path(tmp) / "n99")], capture_output=True, text=True)
    old = {"rustc": subprocess.run([str(r99), "-V"], capture_output=True, text=True).stdout.strip(),
           "rejected": c99.returncode != 0, "E0658": "E0658" in c99.stderr}
    ok &= old["rejected"] and old["E0658"]
out = {"rustc": subprocess.run([str(r100), "-V"], capture_output=True, text=True).stdout.strip(),
       "host": "aarch64-apple-darwin", "blocks": results, "rust199NeverType": old, "passed": bool(ok)}
(HERE / "example-verification.json").write_text(json.dumps(out, indent=2) + "\n")
print(json.dumps({"passed": out["passed"], "blocks": len(results), "rust199": old}))
sys.exit(0 if ok else 1)
