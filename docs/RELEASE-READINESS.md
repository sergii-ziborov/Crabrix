# Crabrix 1.0 release readiness

- Last reviewed: 2026-09-03
- Candidate branch: `release/1.0-app-store`
- Policy: fail closed — an empty evidence field is **pending**, never inferred
  as PASS from source review or Simulator behavior.

## Current decision

**Release scope is frozen. Submission is gated on evidence, not on code.**

Every code-side release gate identified for 1.0 is closed and proven by the
suites below. What remains before `Submit for Review` is not development work:

1. a build under the production-supported Xcode toolchain (26.6), including the
   compiler gates, since the vendored WasmKit needs Swift 6.3;
2. a physical-iPhone smoke run of the exact release candidate — install, Run,
   E0502 repair, `loop {}` Stop with CPU returning to idle, a crates.io build,
   Vendor & Edit, offline pin and an airplane-mode rebuild;
3. an App Store distribution archive (`get-task-allow=false`) with matching App
   Group and privacy report;
4. screenshots recaptured from that exact candidate, and the App Store Connect
   business fields (age rating, content rights, DSA/trader, export compliance,
   pricing, review contact);
5. repository release identity: current default branch, protection, and a
   signed `v1.0.0` tag.

Do not read this as "shipped". It means the source no longer holds the release
back; the remaining gates produce evidence, and any one of them failing stops
the submission.

## Deliberately deferred past 1.0

These were considered and moved, not forgotten. None of them is a correctness
defect in what ships:

- a canonical reference solution and a wider edge/adversarial corpus for all 200
  Algorithm Atlas patterns. Every pattern already verifies against four private
  cases, including an independently authored semantic probe, and the bundled
  compiler gate runs that harness. The wider corpus is 1.0.1 QA work;
- stronger verifier isolation, so a challenge solution cannot read the private
  harness through compile-time tricks such as `include_str!`;
- extending the package source audit to executable text reached through
  `include!` from a non-`.rs` filename;
- a maintained differential corpus against desktop Cargo;
- RustSec/OSV advisory evidence on the Packages screen;
- a toolchain refresh past the pinned 1.96.0-dev.

## Changes verified in this hardening pass

- Cargo wildcard requirements such as `1.2.*` and `1.2.x` use the correct
  `<1.3.0` upper bound, with a regression matrix.
- crates.io registry source remains immutable; **Vendor & Edit** creates a
  project-local source overlay, a distinct content fingerprint, Diff, Reset,
  and a real patched dependency build.
- every extracted crate path is listed; programming source, including hidden
  paths and explicit nonstandard lib/build targets, is audited against the
  complete View/Edit contract before rustc can use it. Oversized or non-UTF-8
  source fails closed, while binary assets remain in the immutable verified tree.
- `cargo check` evidence is labelled **Check verified** and cannot be mistaken
  for stronger **Link verified** evidence.
- the root project receives `CARGO_PKG_*` values from its exact `Cargo.toml`.
- an explicit offline pin stores exact checksum-verified archives outside
  purgeable Caches and can rehydrate a frozen graph after source/archive cache
  deletion.
- Algorithm Atlas expected values and assertions are no longer present in the
  editable project. Every pattern now has an independent semantic probe plus
  two input-normalisation variants in an app-private verifier, and the bundled
  compiler gate executes that multi-case harness.
- CI definitions now contain a fast suite, an unsigned Release build, and the
  bundled-rustc/sandbox suite on GitHub's Xcode 27 runner.
- clean XcodeGen builds restore a source-controlled `Package.resolved` and
  refuse to float the audited SwiftPM graph.
- README, device gates, App Store wording, screenshot status, and reviewer notes
  describe the current binary rather than the older architecture.
- the root crate compiles with its own active features: `--cfg feature="…"` and
  `CARGO_FEATURE_…` now reach the user's own code, proven by a bundled-rustc
  gate, and the artefact cache is keyed on them.
- Game Center and the Crabrix board are compiled out of the production build.
  The Release binary links no GameKit and contains no board endpoint, and a CI
  step fails the build if either returns.
- the Build screen names the programming environment and its exact pinned
  toolchain, and the editor's share of the screen is measured at 66% on iPhone
  and 31% on iPad against the 80% limit.
- every redistributed licence and notice ships verbatim inside the app and is
  readable offline, with a test that fails if one goes missing.
- the public site, privacy policy, terms and support pages describe this binary:
  no leaderboard, no account, current project counts, one offline wording.

