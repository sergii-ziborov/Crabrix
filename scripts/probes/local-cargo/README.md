# Released compiler / Cargo lesson gate

From the app repository root, use the pinned Node runtime to run:

```
node scripts/probes/local-cargo/gate.mjs
```

This developer harness bundles the actual `site/workers/rust.worker.ts`, not a
replacement compiler or interpreter. Five exact starter documents are read from
`CrabrixTests/CompilerCandidate/LocalCargoLessons.json`. It initializes the shipped,
SHA-pinned WASM compiler/sysroot, prepares each pinned registry graph, then denies
all fetches. Every program must pass both Run and real stepping Debug, with equal
stdout, actual pauses and exit 0. A Cargo-bearing agent job must be rejected by the
unchanged manifest-free shared execution profile.

For deterministic qualification, the fetch shim reads original `.crate` archives
and sparse index bytes from the developer's Cargo registry cache. Preparation
still validates registry SHA-256 pins; extraction, graph resolution, build scripts,
compiler and program execution use the production browser code. This is a local
CLI test, not a network compile service. The separate in-app browser check downloads
these same archives from the actual official index/CDN through the real interface.

Native gate: build the `CompilerCandidate` XCTest configuration (its application
compiler remains the released toolchain), then run `LocalCargoLessonTests` on a
compatible iOS Simulator. Set `CRABRIX_LOCAL_CARGO_FIXTURES` to a folder with the
original archives and `<crate>.index` NDJSON. The fixture uses cached-index-only
resolution and a URLSession that refuses network. New empty artifact storage proves
cold dependency compilation. Native Debug steps the same sources. The signed-pack
test separately takes `CRABRIX_LOCAL_CARGO_PACKS` and
`CRABRIX_PREVIOUS_PRACTICE_PACKS`; it verifies update installation and old session
snapshot preservation. Native simulator qualification is not a physical-device or
Safari performance claim.

Results and supported-profile limits:
[qualification](../../../docs/local-cargo-lessons-2026-11-05.md).
