# Source-built compiler candidate gate

This is a test-only path for a marked Crabrix toolchain candidate. It keeps
`Crabrix/Resources/toolchain.lock.json` pinned to the verified external release
until a separately signed, verified Crabrix release passes the acceptance gates.
The test app is unsigned and targets iOS Simulator; it must never be submitted
or used as a production archive.

## Build the test host

On the app branch containing the candidate gates, build the optimized test host:

```sh
xcodebuild build-for-testing \
  -project Crabrix.xcodeproj -scheme CrabrixCompilerGate \
  -configuration Release \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath /tmp/CrabrixOwnToolchainReleaseGate -jobs 2 \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES \
  OTHER_SWIFT_FLAGS='$(inherited) -DCRABRIX_LEGACY_FIXTURES' \
  CODE_SIGNING_ALLOWED=NO
```

`-enable-testing` is needed by `@testable import Crabrix`. The legacy fixture
flag lets parity tests compile in this **test-only** Release configuration;
normal Release builds omit those Swift catalogs. `OTHER_SWIFT_FLAGS` preserves
dependency-defined flags such as Swift System's Darwin condition. A local
build-for-testing and a baseline `test-without-building` manifest/hash test
passed on 1 October 2026. These checks do not test the new compiler.

## Stage and run

Once `crabrix-toolchain/scripts/stage-candidate.sh` has produced and verified
`work/candidate-artifacts`, point the staging command at those files and at the
fresh build products:

```sh
products=/tmp/CrabrixOwnToolchainReleaseGate/Build/Products
python3 scripts/stage_candidate_toolchain_for_simulator.py \
  --candidate-dir /path/to/crabrix-toolchain/work/candidate-artifacts \
  --app-bundle "$products/Release-iphonesimulator/Crabrix.app" \
  --xctestrun "$products/CrabrixCompilerGate_iphonesimulator27.0-arm64.xctestrun"
```

The script verifies the candidate marker, artifact SHA-256 values, Wasm
header, every sysroot ZIP entry and its app manifest, then writes candidate
identity and hashes only inside the built `.app`. It creates a separate
`-candidate.xctestrun` with the heavy-crate opt-in environment variable.
Seven staging unit tests passed, including tampering, traversal, a malformed
checksum sidecar, a wrong test host and signed-bundle rejection. The first
source-built candidate reached this test path on 1 October 2026.

Use `scripts/run_candidate_gate.py` with the generated candidate test-run
file and exact test identifiers. It writes a temporary single-selection
`xctestrun` and rejects Xcode's possible green result with zero executed tests:

```sh
python3 scripts/run_candidate_gate.py \
  --xctestrun "$products/CrabrixCompilerGate_iphonesimulator27.0-arm64-candidate.xctestrun" \
  --destination 'platform=iOS Simulator,id=<SIMULATOR-UDID>' \
  --result-bundle /tmp/crabrix-candidate-e0502.xcresult \
  --test 'BundledCompilerGateTests/testBundledRustcProducesE0502()'
```

First run the
release-manifest hash test, a fresh E0502 Check/repair, the direct i128 and
float-to-i128 regressions, all 46 installed Academy Examples, the three-file
four-crate apps, and the Clap/Regex/JSON CLI.
The generated xctestrun adds these opt-in probes to the scheme's fixed test
selection; setting the environment variable alone would leave them filtered
out. The runner requires the requested number of actually executed tests.
Then run the remaining compiler/Cargo/Stop/Vendor/offline gates and performance
probes. Record every observed pass, failure, skip, compiler SHA, sysroot SHA,
runtime revision, app SHA, device/OS, and build configuration separately.
The first candidate compiler was `f8409434ef8f3e804b6842161b1aa1cb59ad9a8d8d2a7870f52ef9fc38a17090`
with sysroot ZIP `df1c69c31ce5730ff945d6aff5193a037b0ef3bad9495bbc24875dcf57b4cab3`.
On an iOS 18.2 Release Simulator, its manifest/hash test, fresh E0502 and
repair, and Check/Run for all 46 Academy Examples passed. The 46-example test
ran for 179.938 seconds. A cold three-file `clap`/`regex`/`hashbrown`/`smallvec`
app first exhausted the 100-billion compiler-host fuel budget. With 300
billion, it reached `clap_builder` codegen and failed because the source fork's
Wasm emitter lacks `smulhi.i64` lowering. A current `serde_json` probe failed
because `serde_core` needs `OUT_DIR/private.rs` from a build script, which the
Cargo subset does not execute. Those dependency-rich gates remain failed; a
new source-built backend candidate is required before repeating them.

