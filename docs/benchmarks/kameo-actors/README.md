# Large Tokio compiler acceptance workload

This driver compiles and exercises **Kameo 0.22.2**, rather than substituting a standalone timer example for a large project. The inspected upstream revision is [`1b6bffb6d0fdc05492349c08cd3727621a810ed7`](https://github.com/tqwewe/kameo/tree/1b6bffb6d0fdc05492349c08cd3727621a810ed7). Its `src/` contains 27 Rust files and 20,404 lines; the repository contains 74 Rust files and 30,129 lines. These are source-line counts, including comments, not measured compilation work.

The actual build input is the published, checksum-pinned crate in `Cargo.lock`. An inspected Git revision is not evidence that its bytes match a published archive. The selected normal/build dependency graph has 32 packages. Kameo is licensed MIT OR Apache-2.0; see its upstream notices and each dependency’s own license.

## Operation and correctness

A current-thread Tokio runtime starts 16 independent Kameo actors. Workers send 1,024 checked request/reply messages, yield cooperatively, read final snapshots, shut actors down gracefully, and join under a five-second **program execution** deadline. This does not require a TCP listener, cloud service, OS subprocess, or multithreaded runtime. Default Kameo macros and tracing remain enabled.

Expected output:

```text
kameo offline: actors=16 records=1024 sum=523776
```

After fetching dependencies once:

```sh
cargo run --manifest-path docs/benchmarks/kameo-actors/Cargo.toml --locked --offline
```

The native macOS driver passed on October 24, 2026. Native Cargo’s observed 48.86-second initial debug build is **not** an iPhone/WasmKit measurement.

## iPhone acceptance target

The requested target is at most 30 seconds from the local compiler invocation to the verified output on the physical iPhone. Report these cases separately:

1. Prepared, frozen source archives; no compiled dependency or root artifacts.
2. Compiled dependencies retained; a changed root source forces a fresh application compilation.
3. Unchanged root artifact reuse, reported only as a cache hit.

Network acquisition precedes these timings and must be reported separately. A timeout, refused package, reduced dependency graph, or merely reaching code generation does not pass the gate. Preserve the lockfile, toolchain identity, selected features and device model with every result.

## Current compatibility gap

The selected graph includes `futures-macro`, `kameo_macros`, `serde_derive`, `tokio-macros` and `tracing-attributes`. The currently released Crabrix compiler does not support loading general procedural macro libraries. This workload therefore remains an **unmet acceptance target**, not a claim that Kameo already builds or runs in Crabrix. Removing these macros or replacing Kameo with a small Tokio-only example would test a different workload.

### Upstream macro-support audit, October 25

A newer upstream unstable `-Zwasm-proc-macros` flag exists, but its
[introducing commit](https://github.com/rust-lang/rust/commit/6408d389fc3b43e4710a318b991c93014bd6cc8d)
explicitly describes partial compiler/bootstrap support. The inspected main
metadata path still obtains clients through the host dylib loader. This is
not an available WASI runtime implementation to enable in our older compiler.
Watt also needs a macro wrapper and ABI; converting published macros to it
would change this acceptance workload. The loader and span/hygiene bridge
remain engineering work. [Audit evidence](../../performance/2026-10-25-proc-macro-upstream.json)
records the inspected source hashes and limitations.
