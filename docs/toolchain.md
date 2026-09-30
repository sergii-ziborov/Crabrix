# Compiler toolchain

The current app input is the older pinned Weblings `artifacts-test-7` WASI compiler and sysroot. [`scripts/fetch_toolchain.sh`](../scripts/fetch_toolchain.sh) downloads those assets on the build Mac, checks their SHA-256 digests, and bundles them. The phone never downloads a compiler update. This input is a compatibility baseline for the WasmKit 0.4.1 integration.

[crabrix-toolchain](https://github.com/sergii-ziborov/crabrix-toolchain) is a public fork of the original builder recipe with exact source and bootstrap locks, validator, fetch/build/package/verify/smoke commands, notices, and reproducibility documentation. It does **not** yet provide a successful Crabrix-built `rustc.wasm` release. The matching CI LLVM archive for the selected Rust source revision returned 404, so the lock selects source LLVM instead. Its build environment image digest remains unset; release validation fails closed. No replacement digest or binary was fabricated.

A controlled Linux builder with enough RAM, CPU, and disk is required for the first clean source build, two-build comparison, artifact verification, and app integration gates. The available local Docker configuration has 2 GiB RAM and one CPU, so no full Rust/LLVM build was claimed from it. Until a source-built release passes the stated gates, the app continues to use the old verified artifact.