## Gate table

| Gate | Code/automation | Required external evidence | Status |
| --- | --- | --- | --- |
| Project durability and revision identity | ProjectStore, recovery, ProjectID, WorkspaceRevision tests | interrupted-save/update exercise on device | **PARTIAL** |
| Runtime interruption and quotas | instruction limiter, WASI cancel, memory/table/output/storage tests | five-class CPU-idle/thermal/immediate-next-Run matrix | **BLOCKED** |
| Cargo correctness | lock modes, edition, MSRV, tri-state cfg, resolver 1/2/3 semantics, requested-feature version selection, root feature cfg/env gate, SemVer wildcard tests | maintained differential corpus against desktop Cargo, deferred past 1.0 | **PARTIAL** |
| Offline durability | exact archive pin + frozen cache-eviction rehydrate gate | airplane-mode device run and low-disk behavior | **PARTIAL** |
| Package source under guideline 2.5.2 | path listing, pre-build complete View/Edit audit, oversized/non-UTF-8 fail-closed tests, Vendor & Edit, diff/reset, patched link gate | exact-RC reviewer walkthrough / consultation outcome | **PARTIAL** |
| Programming environment under the DPLA | persistent environment label with the pinned toolchain; measured 66% iPhone / 31% iPad editor share; crates.io reachable only as the open project's dependency manager | reviewer acceptance | **PARTIAL** |
| Open-source redistribution | full licence and notice texts bundled and readable offline; inventory in `release-evidence/1.0/2/dependencies.json`; missing-file test | none outstanding | **SHIPPING** |
| Rust Academy integrity | lesson-specific evidence model and structural QA | expert content sample and remaining compiler-evidence coverage | **PARTIAL** |
| Algorithm Atlas integrity | four-case private verifier for all 200 patterns; independent semantic probes; literal-answer regression; bundled-rustc harness gate | canonical-solution corpus, deliberately deferred to 1.0.1 | **SHIPPING** |
| Rating integrity | per-revision build rewards, separate daily bonus, bounded reward identities, digest-backed contribution baseline, curriculum-scaled rank ladder, split Rust/Atlas counters | long-run device economy observation before any public board | **PARTIAL** |
| Social/privacy | social compiled out of Release; binary carries no GameKit and no board endpoint; CI gate; privacy manifest says no collection | confirm the App Privacy answers against the archived RC's privacy report | **PARTIAL** |
| Signing/submission | unsigned Release and development-signed device builds pass; App/Share App Group matches | App Store distribution profile/archive, accepted Xcode/SDK, archive validation | **BLOCKED** |
| Screenshots/metadata | copy is source-controlled and corrected | recapture every frame from exact signed RC | **BLOCKED** |
| Repository discipline | workflow committed | remote checks green, branch protection, current default branch, signed tag | **BLOCKED** |

## Production tag requirements

The current bundle is `release-evidence/1.0/2/`, matching `CFBundleVersion` 2.
It separates what the candidate proves from what it does not measure, and
inherits no result from build 1. It also carries the programming-environment
area measurement and the redistributed-dependency inventory.

Do not create or push a `1.0` production tag until all of these are attached to
`release-evidence/1.0/<build>/`:

1. full fast and bundled-compiler suites, with zero unexpected skips/failures;
2. signed Release archive identity, entitlements, privacy manifests, compiler
   and sysroot hashes;
3. old/current/Pro iPhone plus base/M-series iPad physical results;
4. pure-loop Stop, CPU idle, immediate second Run, quota and repeated-run data;
5. cold, warm, frozen/offline-pinned, interrupted-download and corruption Cargo
   scenarios;
6. App Review 2.5.2 Vendor & Edit walkthrough;
7. multi-case validators and verified canonical solution for every advertised
   Algorithm Atlas challenge;
8. exact final screenshots and App Store metadata review;
9. protected source branch, green required checks, immutable source archive,
   SBOM/license inventory, and signed tag.

## Local commands

```bash
xcodebuild test \
  -project Crabrix.xcodeproj \
  -scheme Crabrix \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project Crabrix.xcodeproj \
  -scheme CrabrixCompilerGate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project Crabrix.xcodeproj \
  -scheme Crabrix \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO
```

Physical procedure: [DEVICE-GATE.md](DEVICE-GATE.md).

App Store copy and reviewer notes: [app-store/listing.md](app-store/listing.md).
