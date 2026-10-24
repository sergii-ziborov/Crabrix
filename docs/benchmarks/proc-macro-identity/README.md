# Minimal procedural-macro bridge acceptance fixture

This unchanged identity macro and its consumer are a prerequisite for a future
WASI macro loader. They are **not** the large Tokio acceptance workload.

Native macOS Cargo passed on October 25, 2026:

```sh
CARGO_TARGET_DIR=build/proc-macro-identity cargo run \
  --manifest-path docs/benchmarks/proc-macro-identity/consumer/Cargo.toml \
  --locked --offline
```

Expected output is `macro identity: 42`.

The full-LTO bundled WASI compiler rejected the same macro source, producing
no artifact: the target drops unsupported `proc-macro` crate type, and its
42-file signed target sysroot has no `proc_macro` library (E0463). This remains
a failed capability, not a passed application test.

A research probe then used that compiler and its original sysroot to build
`rustc-literal-escaper 0.0.7` and the exact pinned Rust source's `proc_macro`
library as ordinary WASI rlibs. Both compilations succeeded. An ordinary WASI binary linked against the new
library also compiled and ran, asserting that `proc_macro::is_available()` is
false outside an active macro bridge. That is the expected API behavior, not
an executed expansion. Those extra rlibs
are retained in the ignored experiment directory and have **not** been added
to the signed app sysroot. This supplies one missing library prerequisite;
accepting macro crate type, loading guests, preserving spans/hygiene through
the bridge and executing real macros remain unimplemented.

[Machine-readable evidence](../../performance/2026-10-25-proc-macro-prerequisites.json)
records hashes, source identities and the failed macro compilation. Kameo's
unchanged 32-package graph remains the separate large-project gate.
