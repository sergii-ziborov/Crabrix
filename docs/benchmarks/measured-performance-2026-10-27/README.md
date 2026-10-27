# Desktop classifier observations — 27 October 2026

These are the actual observations referenced by the Rust performance article.
See `measurements.json` for Rust/target/OS, input identity, timing scope,
per-process medians and descriptive quartiles. Each CSV retains all 21 batch
observations for each variant, with total nanoseconds and 32 scans per batch.

One development process and three Release processes ran sequentially after
both binaries were built. No benchmark commands ran concurrently with each
other. The Mac was shared; background load, thermals and CPU frequency were
not controlled. No samples were removed. The input is deterministic and reused.
There is no claim of cold I/O, measured allocation counts, production latency,
statistical confidence or qualified iPhone performance.

[Exact sample and functional tests](../../examples/measured-performance/README.md).
