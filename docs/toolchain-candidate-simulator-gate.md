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
release-manifest hash test, a fresh E0502 Check/repair, all 46 installed
Academy Examples, the three-file four-crate app, and the Clap/Regex/JSON CLI.
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
