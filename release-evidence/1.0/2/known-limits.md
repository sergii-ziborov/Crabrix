# Crabrix 1.0 build 2 — known release-gate limits

Evidence for the 1.0 (2) candidate on `release/1.0-app-store`. Every measurement
here was taken from this candidate's own tree. Where a result exists only for an
older commit it is named as inherited and is not counted.

## Proven on this candidate

- The fast release suite passes 370 XCTest cases and 7 Swift Testing cases with
  no failures, skips or runtime warnings, run on **iOS 18.2 — the minimum
  deployment target** rather than the newest available runtime.
- The complete bundled compiler and sandbox suite passes **21 of 21** in 838
  seconds on the same iOS 18.2 simulator: real rustc diagnostics and repair,
  root feature flags, the Atlas harness, a real crates.io package compiled and
  linked, a vendored patch, an offline pin rehydrating after cache eviction,
  Stop freeing the Run gate, and the sandbox limits.
- An unsigned Release build succeeds with no new warnings.
- **A real App Store distribution artefact exists.** `build/export/Crabrix.ipa`
  is signed `Apple Distribution: Serhii Ziborov (XMS5ZC28UJ)` — app and Share
  Extension alike — with `get-task-allow=false`, a matching App Group, and an
  `iOS Team Store Provisioning Profile` carrying zero provisioned devices. It
  reports `1.0 (2)`, `MinimumOSVersion 18.0`,
  `ITSAppUsesNonExemptEncryption=false`, both privacy manifests, 15 licence
  files and the bundled toolchain, and links no GameKit. It has deliberately not
  been uploaded.
- The root crate is compiled with its own active features. A bundled-rustc gate
  proves `#[cfg(feature = "fancy")]` and `env!("CARGO_FEATURE_FANCY")` behave as
  Cargo specifies, and the artefact cache is keyed on the feature set.
- Cargo resolution distinguishes resolver 1, 2 and 3, honours the root project's
  `rust-version`, and will not select a version that lacks a requested feature.
- Downloaded package source is audited against the editor's complete View/Edit
  limits before `rustc` is allowed to use it, so an oversized or non-UTF-8
  source file makes the package `Unsupported` instead of compiling code the app
  cannot fully expose.
- Game Center and the Crabrix board are **not in the production binary**. The
  archived app links no GameKit, contains no `crabrix.com/api` string and no
  Game Center symbols; a CI step fails the build if any of them returns.
- The Build screen carries a persistent `RUST PROGRAMMING ENVIRONMENT` label
  with the pinned toolchain beside it, and the source editor measures 66% of the
  screen on iPhone and 31% on iPad in its most editor-heavy state, against the
  80% limit. Screenshots and the calculation are in `programming-environment/`.
- Every redistributed licence and notice ships verbatim inside the app: 15 files
  in the archived bundle, readable offline, with a test that fails if one goes
  missing. The inventory is in `dependencies.json`.
- All 200 Algorithm Atlas patterns verify against a private four-case harness,
  including an independently authored semantic probe.
- Rating is paid once per exact source revision, the day's run bonus is a
  separate reward, revision identities are bounded, the contribution baseline
  remembers oversized files by digest, and the rank ladder is scaled to the
  whole 742-step curriculum.
- The archived bundle carries both privacy manifests, the pinned
  `rustc.wasm`/sysroot, `MinimumOSVersion` 18.0, and
  `ITSAppUsesNonExemptEncryption = false`.
- The public site, privacy policy, terms and support pages describe this binary:
  no leaderboard, no account, current counts, one offline wording.

## Not measured on this candidate

- Every physical-device runtime measurement: cold check timing, repeated
  check/run cycles, pure-compute stop with CPU-idle and memory observation,
  Cargo cold/warm/offline-pinned rebuilds, and Vendor & Edit on device.
- Thermal, low-power, background/foreground and memory-warning behaviour.
- iPad hardware of any class, and a physical device running the minimum
  supported iOS 18.

## Still blocking a production submission

- **Production toolchain.** The vendored WasmKit needs Swift 6.3, so the
  submission build has to run under Xcode 26.6. Only Xcode 27 beta is installed
  on this machine, which is TestFlight-eligible but not App Store-eligible.
- **Physical smoke of the exact candidate**, per `docs/DEVICE-GATE.md`.
- **App Store Connect business fields**: age rating, content rights, DSA/trader
  declaration, export compliance, pricing and availability, review contact.
- **Repository release identity**: a current default branch, branch protection
  with required checks, and a signed `v1.0.0` tag.

## Deliberately deferred, not forgotten

A canonical reference solution and a wider edge/adversarial corpus for all 200
Atlas patterns; stronger verifier isolation; `include!`-reached source in the
package audit; a differential corpus against desktop Cargo; RustSec/OSV advisory
evidence; and a toolchain refresh past 1.96.0-dev. None of these is a
correctness defect in what ships.

No iPhone, iPad, compiler, Cargo, Academy, Atlas, gamification or purchase
capability was removed to reach this state.
