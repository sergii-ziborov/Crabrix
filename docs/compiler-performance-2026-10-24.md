# Compiler performance investigation — October 24, 2026

This is research after the shipped 1.1.2 (75) feature release. The release app remains on runtime `0689cc5`; the `codex/compiler-speed-20261024` branch initially tested `c462814`, then sampled-cancellation runtime `83406c2`, with an explicitly injected experimental dispatcher. Production construction still uses token dispatch. Native layout rules are unchanged.

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

The locked source selects upstream `profile = "compiler"`, whose contributor defaults explicitly enable debug assertions/logging and frame pointers and disable LTO. The root's `rust.debug = false` does not cancel these independently set fields. The toolchain repository has a candidate-only `--performance-profile` path on branch `codex/compiler-performance-profile-20261024` (initial commit `b728d6b`), with recorded raw profile/default merges and explicit overrides. Locked production rebuild behavior remains unchanged. The successful separate macOS candidate build is recorded below.

The controlled builder requires Linux x86_64, 8 GiB RAM and 30 GiB free disk. No old source or build snapshots were deleted to satisfy the resource gate.

## Active Run scheduling and separate compiler build

Explicit Run operations now request `userInitiated` QoS on the existing serial
compiler queue. Background checks retain `utility`. This does not move guest
execution to the main actor or guarantee a particular CPU core. The new physical
gate checks effective worker QoS, main-actor heartbeats and actual program output.
Its signed Release test host builds successfully. The initial physical results
and the subsequent isolated comparison are recorded below.

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
The physical comparison uses a signed Release host. Compiler artifacts are
kept in test resources and do not replace the production app compiler.

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

The physical comparison allocates a fresh dependency-artifact directory
for **each** token/direct run and asserts that no dependency is cached. Source
archives remain pinned and resolution is frozen. The real app cache is retained.
The same test session holds the phone awake across both runs; network preparation
is outside the measured compiler duration. The completed four-case measurement
is recorded below.

### Rebuilt compiler artifact

Manual Cloud run **77** built the optimized compiler in 894.50 seconds after
bootstrapping from the pinned source. Its 95,199,989-byte Wasm has SHA256
`0900e146ea3d54efb021a79165b2439d28ad67bd296a5075c4d915f6ddb353ac`.
The Test Products archive was downloaded and its embedded compiler digest and
candidate provenance verified. Both original and rebuilt compilers identify as
`rustc 1.96.0-dev`; backend labels are recorded verbatim in the
[rebuild evidence](performance/2026-10-24-rebuilt-compiler.json).

Cloud built the test host successfully but did **not** run the tests: its service
rejected iPhone 13 mini / iOS 27.1 as an unavailable destination. The manual
workflow now uses iPhone 18 Pro / iOS 27.1 from Apple's returned available list.
The downloaded artifact does not need rebuilding to test locally.

Four matched `bytes` compilations, alternating original/rebuilt/rebuilt/original,
produced bit-identical rlibs. Metered guest work fell **37.532%**. Host wall times
were 22.545/17.227 s for original and 24.899/7.931 s for rebuilt under concurrent
desktop build activity. These timings remain too variable for a general speed
claim. The signed Release device session completed the four isolated cold Tokio
cases, full-compilation UI heartbeats and the web generator. Each candidate uses
its full compiler digest as a cache namespace and an in-memory compatibility
ledger.

### Complete cold-graph iPhone comparison

On iPhone 13 mini, **iOS 26.5 (23F77)**, each case freshly compiled `bytes
1.12.1`, `pin-project-lite 0.2.17`, Tokio 1.54.1 and its UUID-marked root, then
ran the resulting program and checked `tokio offline: 42`. Every dependency
reported `wasCached: false`. Pinned source preparation was outside the timer;
resolution was frozen and no remote compiler was used.

| Compiler | Dispatcher | Compiler duration | Thermal state start → end |
| --- | --- | ---: | --- |
| Original | Token | 123.995 s | nominal → fair |
| Rebuilt | Token | 60.754 s | fair → fair |
| Rebuilt | Experimental direct | 41.692 s | fair → fair |
| Original | Experimental direct | 87.063 s | fair → serious |

These are single sequential samples, with different thermal conditions. The
result demonstrates successful offline cold builds for this selected Tokio
feature set; it does not establish a general threefold speedup. This is still
a smaller workload than the large Kameo acceptance project. A later fresh
repeat of rebuilt/direct with the same runtime took **36.680 s**, with nominal
thermal state at both ends and all three dependencies again uncached. This
variation is another reason to preserve thermal context with every sample.

The rebuilt/direct fresh responsiveness program finished in **1.244 s**; the
main-actor heartbeat covered the entire compilation and its largest observed
gap was **53.47 ms**. The Rust HTML/CSS/JS generator finished in **1.242 s** and
its generated files and execution output passed validation.

