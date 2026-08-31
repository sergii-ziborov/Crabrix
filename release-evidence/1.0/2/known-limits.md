# Crabrix 1.0 build 2 — known release-gate limits

Evidence for commit `adf10fb`. Every measurement here was taken from this
commit's own tree. Where a result exists only for an older commit it is named as
inherited and is not counted towards this candidate.

## Proven on this commit

- The fast release suite passes 364 XCTest cases and 7 Swift Testing cases with
  no failures, skips or runtime warnings, run on **iOS 18.2 — the minimum
  deployment target** rather than the newest available runtime.
- An unsigned Release build succeeds with no new warnings.
- A signed optimized `Release-iphoneos` build succeeds, passes strict code-sign
  verification, carries the same App Group in the app and the Share Extension,
  and has no Game Center entitlement, as the dormant feature flag requires.
- The signed product installs on a physical iPhone 13 mini.
- The bundled `rustc.wasm` and sysroot manifest inside that signed product hash
  to the pinned `artifacts-test-7` values, and the audited SwiftPM graph,
  project spec, privacy manifests and third-party notices are byte-identical to
  build 1.
- Downloaded package source is audited against the editor's complete View/Edit
  limits before `rustc` is allowed to use it, so an oversized or non-UTF-8
  source file makes the package `Unsupported` instead of compiling code the app
  cannot fully expose.
- Cargo resolution distinguishes resolver 1, 2 and 3, honours the root project's
  `rust-version`, and will not select a version that lacks a requested feature.
- All 200 Algorithm Atlas patterns verify against a private four-case harness,
  including an independently authored semantic probe.
- Rating is paid once per exact source revision, the day's run bonus is a
  separate reward, reward identities for revisions are bounded, the contribution
  baseline remembers oversized files by digest instead of forgetting them, and
  the rank ladder is scaled to the whole 742-step curriculum.

## Not measured on this commit

- The bundled compiler/sandbox suite. Its most recent full 20/20 run was on
  build 1's tree; the Algorithm Atlas harness gate was last run on `452f209`.
- Every physical-device runtime measurement: cold check timing, repeated
  check/run cycles, pure-compute stop with CPU-idle and memory observation,
  Cargo cold/warm/offline-pinned rebuilds, and Vendor & Edit on device. The
  installed build has not been exercised: the phone was locked when the
  installer asked for a launch.
- Thermal, low-power, background/foreground and memory-warning behaviour.
- iPad of any class, and a physical device running the minimum supported iOS 18.

## Still blocking a production release claim

- The available signing profile is a short-lived development profile
  (`get-task-allow=true`, expires 2026-09-03), not an App Store distribution
  archive or profile, and the production-supported Xcode toolchain is still
  required at submission time.
- The exact signed-RC reviewer walkthrough for guideline 2.5.2, and the App
  Review consultation about downloaded package source, are outstanding.
- Canonical-solution validation for all 200 Atlas patterns, and a broader
  edge/adversarial corpus, remain release gates rather than finished claims.
- A maintained differential corpus against desktop Cargo does not exist yet, so
  no claim of universal Cargo parity is made.
- Airplane-mode, cache-pressure and low-disk offline evidence is pending.
- App Store screenshots are from an older UI state and must be recaptured from
  the exact signed release candidate.
- Branch protection, required remote checks, a current default branch, a signed
  production tag and an immutable source archive require repository
  administration.

No iPhone, iPad, compiler, Cargo, Academy, Atlas, gamification or purchase
capability was removed to reach this state.
