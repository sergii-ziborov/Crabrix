# Native compiler candidate: qualification in progress

This is a development record, not a released-device performance claim.

- Two independent source builds, Cloud 85 and 86, produced the identical compiler SHA-256 `00fd7be5c8799c59707ea2c3dd1d5826c8c667d368843c9598019322fd608889` and matching complete source-built sysroots.
- Both WASM compilers translated into identical generated C/header inventories with pinned WABT 1.0.42. Source archive SHA-256: `2a7613b3691a039faeec6f080d3643bb37a78c397d9d2b8bd0e80e99354fc92e`.
- The repaired interpreter path passed four initial candidate/macro gates, including an unchanged identity macro and real `serde_derive`.
- The full Kameo graph exposed Cargo's missing implicit `--extern proc_macro`. The app now supplies that argument without editing package sources or stripping features; full graph acceptance is being rerun.
- Runtime revision `e714b3efb3f4973bfd20ea41cb2cf0d6eb27713d` passed 25 selected tests covering RPC, reserved memory, WASI input ranges and interruptible host polling.
- The native C wrapper passed hostile mock-module checks for work exhaustion, cancellation, OOB, nested traps, stack margin, the 2 GiB memory ceiling and repeated teardown. These are wrapper checks, not a real-project benchmark.
- Ordinary simulator builds use the WASM compiler; the subsequent opt-in native simulator run is recorded below.

The large-project 30-second iPhone goal and the native Axum measurement are **not yet established**. Promoting this experimental compiler to a production input requires the remaining real-device gates; app builds 87/88 were delivered separately with the existing signed compiler. The existing offline WebKit features and device layout code are retained.

## Subsequent evidence

The complete unchanged Kameo graph compiled all 31 dependency crates and linked the root under the WASM interpreter, including all five macro crates. Its program then trapped during execution; the previous error wrapper discarded the panic text. The app now preserves that text and reports the Run phase, with a passing panic regression test. The failed Kameo run remains recorded and is not a functional acceptance.

The guarded native compiler completed a real arm64 iOS SDK build. Static library SHA-256: `5a513c830b7fba5c21a021893a608f9e537ea3299a3cdab813f6bd1a5108d8ef`. Its source and binary packages are retained in a draft GitHub prerelease. They are not enabled in App Store/TestFlight build 87. Native integration is explicitly compiled only with `CRABRIX_NATIVE_COMPILER`; real iPhone acceptance remains pending.

Build 87 instead ships the checked arm64 interpreter improvements, offline web lab, 2,048-package resolver ceiling and preserved runtime panic diagnostics. It passed 67 selected Release Simulator gates and was submitted for App Review.

## Simulator follow-up while the phone is unavailable

The physical-device test wait was stopped at the user's request. Build 87 remains valid in TestFlight's Internal QA group and selected on the App Store version waiting for review.

- The macro-enabled WASM compiler passed the Axum 0.8.9/Tower/Tokio cold router gate on the simulator: 22 dependency crates, HTTP 200 with the expected body, **126.113 seconds** for compilation and execution. This is in-memory request routing, not a TCP listener or an iPhone timing.
- Re-running the Kameo test exposed a qualification defect: its private dependency cache did not isolate the root-program cache. A previously linked program could be reused without dependency callbacks. That run's 0.064-second duration is **not a cold build measurement**. The test factory now isolates both caches and asserts that every planned dependency produced progress.
- The corrected isolated cold run compiled all 31 units and linked the unchanged root, then failed with the same `ActorNotRunning`. Its **245.902 seconds** is recorded as a failed functional run on the simulator while other local compiler builds were active; it is not an accepted benchmark. The separate token-interpreter compiler control also compiled every unit and failed identically (**328.775 seconds**). This does not identify the software-direct dispatch path alone as the cause.
- Comparing the planned feature sets with ordinary Cargo metadata found an independent resolver gap: strong `optional/feature` forwarding activated the dependency but omitted its public feature name. Local Cargo controls confirmed implicit, hidden `dep:`, explicit and explicit-with-`dep:` cases. The resolver now expands that public feature when Cargo does; it preserves suppression of genuinely hidden implicit features. A regression test covers the four cases. The missing `futures-executor` feature name is not asserted to explain the Kameo failure.
- The preserved Kameo WASM prints `record: ActorNotRunning` in both WasmKit and independently installed Wasmtime 50.0.1. The identical source and lockfile succeed with ordinary Rust 1.99.0 on macOS and when compiled by that compiler for WASI and executed in Wasmtime. This narrows investigation to the candidate's produced program or build inputs; it does not establish a WasmKit-only runtime defect.
- A simulator native library is being compiled for `arm64-apple-ios18.0-simulator` with its real SDK. The helper now verifies executable native ABI symbols in addition to the platform record. The real iOS archive is explicitly rejected for simulator linking. A normal simulator app continues to use the WASM backend unless the separate test-only native flags and a verified library are supplied.

