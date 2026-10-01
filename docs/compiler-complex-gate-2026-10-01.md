# Compiler checks with real crates — 2026-10-01

This is a record of opt-in iOS Simulator tests against the bundled compiler in the app build. It is not a general claim that every crates.io package builds. The app still uses the pinned external compiler artifact while the source-built Crabrix toolchain is being prepared.

## Environment

- Crabrix app source: this branch based on `0214f0fd35d76024efa263d99acbc77c91c77f20` (1.1 build 9).
- Runtime: the exact `crabrix-runtime` revision pinned by `project.yml` (`fbe46d9` prefix).
- Device: iOS 18.2 arm64 Simulator; Release configuration.
- Network dependency resolution was enabled for the cold crate tests. The resolved source archives and lockfile were checked before compile.

## Observed results

| Workload | Result | Evidence |
| --- | --- | --- |
| 26 guided multi-file Academy examples | Passed | `testEveryGuidedShowcasePassesBundledRustcCheck`, 22.388 s |
| `hashbrown` 0.17.1 real registry source | Passed | `testHashbrownFromDeviceReportResolvesAndRuns`, 45.176 s |
| `smallvec` real registry source | Passed | `testResolvesDownloadsAndLinksARealCratesIOPackage`, 9.505 s |
| `regex` 1.13.1 with default features plus `serde_json` 1.0.151 | Failed during dependency compile | `aho-corasick` 1.1.5: backend reported `uextend.i16 ... unimplemented` |
| `regex` 1.13.1 with `std` and `unicode` (default features disabled) plus `serde_json` 1.0.151 | Failed during dependency compile | 100 billion instruction compiler-host budget was exhausted; at 500 billion, `regex-automata` reported `ireduce i16 -> i8 unimplemented` |
| `hashbrown` 0.17.1 + `smallvec` 1.15.1 + `serde_json` 1.0.151 application | Failed during dependency compile | `itoa` 1.x reported `ireduce i16 -> i8 unimplemented` before the root application ran |
| `clap` 4.5.50 + `regex` 1.13.1 + `serde_json` 1.0.151 CLI | Failed on the old compiler in a separate test-only Release Simulator run | The graph resolved, downloaded and planned at least ten units; `anstream` 0.6.21 then failed after 61.567 s with `ireduce i16 -> i8 unimplemented`. Existing failures for `aho-corasick` 1.1.5 and `itoa` 1.0.18 were reported by the old compiler's compatibility ledger. App test input `70b8abf`, runtime `fbe46d9`, old `rustc.wasm` SHA-256 `41412081eefc3e08ec5664ed0748902a7e575e1f267898dcc64d412702df7e83`. |

The host now reports the actual compiler stop reason instead of labeling every `WasmExecutionCancelled` as a user stop. The 500-billion-fuel run was diagnostic only; the shipped compiler-host limit remains 100 billion because this graph still fails in code generation, and no passing workload established a reason to raise the limit. The user-program budget was not changed. A failed dependency remains a visible compatibility limit until the pinned toolchain/backend is fixed and the same gate passes.

`testMultiCrateCollectionsAndJSONApplicationBuildsAndRuns`, `testRegexAndJSONLogAnalyzerBuildsAndRuns`, `testMultiFileDependencyRichLogMonitorBuildsAndRuns`, and `testClapRegexJSONCommandLineAppBuildsAndRuns` are retained as opt-in compatibility probes. The third combines four external crates with a three-file Rust application and an exact output assertion. The fourth uses the published, non-yanked `clap` 4.5.50 (registry minimum Rust 1.74), `regex`, and `serde_json` to exercise a larger CLI dependency graph. These probes are excluded from the passing compiler scheme until the toolchain backend is fixed. Run them with both `CRABRIX_RUN_COMPILER_GATE=1` and `CRABRIX_RUN_UNSUPPORTED_CRATE_PROBE=1`, then record actual passes before promoting them. The three-file gate has not run; the Clap gate has only the **failed old-toolchain baseline** above. A new toolchain changes the Cargo fingerprint and must prove these graphs afresh. The current compiler's supported Cargo subset includes the separately passed crates above but does not include these `regex`/`serde_json` graphs.