The second source-built candidate, `61478aefaa4d26e1de217dcf427b68d09203695f9055b92689011014bcd61e16`, reused the byte-identical sysroot ZIP above. Its `checked_mul` regression passed on iOS 18.2 Release Simulator (one executed test, zero failures, 4.625 seconds), proving the former `smulhi.i64` failure was resolved for that workload. A real `smallvec` crate download/build/link/Run passed in 19.686 seconds; Vendor & Edit and offline pin rehydration passed together (2 executed, zero failures, 17.078 seconds). The four-crate CLI then failed after 515.204 seconds while emitting `regex-automata 0.4.18`: `bswap.i128` tried to use a two-word i128 as one Wasm value. A new `u128::swap_bytes()` regression reproduced the exact failure on this candidate (one executed test, one failed, 6.172 seconds). The heavy-crate gate was therefore still failed for this second candidate.

The third source-built candidate, `e7c94685d0f6cc217d57f9d1ae1d2b005ddd718f03f6ff30bfa1596730aae775`, uses the same verified sysroot ZIP. Its exact `u128::swap_bytes()` regression passed on iOS 18.2 Release Simulator (one executed, zero failed, 2.411 seconds). A separate `regex 1.13.1` dependency build/link/Run passed (one executed, zero failed, 334.623 seconds). The three-file `clap 4.5.50` + `regex 1.13.1` + `hashbrown 0.17.1` + `smallvec 1.15.1` application then passed with its exact expected output (one executed, zero failed, 284.911 seconds). Xcode installed that test in a new app data container; no prior app-local dependency artifacts were present there, although system/network caches were not independently purged.

On that same candidate, all 46 installed Academy Examples compiled and ran in 182.447 seconds. The nine-test regression selection passed with zero failures or skips in 220.904 seconds: Examples, E0502, repaired Run, a real `smallvec` crate, offline pin rehydration, root features, compile Stop, the 64 MiB user-program memory limit, and Vendor & Edit. These are completed Simulator gates for this compiler SHA, not physical-device or general crates.io compatibility claims. The `serde_json` build-script limitation remains.

A separate **candidate-only size experiment** stripped only Wasm `name` and
`.debug_*` custom sections from this third compiler. The output SHA-256 is
`5da690fe77625d55602e400ebdb0d57fb496c1f3e26d1376c1a8ef0e56e378bd`:
87,833,739 bytes versus 129,337,658 bytes for the original. `producers`,
`target_features`, and all executable sections were retained. The artifact
checksum and all 43 sysroot ZIP entries verified. On the same iOS 18.2 Release
Simulator, E0502 and the `u128::swap_bytes()` regression passed (2/2, 16.997
seconds); all 46 installed Examples passed in 160.318 seconds; and the
three-file `clap`/`regex`/`hashbrown`/`smallvec` CLI passed with exact output
in 588.873 seconds (the latter two were one 2/2, 749.191-second run). The
CLI times of 284.911 and 588.873 seconds are **not a controlled speed
comparison**: staging the second artifact changed the compiler cache identity
and forced dependency rebuilds, and network/system cache state was not held
constant.

[Two sets of five raw warning-Check observations](performance/2026-10-02-source-built-strip-simulator.json)
measured median rustc parse at 148.515 ms original versus 108.671 ms stripped
(1.37×), first Check at 838.347 versus 686.758 ms (1.22×), and changed Check
at 581.459 versus 566.800 ms (1.03×). All ten probes passed with two warnings
and unchanged-cache diagnostic parity. The run used Simulator in fixed
original-then-stripped order and did not measure thermal state, peak RSS, or
whole-app responsiveness. The release packager still uses the unstripped
compiler; the stripped artifact is only a candidate.

With the 300-billion compiler-host policy and the first source-built candidate,
the Stop gate completed in 0.666 seconds and the 64 MiB user-program memory
limit gate passed in 5.701 seconds (2 executed, 0 failures). These do not
replace the new compiler candidate's regression run.