Simulator results cannot satisfy the physical iPhone performance gate. No native candidate is promoted by this follow-up alone.

## Completed simulator native run and narrow-atomic diagnosis

The explicit `arm64-apple-ios18.0-simulator` library built successfully; its SHA-256 is `81defcd3c586ee597dbd1ba0bc1b9b2c27435e132d06d6ac0d20f0dff3b302fb`. It is a test-only static translation of compiler `00fd7be5c8799c59707ea2c3dd1d5826c8c667d368843c9598019322fd608889`, not a release input.

- The native Axum 0.8.9/Tower/Tokio router completed a cold 22-dependency compile and run in **24.397 seconds**, returning the expected HTTP 200 response. This remains a simulator in-memory request, not an iPhone TCP server measurement.
- Identity and real Serde derive macros passed. Offline Rust web generation and the main-actor responsiveness gate passed; the observed maximum main-actor scheduling gap was **0.0535 seconds**.
- The unchanged 31-dependency Kameo workload compiled in **49.303 seconds** and still failed at runtime with `ActorNotRunning`. It is not a functional pass or a sub-30-second result.
- The initial Stop test's tiny program finished in 33 ms, before its scheduled cancellation. The test now waits for compilation of an intentionally nonterminating const evaluation before cancelling. Native Stop passed twice (0.607 and 0.639 seconds for the entire test case). The ordinary selected Release simulator regression then passed **69 tests**, with no failures or skips.
- The startup diagnostic narrowed the Kameo failure to an `AtomicBool::new(false)` read returning true beside other data. Inspection found that `clif2wasm` used the mapped i32 local type to select 32-bit atomic memory operations for CLIF i8/i16. This reads and can overwrite neighboring fields. Signed narrow atomic min/max comparisons also lacked sign extension.
- The backend correction selects 8-, 16-, 32- or 64-bit memory operations from the original CLIF type. An executable backend regression uses nonzero neighboring canaries across loads, stores, compare/exchange and all eleven RMW operations. The original backend fails its first i8 load; the corrected backend passes **1,420 checks** in Wasmtime. [Exact regression evidence](2026-10-25-atomic-widths.json).

The full compiler must still be rebuilt from the corrected source and pass the unchanged Kameo and macro gates. These backend tests alone do not prove that Kameo is fixed or establish an iPhone performance claim. App Store/TestFlight **1.1.2 (88)** was separately delivered with the verified Cargo resolver correction; it does not bundle this experimental compiler.

## Optional polling experiment while the corrected compiler rebuilds

A separate source-generation option retains checkpoints on function entry and backward edges, omitting forward-only branches. Every cycle within a generated function has a backward edge; recursive cycles enter a function. The parser rejects changed function boundaries, unknown targets and unfamiliar native loop syntax. Three tests, including compiled C budget exhaustion for loops and recursion, passed. The default remains the prior all-branches policy until the new option is benchmarked.

Across all 64 existing generated kernel files, the experiment retains **188,147** static checks (60,368 entries and 127,779 backward edges) and removes 1,925,034 forward-edge checks. Re-emitting the original all-branches policy matched every old generated function byte for byte. These are static code counts, not a runtime speedup, and they do not qualify the earlier compiler that failed Kameo.

Two fresh corrected-compiler source builds were manually started from app driver `3222691a3ef96025dc14de5dcd685172ba563a35`: Cloud **89** (`eb73637a-1c11-4d19-b178-f4a8666ed50f`) and **90** (`f719833d-1fe2-4a94-82a3-29dd3d4e34f9`). Both bind the atomic-corrected recipe `0a5970c97ef0e192c8f6e5dec460190924489f97`. They are compiler qualification runs, separate from TestFlight build 88.

## Corrected full compiler: functional simulator acceptance

Cloud 89 and 90 produced identical corrected compiler `27acccf94e1f4083b311b352164fe1a310077c76f4cd3e221a2ee26b02309008`, identical source-built sysroot archives and identical inventories. Both raw records passed the exact source-profile checks. Their subsequent Cloud device tests were not executed: Xcode Cloud rejected the configured iPhone 18 Pro/iOS 27.1 destination. The manual-only workflow now selects iPhone 17 Pro; that new Cloud destination still needs a future run.

The verified compiler and complete source-built sysroot were staged only into a local optimized simulator test bundle. With the WASM software-direct backend, all **5 selected tests passed, with no failures or skips**: packed atomic canaries, input/sysroot binding, real Serde derive, unchanged identity macro, and the unchanged full Kameo/Tokio gate. The Kameo program now prints the expected 16-actor/1,024-record result instead of `ActorNotRunning`. All 31 dependencies compiled cold; after changing the root, every dependency was correctly reused.

