# Precision review and senior coverage — 6 November 2026

The corpus contains 771 lessons/steps (171 Rust readings and 600 Atlas steps),
plus the separate Examples gallery. This pass does not certify every lesson as
production training or claim that all senior topics are covered.

Twelve existing readings were corrected without changing IDs, answer positions,
compiler checks or project starters. [the exact change list](https://github.com/sergii-ziborov/crabrix-courses/blob/main/editorial/senior_20261106/changed.json) lists their new pack versions.
The changes distinguish optimized test builds from ordinary release builds,
static dispatch from a zero-cost guarantee, Copy from cheapness and deep Clone,
local drop order from field order, closure capture from Send/static requirements,
associated types per implementation, disconnected channels from empty channels,
owned futures from spawned task handles, and target-specific C layout from a
complete FFI safety contract. Six generated diagrams track the new text; custom
artwork is retained.

Primary references:

- [Test configuration](https://doc.rust-lang.org/reference/conditional-compilation.html#test)
- [Destructor ordering](https://doc.rust-lang.org/reference/destructors.html)
- [Thread spawn requirements](https://doc.rust-lang.org/std/thread/fn.spawn.html)
- [Tokio JoinHandle ownership](https://docs.rs/tokio/latest/tokio/task/struct.JoinHandle.html)
- [Copy semantics](https://doc.rust-lang.org/std/marker/trait.Copy.html)
- [Type representation](https://doc.rust-lang.org/reference/type-layout.html)

## Reproduce the checks

```sh
python3 editorial/senior_20261106/verify.py
python3 -m unittest discover -s tests
python3 tools/coursepack.py validate --courses courses --schema schemas
```

Seven executable semantic checks passed: local/field cleanup order, associated
types on two trait instantiations, Fn after move and borrowing static data into
a thread, large Copy arrays, draining a disconnected channel, an Rc capture
rejected by Send bounds, optimized tests retaining cfg(test), and Tokio handle
detach versus abort. Some checks deliberately combine related assertions.
The existing 28 corpus/package tests passed. These are desktop compiler results,
not a fresh native/browser runtime qualification; existing runtime limits remain.
The unchanged worked snippets include contextual fragments as well as complete
programs. They are not all advertised as independently runnable mains.

## Senior engineering depth still needed

This is an editorial assessment of depth, not a universal senior job specification.
Existing titles alone do not close these gaps. Build substantive worked examples,
an observable failure case and an independent assessment for each next unit.

| Priority | Existing foundation | Missing depth and concrete assessment |
| --- | --- | --- |
| P1 | API boundaries, traits, PhantomData, interview API design | SemVer/MSRV/feature compatibility, variance and HRTB/GAT tradeoffs. Evolve a library while compiling an unchanged downstream consumer under supported feature sets. |
| P1 | Unsafe, raw pointers, layout, FFI | Safe-wrapper soundness obligations, MaybeUninit initialization and partial cleanup, provenance and unwind/allocator contracts. Audit a small FFI buffer handle and test length, ownership and failure paths; use Miri where supported. |
| P1 | Cancellation, JoinSet, semaphore, shutdown | End-to-end task ownership with deadlines, cancellation-safe state transitions and bounded shutdown. Stop a worker at each await and prove which effects can be retried without duplication. |
| P1 | Atomics intro and interview atomics | Acquire/release publication, ordering arguments and model exploration. Explain a happens-before chain and show a broken alternative with Loom; do not require everyone to invent a lock-free container. |
| P1 | Typed errors, reliability, interview transactions | One service capstone: request limits, tracing, pooled database transactions, migration failure, idempotency, retry budget/jitter and shutdown. Exercise overload and partial failure; label host-only infrastructure honestly. |
| P2 | Performance and profiling interview | Criterion methodology, allocation and flamegraph evidence, realistic throughput/tail latency and data-layout tradeoffs. Submit a reproducible before/after report, not a claim that syntax is inherently fast. |
| P2 | Dependencies, features, Cargo profiles | Supply-chain and reproducibility: build.rs/proc-macro trust, advisory/license review, lockfile and CI feature/target matrices. Diagnose a feature-unification or MSRV regression in a downstream fixture. |
| Role-specific | Introductory C ABI/FFI | C/C++ integration with opaque handles, bindgen/cxx and callback ownership; target-specific native build/link tests. Embedded/no_std, GPU and kernel work are separate specializations. |

The next work should deepen these contracts rather than adding shallow topic cards
or claiming that networking/database tooling runs in the browser WASI profile.
