# Compiler performance investigation — October 24, 2026

This is research after the shipped 1.1.2 (75) feature release. The release app remains on runtime `0689cc5`; the `codex/compiler-speed-20261024` branch tests `c462814` with an explicitly injected experimental dispatcher. Production construction still uses token dispatch. Native layout rules are unchanged.

## Physical baseline

A signed Release host on iPhone 13 mini freshly compiled a UUID-marked Rust web generator in **7.348 seconds**. The test including output assertions took 7.394 seconds. This does not meet or measure the separate large-project target.

Tokio 1.54.1 (`rt`, `sync`, `time`, `io-util`, default features off) was prepared and reopened frozen, then compiled from uncached dependency artifacts. `bytes` took approximately 63 seconds and `pin-project-lite` approximately five seconds. The test reached Tokio and exceeded its **240-second test bound**. There was no successful result, and increasing that bound would not be an optimization.

## Large-project target

The acceptance workload is [Kameo actors](benchmarks/kameo-actors/README.md), with a committed Cargo.lock and checked output. Its published core has an inspected upstream reference of about 20,400 source lines; the selected graph has 32 packages. The native macOS driver passes. General procedural macros remain an unmet compiler requirement, so no iPhone success or 30-second claim is made for this workload.

## Direct dispatcher repair

On the same optimized Xcode 27.1 RC toolchain, the old Clang-imported inline C entry reproduced signal 11. Moving that calling-convention transition into an external C implementation made memory traps, fuel exhaustion and recovery work. The expanded gate passed 19 tests including **179 WebAssembly core/Crabrix instruction scripts**, plus cancellation and committed-memory bounds.

Four process-cold std/BTreeMap compilations produced identical output hashes. Token measured 6.575/8.675 seconds, experimental direct 7.525/6.549 seconds: overlapping ranges, without evidence for a general speedup. A separate `bytes` phase probe measured 23.892 seconds with token and 20.363 seconds with direct; one pair is insufficient for a device claim. Its largest observed costs were type checking and MIR borrow checking, rather than final machine-code emission.

## Compiler-binary experiment

Binaryen 133 completed a bounded local-pass rewrite (`optimize-instructions`, `simplify-locals-nonesting`, `vacuum`, `strip-debug`) in 87.75 seconds. The compiler shrank from 129,350,419 to 81,597,943 bytes. Input SHA256: `0286dc52064283ef78ba153a554d86ae742e6c8cd638aea8662e07d3529233fc`; experimental output: `e5d7d53561a923c9d72da93e5ab0474e91ed567355663d2d73aba988d4f85f2b`.

Four complete `bytes` builds produced the same rlib SHA256 with original and transformed compilers. Host wall times varied substantially under other native build activity; an owned native compiler was briefly paused during the third sample and resumed. These observations cannot establish a reproducible speedup. Much of the file-size saving is debug information which the production parser already discards. The transformed compiler has not replaced the signed production artifact.

A subsequent bounded Binaryen `-O2` pass completed in 167.65 seconds with
2.17 GB peak observed RSS. Its 74,407,134-byte candidate has SHA256
`40da31c069c57c2d69a3d35575699b173364650881258594166820226bb0d6ff`.
Four matched `bytes` compilations produced identical rlibs. Metered guest work
fell by **8.684%**, but host wall times did not demonstrate a speedup: original
17.637/15.324 s, candidate 18.475/16.370 s. This remains an experiment; see the
[complete samples](performance/2026-10-24-binaryen-o2.json).

A separate `-Ccodegen-units=1` probe reduced metered `bytes` work by only about
0.1%; a single faster wall time is insufficient evidence for changing this
flag. Production invocation flags are unchanged by these probes.

## Incremental compilation blocker

Invoking the bundled compiler with a private `-Cincremental` directory fails before compilation: **“file locks not supported on this platform.”** It then exits through the compiler's fatal-abort path. Supporting a persistent incremental cache requires real locking/lifetime and invalidation behavior in the WASI host/compiler contract. Silently bypassing locks or declaring a cache hit to be a fresh compilation would not address the requested target.