The cold Kameo compile/run took **238.315 seconds**; changed-root compile/run with dependencies cached took **7.164 seconds**. The Serde test case took 98.576 seconds. These are interpreter-path simulator observations while the native kernel was being compiled, not an iPhone or native-accelerator performance claim.

Both new compilers translated into identical C inventories with optional function/backedge polling. The new kernel has 188,148 static checkpoints; matching source archive SHA-256 is `6a28c35e6f70a1cf2ba422ec68ae5bbe8abd5b550523c502f3e52c3e5d0bc760`. Its real simulator SDK build is in progress. Native performance, Stop and full runtime acceptance remain pending. [Exact functional evidence](2026-10-25-atomic-compiler-simulator.json).

## Corrected native kernel: ten simulator gates passed

The corrected C kernel completed its actual arm64 simulator build. The first
archive write ran out of local disk space; the resumed build verified and reused
the completed object files and produced archive
`3dd44c63a234bad2799005f732944707d3dcf686b75049e9f34b18c38f5b75de`.
The resume's 1.845-second script duration is not a full C compilation time.

The optimized test driver from app source `521601ac54133c141db27e208a78475060e2b106`
required the native compiler backend and passed **10 tests, 0 failures, 0 skips**:
packed atomic canaries, exact compiler/sysroot binding, identity and real Serde
macros, program panic diagnostics, unchanged Kameo/Tokio cold and changed-root
runs, Axum, Stop, main-actor responsiveness and offline Rust web generation.

The full unchanged Kameo workload produced the expected actor result. Its
31-dependency cold compile/run took **40.436 seconds**; a changed root with all
31 dependencies cached took **0.950 seconds**. The 22-dependency Axum in-memory
router compile/run took **13.601 seconds**, and real Serde derive took
**10.034 seconds**. Stop's entire test case passed in 0.889 seconds; the maximum
observed main-actor scheduling gap was 0.0534 seconds. These compiler timings
exclude prior package preparation; the corresponding full test cases include
setup. All measurements are from one simulator batch.

This establishes functional acceptance of the corrected native candidate on
the simulator. It does not establish the large-project 30-second objective or
physical-iPhone qualification. The source archive and distinct build-origin
provenance are retained with verified hashes; redundant generated C directories
were archived after the tests to recover disk space. Production build 92 retains
the existing signed compiler and does not enable this candidate. Promotion and
physical-device checks remain outstanding.
[Exact native simulator evidence](2026-10-25-atomic-native-simulator.json).

## Explicit O2 experiment: functional pass, no accepted speedup

The same verified C inventory was separately compiled with an explicit `-O2`
override, retaining all bounds, stack, work and Stop checks. The helper records
that override in the compile provenance and cache identity; its default remains
the original source recipe. The actual wrapper passed hostile mock checks at O2,
and the simulator passed all ten functional gates with no failures or skips.

On the shared Mac, the two O2 cold Kameo samples took **34.096 and 43.050 seconds**;
the subsequent O1 control from the same app source took **31.101 seconds**. Axum
took 31.377 then 21.275 seconds with O2 and **20.990 seconds** with O1. These
successive samples show substantial variation and establish no O2 advantage.
The O2 kernel is retained as an experimental artifact and is not promoted.
The previous O1 recipe and shipping build 93 remain unchanged.
[Exact comparison](2026-10-25-native-o2-simulator.json).

## Function-entry stack-probe experiment and sub-30 simulator samples

A separate optional policy retains all 188,148 work checkpoints and the same
Stop polling frequency, but probes the native stack only at the 60,369 guest
function entries. It rejects dynamic native stack allocation and unfamiliar
array bounds. Both independently generated C inventories match; source archive
SHA-256 is `f84d09244721f76791ef00ea95a7e89792c237c52fdc1e653efe07df67c8f256`.
Five unit tests and both entry/loop variants of the actual trap wrapper passed.

The simulator passed all ten real-project gates without failures or skips.
Cold Kameo compile/run samples took **24.182 and 23.062 seconds**; Axum took
10.774 and 13.425 seconds. The subsequent original-kernel control, with stack
probes retained at every checkpoint, took **19.480 seconds** for Kameo and
12.332 seconds for Axum. All batches used the same app source and unchanged
fixtures. Shared-host variation prevents attributing the difference to this
policy, and the original control is faster. The original guarded O1 kernel
is therefore retained; neither optional experiment is promoted.

These are successful sub-30-second simulator observations with downloaded
package inputs and empty build caches. They are not physical-iPhone timings.
A real `iphoneos` arm64 archive of the selected original kernel is now being
compiled separately; simulator objects are never relabelled for device use.
Production signing and build 93 remain unchanged.
[Exact comparison](2026-10-26-native-entry-stack-simulator.json).
