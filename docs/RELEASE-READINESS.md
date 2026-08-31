# Crabrix 1.0 release readiness

- Last reviewed: 2026-08-31
- Candidate branch: `release/1.0-app-store`
- Policy: fail closed — an empty evidence field is **pending**, never inferred
  as PASS from source review or Simulator behavior.

## Current decision

**Production App Store release: BLOCKED**

The current source is a strong TestFlight/release candidate, but it is not yet
eligible for a production tag. The remaining blockers require device,
curriculum, repository, signing, or App Store evidence that cannot be replaced
by a successful local build.

## Changes verified in this hardening pass

- Cargo wildcard requirements such as `1.2.*` and `1.2.x` use the correct
  `<1.3.0` upper bound, with a regression matrix.
- crates.io registry source remains immutable; **Vendor & Edit** creates a
  project-local source overlay, a distinct content fingerprint, Diff, Reset,
  and a real patched dependency build.
- textual downloaded crate source, including hidden paths, is viewable and
  vendorable; binary assets remain in the immutable verified tree.
- `cargo check` evidence is labelled **Check verified** and cannot be mistaken
  for stronger **Link verified** evidence.
- the root project receives `CARGO_PKG_*` values from its exact `Cargo.toml`.
- an explicit offline pin stores exact checksum-verified archives outside
  purgeable Caches and can rehydrate a frozen graph after source/archive cache
  deletion.
- Algorithm Atlas expected values and assertions are no longer present in the
  editable project. Crabrix injects an app-private verifier at compilation.
- CI definitions now contain a fast suite, an unsigned Release build, and the
  bundled-rustc/sandbox suite on GitHub's Xcode 27 runner.
- clean XcodeGen builds restore a source-controlled `Package.resolved` and
  refuse to float the audited SwiftPM graph.
- README, device gates, App Store wording, screenshot status, and reviewer notes
  describe the current binary rather than the older architecture.

## Gate table

| Gate | Code/automation | Required external evidence | Status |
| --- | --- | --- | --- |
| Project durability and revision identity | ProjectStore, recovery, ProjectID, WorkspaceRevision tests | interrupted-save/update exercise on device | **PARTIAL** |
| Runtime interruption and quotas | instruction limiter, WASI cancel, memory/table/output/storage tests | five-class CPU-idle/thermal/immediate-next-Run matrix | **BLOCKED** |
| Cargo correctness | lock modes, edition, MSRV, tri-state cfg, feature errors, SemVer wildcard tests | maintained differential corpus against desktop Cargo | **PARTIAL** |
| Offline durability | exact archive pin + frozen cache-eviction rehydrate gate | airplane-mode device run and low-disk behavior | **PARTIAL** |
| Package source under guideline 2.5.2 | view, Vendor & Edit, diff/reset, patched link gate | exact-RC reviewer walkthrough / consultation outcome | **PARTIAL** |
| Rust Academy integrity | lesson-specific evidence model and structural QA | expert content sample and remaining compiler-evidence coverage | **PARTIAL** |
| Algorithm Atlas integrity | private verifier; literal starter-answer regression | real multi-case hidden/adversarial bank and canonical solution for all 200 patterns | **BLOCKED** |
| Social/privacy | boards dormant; privacy manifest says no collection | verify production flags and App Privacy answers in archived RC | **PARTIAL** |
| Signing/submission | unsigned Release and development-signed device builds pass; App/Share App Group matches | App Store distribution profile/archive, accepted Xcode/SDK, archive validation | **BLOCKED** |
| Screenshots/metadata | copy is source-controlled and corrected | recapture every frame from exact signed RC | **BLOCKED** |
| Repository discipline | workflow committed | remote checks green, branch protection, current default branch, signed tag | **BLOCKED** |

## Production tag requirements

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
