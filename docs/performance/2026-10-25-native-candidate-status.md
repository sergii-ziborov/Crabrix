# Native compiler candidate: qualification in progress

This is a development record, not a released-device performance claim.

- Two independent source builds, Cloud 85 and 86, produced the identical compiler SHA-256 `00fd7be5c8799c59707ea2c3dd1d5826c8c667d368843c9598019322fd608889` and matching complete source-built sysroots.
- Both WASM compilers translated into identical generated C/header inventories with pinned WABT 1.0.42. Source archive SHA-256: `2a7613b3691a039faeec6f080d3643bb37a78c397d9d2b8bd0e80e99354fc92e`.
- The repaired interpreter path passed four initial candidate/macro gates, including an unchanged identity macro and real `serde_derive`.
- The full Kameo graph exposed Cargo's missing implicit `--extern proc_macro`. The app now supplies that argument without editing package sources or stripping features; full graph acceptance is being rerun.
- Runtime revision `e714b3efb3f4973bfd20ea41cb2cf0d6eb27713d` passed 25 selected tests covering RPC, reserved memory, WASI input ranges and interruptible host polling.
- The native C wrapper passed hostile mock-module checks for work exhaustion, cancellation, OOB, nested traps, stack margin, the 2 GiB memory ceiling and repeated teardown. These are wrapper checks, not a real-project benchmark.
- The app bridge builds for the simulator, where the ordinary WASM compiler remains the backend.

The large-project 30-second iPhone goal and the native Axum measurement are **not yet established**. A production compiler input, TestFlight upload and App Review submission require the remaining real-device gates. The existing offline WebKit features and device layout code are retained.

## Subsequent evidence

The complete unchanged Kameo graph compiled all 31 dependency crates and linked the root under the WASM interpreter, including all five macro crates. Its program then trapped during execution; the previous error wrapper discarded the panic text. The app now preserves that text and reports the Run phase, with a passing panic regression test. The failed Kameo run remains recorded and is not a functional acceptance.

The guarded native compiler completed a real arm64 iOS SDK build. Static library SHA-256: `5a513c830b7fba5c21a021893a608f9e537ea3299a3cdab813f6bd1a5108d8ef`. Its source and binary packages are retained in a draft GitHub prerelease. They are not enabled in App Store/TestFlight build 87. Native integration is explicitly compiled only with `CRABRIX_NATIVE_COMPILER`; real iPhone acceptance remains pending.

Build 87 instead ships the checked arm64 interpreter improvements, offline web lab, 2,048-package resolver ceiling and preserved runtime panic diagnostics. It passed 67 selected Release Simulator gates and was submitted for App Review.
