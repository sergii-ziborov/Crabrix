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
Six staging unit tests passed, including tampering, traversal, a wrong test
host and signed-bundle rejection. A real candidate has **not yet** reached
this step.

Use `xcodebuild test-without-building` with the generated candidate test-run
file and explicit `-only-testing:CrabrixTests/...` selectors. First run the
release-manifest hash test, a fresh E0502 Check/repair, all 46 installed
Academy Examples, the three-file four-crate app, and the Clap/Regex/JSON CLI.
The generated xctestrun adds these opt-in probes to the scheme's fixed test
selection; setting the environment variable alone would leave them filtered
out. Always inspect the XCTest result for executed test counts, not only an
overall green result.
Then run the remaining compiler/Cargo/Stop/Vendor/offline gates and performance
probes. Record every observed pass, failure, skip, compiler SHA, sysroot SHA,
runtime revision, app SHA, device/OS, and build configuration separately.
The `xcodebuild test-without-building` mechanism was smoke-tested against the
baseline app; candidate results remain pending.