Six of seven tests passed. The seventh stopped on the original compiler's
expected fatal E0502 abort: the test assumed a nonzero exit, whereas the WASI
compiler emits the valid JSON diagnostic and traps with `unreachable`. The
corrected gate accepts only that precise trap shape and requires a parsed E0502
error with a primary span in `invalid.rs`; all other failures remain failures.
The corrected gate passed separately on the owned iOS 26.5 simulator with
optimized app/VM code, in 11.372 s, covering both compilers. The physical
iPhone rerun also passed, in 9.801 s; original/candidate compile times were
4.493/2.343 s.
The [machine-readable evidence](performance/2026-10-24-rebuilt-compiler.json)
records these limitations.

### Next candidates

A bounded Binaryen `-O2` transform of the rebuilt compiler produced a
63,890,638-byte module with SHA256
`c536ce70d4487ec08af4de4849f24456611e28d61ee1468438a8ddbcde35d45f`.
Matched `bytes` output hashes agree; measured guest work drops about 7.5%.
Host wall times still overlap substantially under concurrent desktop work, so
this is not yet a physical speed claim or a replacement for the tested artifact.

The manual compiler-only workflow's next recipe compares full LTO with the
measured ThinLTO baseline. Its dedicated `CompilerCandidate` configuration
optimizes the app and VM while leaving the XCTest driver unoptimized to reduce
test rebuild time. Production Release configuration and native UI are retained.

The large Kameo target and the 30-second physical target remain unqualified.

### Sampled cancellation fast path

Research runtime `83406c2` moves access to the Swift cancellation-probe
existential inside the existing one-in-64 sampling branch. Optimized arm64
assembly confirms that the other 63 checkpoints avoid Swift retain/release and
exclusivity calls. Installing a probe from a host function resets the sampling
position; fuel costs and bulk-operation checks stay the same.

The optimized host gate passed 16 tests, including 179 instruction scripts,
exact fuel-accounting checks, memory/fuel traps, recovery and host-installed
cancellation before the next loop-body write. Four matched `bytes` builds
produced identical rlibs. Old direct runtime wall times were 16.818/33.250 s;
new runtime 13.101/12.541 s, while other native builds were running. These are
host observations, with the CLI's nil probe. The subsequent physical gate used
the app's real cancellation probe and passed **8/8 tests**, with no skips.
Fresh cold Tokio compilation took **32.153 s** with the raw rebuilt compiler
(nominal thermal state at both ends), compared with the preceding 36.680 s
repeat on the old runtime. Both runs verified output and rejected all dependency
cache hits. The Binaryen-transformed compiler took **35.571 s**, ending in fair
thermal state; it is not selected as a demonstrated speed improvement.

The whole-compilation main-actor heartbeat's largest gap was **53.49 ms**, the
web generator completed in **1.235 s**, Stop passed in **0.294 s**, and the
64 MiB user-program memory limit was enforced. Both compiler variants passed
the signed-sysroot, execution, wide-integer and E0502 smoke gate on the phone.
The large Kameo and 30-second acceptance targets remain unmet.
See [the complete sampling evidence](performance/2026-10-25-cancellation-sampling.json).

### Outlined checkpoint and full-LTO candidate

Runtime `78aef49` outlines the sampled probe into a non-inlined helper. The
optimized direct handler's native frame shrinks from 128 to 64 bytes, with
compiler protection settings retained. The 16-test/179-script host gate passes;
matched `bytes` rlibs agree, but host time ranges overlap. A separate physical
measurement is required. See [outlining evidence](performance/2026-10-25-cancellation-outlining.json).

Manual Cloud 78 built the full-LTO compiler in **1199.96 s**, producing
79,051,505 bytes with SHA256
`8f1b313ccb59bf43546e36cfcdbd04dac9b5c8388a6ffec23efe2148564c17e6`.
Its source, patches, SDK and recipe revision were checked against provenance
after download. Four matched `bytes` builds agree bit-for-bit, while guest work
**increases 5.59%** relative to ThinLTO and host wall times still overlap. This
does not establish a speedup. Cloud built the optimized test host, but its test
service again rejected the advertised destination (now iPhone 18 Pro / iOS
27.1), so no Cloud tests ran. The downloaded artifact is preserved separately
in `ArtifactFat/` for local qualification, alongside the original candidates.
See [full-LTO evidence](performance/2026-10-25-fat-lto.json).

## Upstream audit

The upstream `riw-wasm20` head was checked on October 24:
`cc6954e02cb99b83a66805a51717c6920915113a` is one commit ahead of the pinned
`abc48c0b8ab`, changing only `compiler/rustc_codegen_cranelift/clif2wasm/README.md`.
There is no functional compiler update to import from that branch. The pinned
source and four existing arithmetic/ABI patches remain the controlled input.