Local logs and result bundles are under `build/compiler-optimization-20261024/` and `build/web-preview-20261024/`; no user project is sent to a remote compiler. Device experimental results are recorded separately from this baseline when available.

## Rebuild profile finding

The locked source selects upstream `profile = "compiler"`, whose contributor defaults explicitly enable debug assertions/logging and frame pointers and disable LTO. The root's `rust.debug = false` does not cancel these independently set fields. The toolchain repository now has a candidate-only `--performance-profile` path on branch `codex/compiler-performance-profile-20261024` (commit `b728d6b`), with recorded raw profile/default merges and explicit overrides. Locked production rebuild behavior remains unchanged. This is a prepared recipe, not a rebuilt or timed compiler artifact.

The controlled builder requires Linux x86_64, 8 GiB RAM and 30 GiB free disk. No old source or build snapshots were deleted to satisfy the resource gate.

## Active Run scheduling and separate compiler build

Explicit Run operations now request `userInitiated` QoS on the existing serial
compiler queue. Background checks retain `utility`. This does not move guest
execution to the main actor or guarantee a particular CPU core. The new physical
gate checks effective worker QoS, main-actor heartbeats and actual program output.
Its signed Release test host builds successfully. Device execution is pending
the unlock preflight; there is no timing claim for this change yet.

The toolchain repository's `5b2f3d0` adds a separate **compiler-only macOS
candidate** recipe so an ephemeral Xcode Cloud Mac can build the optimized WASI
compiler without the local disk constraint. Inputs remain pinned: Rust source,
four patches, source stage0 manifest and native WASI SDK SHA-256. It builds stage
2 rustc with Cranelift and the explicit performance profile, after building a
same-source native stage1 compiler with external LLVM 22.1.8. This experiment
does not change the controlled Linux production recipe or package a new sysroot.

The app's manual **Compiler performance candidate (manual)** workflow
(`dacd787e-9b39-45b8-9776-03b4de0aa930`) has one test action and no automatic
triggers, archives or distribution. The generated compiler is copied only into
the XCTest resource bundle. A dedicated test retains compiler/provenance
attachments, verifies their digest and requires compilation, execution, checked
wide-integer operations and E0502 diagnostics with the signed target sysroot.
Cloud's correctness test uses its normal Debug host; iPhone performance must
subsequently use the Release host. These are prepared gates, not evidence of a
successful compiler rebuild or device speedup.

### First physical experimental result

The selected Release device run completed three tests on iPhone 13 mini with
explicit experimental-direct dispatch and interactive worker QoS 25. The fresh
responsiveness program completed in **1.875 s**; the observed first 1.5-second
main-actor heartbeat's largest gap was **53.47 ms**. The gate was subsequently
extended to cover the entire compilation. A fresh web generator completed in
**1.799 s**. A fresh root plus uncached Tokio compilation completed in
**62.385 s**, with verified `tokio offline: 42` output. `bytes` and
`pin-project-lite` were already cached: this is not a complete cold graph, not
the Kameo workload, and not a controlled attribution between QoS and dispatch.

Manual Cloud run 76 reached bootstrap and failed because cross-target std may
not be compiled by stage0. The recipe now requests stage2, building a same-source
native stage1 first. No local-rebuild or compatibility check was bypassed.

The next physical comparison allocates a fresh dependency-artifact directory
for **each** token/direct run and asserts that no dependency is cached. Source
archives remain pinned and resolution is frozen. The real app cache is retained.
The same test session holds the phone awake across both runs; network preparation
is outside the measured compiler duration. This gate is prepared, not yet a
completed cold-graph measurement.

## Upstream audit

The upstream `riw-wasm20` head was checked on October 24:
`cc6954e02cb99b83a66805a51717c6920915113a` is one commit ahead of the pinned
`abc48c0b8ab`, changing only `compiler/rustc_codegen_cranelift/clif2wasm/README.md`.
There is no functional compiler update to import from that branch. The pinned
source and four existing arithmetic/ABI patches remain the controlled input.
