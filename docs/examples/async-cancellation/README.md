# Async cancellation article examples

The exact Rust/TOML blocks published in the 26 October 2026 Crabrix article,
plus seven contract checks. The library includes the article's full-queue test.

Run on a native Rust installation:

```sh
cargo test --locked
```

Tokio is pinned to 1.54.1. Time tests use the current-thread runtime and paused
Tokio time; these are correctness checks, not timing benchmarks. Network APIs
are not used. This native test result does not qualify the Tokio macros or
runtime for Crabrix's bundled iPhone WASI environment.
