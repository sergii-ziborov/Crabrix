# Measured Rust performance example

The standard-library-only classifier and benchmark driver used in the
27 October 2026 Crabrix article. Eight semantic/differential tests pass in
both development and Release profiles with Rust 1.99.0.

From this directory, run:

```sh
cargo test --locked
cargo test --locked --release
cargo run --locked --example measure > debug.csv
cargo run --locked --release --example measure > release.csv
```

Both paths scan the same 405,000-byte fixture: 24,000 lines, 9,000 warnings.
The driver prepares the fixture, checks answers and warms both paths before
measuring 21 batches per variant. A batch includes 32 scans, loop/dispatch
and optimizer barriers; collection and printing are outside the interval.
Order alternates AB/BA. This is reused-input native timing, with no allocations
or resident-memory counters, and no cold-I/O or single-request latency claim.

The full driver and fixture are included; Cargo has no external dependencies.
Desktop measurements do not qualify any timing on iPhone or Crabrix's WASI VM.

[Recorded process runs and raw samples](../../benchmarks/measured-performance-2026-10-27/measurements.json).
