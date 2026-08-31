# Crabrix 1.0 build 1 — known release-gate limits

This evidence set is intentionally fail-closed. A missing physical result is
recorded as pending, never inferred from simulator coverage.

## Proven in this candidate

- The release-branch hardening candidate passes 347/347 fast iOS Simulator
  tests with no failures, skips, or runtime warnings. The test run used the
  audited, locked SwiftPM graph.
- The bundled compiler/sandbox suite passes 20/20 on the same Simulator with no
  failures, skips, or runtime warnings (1537.872 seconds wall-clock).
- An unsigned Release build succeeds, contains both privacy manifests and the
  third-party notices, and bundles the expected rustc/sysroot SHA-256 values.
- The current `Release-iphoneos` candidate passes strict code-sign verification;
  app and Share Extension use the same App Group, and Game Center is absent as
  required by the dormant feature flag.
- At audit base `1b45367`, a signed optimized arm64 Release build installed on
  an iPhone 13 mini and produced E0502 in 9.2 seconds. That result is retained
  as historical physical evidence, not attributed to the current hardening
  candidate.
- A regression gate proves Stop releases the compiler worker and re-enables Run.
- The bundled `rustc.wasm`, sysroot manifest and privacy manifests are present in the signed app.
- Pure-compute interruption, output/storage/memory/table quotas and immediate next-guest behavior have automated coverage.
- Durable project identity/storage, stale-revision rejection, Cargo lock modes, archive boundaries, lesson evidence and idempotent progress have automated coverage.

## Still blocking a production release claim

- The installed Release build still needs the full repeated Run/Stop runtime matrix.
- The currently available signing profile is a short-lived development profile
  (`get-task-allow=true`, expires 2026-09-03), not an App Store distribution
  archive/profile. The current candidate also still needs installation after
  the registered iPhone becomes available again.
- The required five-class physical-device matrix, thermal and low-power evidence is incomplete.
- `Vendor & Edit`, diff/reset, patch fingerprints and a real patched link are
  automated, but the exact signed-RC reviewer walkthrough is still pending.
- Algorithm challenge verifier data is now private, but all 200 advertised
  challenges still need curated multi-case hidden/adversarial tests and a
  verified canonical solution before production release.
- Durable offline archives can rehydrate a frozen graph after cache eviction in
  automation; airplane-mode, cache-pressure and low-disk device evidence is
  still pending.
- Archive extraction is bounded and atomic, but streaming extraction and the fuzz/differential corpora remain incomplete.
- The Crabrix Board server-side signed event ledger, attestation, replay defense and moderation are not implemented; production UI is dormant behind a release flag.
- Game Center production provisioning/catalog verification is incomplete; production authentication UI is dormant behind a release flag.
- Branch protection, required remote checks, signed production tags and immutable App Store source archive require repository/release administration.
- App Store screenshots are from an older UI state and must be recaptured from
  the exact signed release candidate.

No existing iPhone, iPad, local compiler, Cargo, Academy, gamification,
one-time-purchase or board implementation has been removed to reach this state.
