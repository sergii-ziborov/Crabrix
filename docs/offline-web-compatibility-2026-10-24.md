# Offline compiler and web lab — October 24, 2026

## Release scope

Crabrix 1.1.2 adds transparent package preparation, compilation-stage history, bounded local std-only build scripts, two local web templates, an immutable offline WebKit preview, browser errors in Problems, web syntax grammars and language-aware on-device completion/advice. Native keyboard, fold, tab positioning and device header rules are preserved.

The compiler remains `crabrix-rust-2026-10-02.1`, Rust `1.96.0-dev`, wasm32-wasip1. The runtime pin is `0689cc5df8b5b3f81ac5e9675cc3c22fe1b614f3`. No project sources are sent to a remote compiler.

## October 25 compiler candidate follow-up

The previously published results below describe the original signed compiler and runtime. The acceleration branch now pins runtime `7d0f6718597c1a1228efca3591ae91d13c6d569b`; the following physical results used its earlier qualified core at `2b97c92215dfc7580b627c87ce718c9348898baa` and the full-LTO compiler candidate (SHA-256 `8f1b313ccb59bf43546e36cfcdbd04dac9b5c8388a6ffec23efe2148564c17e6`). Neither candidate promotion nor App Store shipment is implied.

- **Tokio 1.54.1**, defaults off, `rt,sync,time,io-util`: three cold, fully uncached dependency builds passed in **29.778 / 27.881 / 28.537 s** on iPhone 13 mini, iOS 26.5. This graph contains bytes, pin-project-lite and Tokio. It is not the large-project target.
- **Axum 0.8.9**, defaults off, Tower 0.5.2 `util`, Tokio 1.54.1 `rt`: all **22 dependencies** were uncached. The offline in-memory request returned HTTP 200 and the expected body in **126.286 s**. No TCP listener was tested. Thermal state changed from nominal to serious. A subsequent small Tokio run at serious thermal state took **31.477 s**.
- The same Axum session passed all three selected checks, including UI actor responsiveness. Highest phase-sampled physical footprint was approximately **764 MiB**; this is not a continuously measured peak. The first Axum attempt ended prematurely with no matching crash report; its root cause remains unconfirmed. The per-invocation autorelease-pool follow-up passed.
- Rust web generation, Stop, memory refusal, wide integers and borrow-checking gates also passed on the physical device with the full-LTO candidate. Offline HTML/CSS/JavaScript support remains part of the source; the compiler experiments do not replace or remove it.
- The unchanged **Kameo 0.22.2 / 32-package** graph and the **30-second large-project objective remain unmet**. The procedural-macro loader is experimental until actual unchanged macro and derive consumers pass. It is disabled in the signed production manifest.

Machine-readable [Tokio](performance/2026-10-25-direct-emission.json) and [Axum](performance/2026-10-25-axum.json) records retain exact hashes, feature sets, cache conditions and limitations.

## Observed gates

| Workload | Environment | Observed outcome |
| --- | --- | --- |
| std-only root build.rs, generated include, cfg, environment and changed input | Release iOS 26.5 Simulator | Passed; initial two-run fixture 6.815 s. Later warm gate 1.535 s. |
| Rust-generated HTML/CSS/JavaScript assets | Release iOS 26.5 Simulator | Passed; initial 1.611 s; warm 0.052 s is not a cold compiler measurement. |
| Same Rust web generator | Physical iPhone 13 mini, signed Release test host | Passed initially in 11.733 s. A UUID-marked fresh source on October 24 later measured 7.348 s compiler duration (7.394 s test). Not an app launch benchmark or a large dependency benchmark. |
| Actual WebKit local script, stylesheet, interactive counter and blocked external fetch | Release iOS 26.5 Simulator | Passed (1.262 s and final 3.382 s functional tests); timings are test durations, not compiler performance. |
| Syntax, completions, build-script directives, snapshot path/byte limits | Release iOS 26.5 Simulator | Final selected 12-test gate passed with zero failures. |
| Rust nested block comments and hashed raw strings | Host Swift/Foundation lexical gate | Passed against the production tokenizer source. |
| Tokio 1.54.1, default features off; rt, sync, time, io-util | Release Simulator | Program compiled and its timer/task/channel assertions passed in the initial 425.824 s fixture. That test failed an additional old 512-file loader guard because Tokio has 581 text files. Loader budget is now 2,048 files; existing byte budgets remain. This is not a fully green Tokio test. |
| Tokio 1.54.1 on physical iPhone | Signed Release test host | After reconnecting, frozen/offline preparation succeeded; a fresh dependency build reached Tokio after bytes (~63 s) and pin-project-lite (~5 s). The fixture exceeded its 240 s test bound. No pass or 30-second claim; large-project performance remains a separate compiler task. |
| Serde JSON 1.0.151 build script | New frozen/offline fixture | Validation pending. |
| pulldown-cmark 0.13.5 + MiniJinja 3.0.3 | New frozen/offline fixture | Validation pending. |
| Axum 0.8.9 + Tower 0.5.2 + Tokio 1.54.1, in-memory HTTP request | New frozen/offline fixture | Long Simulator run stopped; no pass claim. Does not open a TCP listener. |

Raw logs and xcresults are retained locally under `build/web-preview-20261024/` and `build/compatibility-blog-20261024/`. Exact fixture source is in `BundledCompilerGateTests.swift`. Compatibility belongs to a version, feature selection and tested operation, not to a crate name or arbitrary repository.

## Explicit boundaries

- Acquiring a previously unavailable archive needs a connection. Prepared checksum-verified archives are pinned outside purgeable caches. Frozen/offline resolution never fetches.
- Build scripts run as bounded WASI guests with read-only source and a writable OUT_DIR. cfg, check-cfg and rustc-env directives are handled. Host subprocesses, native linker directives, separate build-dependency graphs and procedural macros remain unsupported.
- There is no bundled native C/C++ toolchain, CUDA/NVIDIA runtime, OS server process or general iOS shell. These are capability requirements, not generic Rust syntax failures.
- Direct web previews execute browser JavaScript with external resources blocked. TypeScript is highlighted, not transpiled. A preview is not a Rust HTTP server.
- Preview input is bounded to 256 supported assets, 2 MiB per asset and 8 MiB total. It receives immutable bytes and no native edit or command bridge. WebKit uses a separate process; WASI guest memory/fuel/time limits do not govern JavaScript.
- Compiler workers and package actors are distinct from the UI actor. Build history is bounded to 200 events, web console messages to 128. Closing the package sheet does not cancel preparation.

## Performance interpretation

The runtime custom-section update removes about 41.5 MB of retained debug payload. Three paired host probes measured approximately 15.6 MiB lower median process-tree RSS; parser timings overlap. No complete-compiler speedup is claimed from that change. Core compiler/runtime throughput work follows this release, using identical cold inputs and explicit cache state.
