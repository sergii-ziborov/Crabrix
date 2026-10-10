# Crabrix third-party notices

Crabrix is proprietary software. The following components are not covered by
the Crabrix proprietary license and remain available under their respective
open-source licenses.

## Bundled compiler runtime and toolchain

### CrabrixRuntime, derived from WasmKit 0.4.1

Copyright (c) 2020 Akio Yasui. Licensed under the MIT License.

WasmKit includes derived utility code from Swift System and a derived Swift
keyword list from Swift Syntax; both are licensed under Apache-2.0. See the
upstream `NOTICE.txt` for those attributions.

Upstream source and license: https://github.com/swiftwasm/WasmKit/tree/0.4.1

Crabrix fork and patch history:
https://github.com/sergii-ziborov/crabrix-runtime/tree/d996f0d11dff54734b5670d58062e22c6e01f949

### Crabrix source-built Rust toolchain

The build recipe is a fork of AngelOnFira/wasm-rustc. Copyright (c) 2026
Forest Anderson. The builder recipe remains under the MIT License. The
compiler, sysroot and their dependencies retain separate licenses.

Source, lock, licenses and release notices:
https://github.com/sergii-ziborov/crabrix-toolchain/releases/tag/toolchain-2026-10-02.1

Builder upstream and license: https://github.com/AngelOnFira/wasm-rustc

### Rust compiler and standard library

Copyright (c) The Rust Project Contributors. Except where otherwise noted,
Rust is offered under Apache-2.0 or MIT terms, at the recipient's option.
Rust binary distributions also contain separately attributed third-party
materials. This source-built release publishes a `vendor-notices.zip`
inventory of its exact vendored crates and their notice texts.

Copyright and license sources:

- https://github.com/rust-lang/rust/blob/main/COPYRIGHT
- https://github.com/rust-lang/rust/blob/main/LICENSE-APACHE
- https://github.com/rust-lang/rust/blob/main/LICENSE-MIT

## Direct Swift package dependencies

### ZIPFoundation 0.9.20

Copyright (c) 2017-2025 Thomas Zoechling. Licensed under the MIT License.

Source and license: https://github.com/weichsel/ZIPFoundation/tree/0.9.20

### Swift System 1.8.1

Licensed under Apache-2.0.

Source and license: https://github.com/apple/swift-system/tree/1.8.1

## Transitive Swift package dependencies

The selected app targets resolve the following packages through the runtime.
Exact versions and the fork revision are recorded in
`Dependencies/Package.resolved`:

- Swift Argument Parser 1.8.2 — Apache-2.0 — https://github.com/apple/swift-argument-parser
- Swift Syntax 604.0.0 — Apache-2.0 — https://github.com/swiftlang/swift-syntax

## Where the full texts are

This page is a summary. Primary license and notice texts are bundled inside
the app and readable with no network:

**Settings → About Crabrix → Open-source licenses → any component.**

They are also in this repository under `Crabrix/Resources/Licenses/`.
The exact primary and vendored toolchain notice archives are also bundled
in the app under Compiler and sysroot dependency notices. The searchable
index includes all 1,592 source packages, including build-time dependencies.
The original archives and their provenance remain public assets of the pinned
toolchain release linked above. Website copies are at https://crabrix.com/licenses/. This summary does not
replace any component's terms.