The same runtime and Release Simulator gave the former compiler 1378.780 ms
for first Check and 666.594 ms for a changed Check; the source-built candidate
gave 1208.577 ms and 623.111 ms. These are one probe each, not a device
benchmark or a several-fold speed claim. Normal release inputs are unchanged.

The separate opt-in public delivery gate fetched the signed catalog, downloaded
the Basics and Projects/Examples archives, installed both and read all 46
Examples. It passed in 2.927 seconds on the same simulator. This checks the
remote Examples path; the 46-project compiler gate above used the signed
bundled transition pack to keep that test independent of network availability.
The public `projects` 1.0.1 entry and the bundled transition archive both have
SHA-256 `e4636c190ac7a10b7c8f2f9e2571b98f2e46b49d03fff21f03bd49567ac767aa`,
so the compiled Examples are the same archive bytes offered for download at
this catalog version.

On 2 October, a separate public fetch rechecked the signed catalog at
`https://raw.githubusercontent.com/sergii-ziborov/crabrix-courses/main/catalog.v1.json`:
the production keyring accepted sequence 2 with seven course versions. The
public Projects descriptor and ZIP downloaded successfully and matched their
catalog SHA-256 values (`15a05aba1a08ac5f576e3e088036a61a23219e30c7001463e82435ffa8de4f5e`
and the ZIP digest above). The CoursePack verifier accepted all 212 Projects
payload files. This checks the published bytes; it is separate from the
Simulator installation and compiler gates.

On 2 October the third stripped compiler and sampled-runtime fork were used
for a new three-file route-planner probe with `clap 4.5.50`, `regex 1.13.1`,
`petgraph 0.8.3`, and `itertools 0.14.0`. The first run **failed** (one executed,
four XCTest assertions failed, 173.087 seconds). Source policy rejected
`petgraph` because its published `tests/res/graph_1000n_1000e_iso.txt` is
1,999,999 bytes, above the app's former 1,500,000-byte editable-file cap.
The archive's 147 UTF-8 files total about 5.4 MB, below the unchanged 16 MB
tree cap. The candidate app now raises the per-file cap to 2 MiB, matching
the existing source-view cap. Its Release Simulator test host built successfully,
but the graph gate has not yet passed with the new limit. Independently, the
compiler reached `petgraph` codegen and failed at
`icmp_imm.i128 slt` in `core::num::overflowing_add`: the CLIF-to-Wasm emitter
tried to map a two-word i128 to one Wasm value. The next source-locked builder
patch sign-extends that immediate into two i64 halves and uses the existing
i128 comparison lowering. The next candidate's results follow.
An isolated `i128` immediate comparison and `overflowing_add` test reproduced
that exact backend error on the old stripped candidate (one executed, two
assertion failures, 4.664-second test body). This confirms the regression
test exercises the failing path before the next candidate is staged.

The fourth source-built candidate, `cbf85af252b4abcaadd1a1d740746838c733761cf11a4ce20085287a1fae9e7c`, passed that exact isolated regression on iOS 18.2 Release Simulator (one executed, zero failures, 3.480 seconds). Its sysroot ZIP remained byte-identical to the prior candidate. The route planner then compiled its dependency graph but **failed at link time** after 474.615 seconds: `riwl` found that the Cranelift object imported `__fixunssfti` as `(f32) -> (i64, i64)`, while LLVM-built `compiler_builtins` defined `(i32 return_area, f32) -> ()`. The linker correctly rejected the ABI mismatch. A fifth pinned source patch changes the four f32/f64-to-i128 library calls to the wasm32 C return-area ABI. Its new source build and gates are pending; the fourth candidate must not be described as passing the graph application.

An isolated four-conversion test (`f32/f64` to signed/unsigned `i128`) reproduced the same `__fixunssfti` link mismatch on the fourth candidate (one executed, two assertion failures, 3.887-second test body). This is the fast regression to run before repeating the eight-minute dependency graph.

The sampled runtime fork passed the prior three-file
`clap`/`regex`/`hashbrown`/`smallvec` CLI in an A/B/A Simulator comparison
against its preceding revision. [Sanitized raw phase and wall-time
observations](performance/2026-10-02-sampled-cancellation-heavy-cli-simulator.json)
record 345.835 s (sampled), 563.758 s (prior), and 351.106 s (sampled).
This is about 1.61–1.63× on that selected workload, with missing thermal,
peak-RSS and physical-device measurements. It is not a whole-app speed claim.
