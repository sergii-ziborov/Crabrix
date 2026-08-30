# Crabrix 1.0 build 1 — known release-gate limits

This evidence set is intentionally fail-closed. A missing physical result is
recorded as pending, never inferred from simulator coverage.

## Proven in this candidate

- The complete iOS simulator suite passes: 315/315 tests, with no runtime warnings.
- A signed, optimized arm64 Release build for an iPhone 13 mini succeeds and installs.
- A physical iPhone 13 mini Release compiler gate produces E0502 in 9.2 seconds.
- A regression gate proves Stop releases the compiler worker and re-enables Run.
- The bundled `rustc.wasm`, sysroot manifest and privacy manifests are present in the signed app.
- Pure-compute interruption, output/storage/memory/table quotas and immediate next-guest behavior have automated coverage.
- Durable project identity/storage, stale-revision rejection, Cargo lock modes, archive boundaries, lesson evidence and idempotent progress have automated coverage.

## Still blocking a production release claim

- The installed Release build still needs the full repeated Run/Stop runtime matrix.
- The required five-class physical-device matrix, thermal and low-power evidence is incomplete.
- `Vendor & Edit` / project-local package overlay is not yet complete.
- Archive extraction is bounded and atomic, but streaming extraction and the fuzz/differential corpora remain incomplete.
- The Crabrix Board server-side signed event ledger, attestation, replay defense and moderation are not implemented; production UI is dormant behind a release flag.
- Game Center production provisioning/catalog verification is incomplete; production authentication UI is dormant behind a release flag.
- Branch protection, required remote checks, signed production tags and immutable App Store source archive require repository/release administration.

No existing iPhone, iPad, local compiler, Cargo, Academy, gamification,
one-time-purchase or board implementation has been removed to reach this state.
