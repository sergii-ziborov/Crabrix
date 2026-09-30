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
https://github.com/sergii-ziborov/crabrix-runtime/tree/9dc0ef77c101d2b1f1433ece34a0e47889770335

### wasm-rustc / Weblings artifacts-test-7

Copyright (c) 2026 Forest Anderson. Licensed under the MIT License.

Source and license: https://github.com/AngelOnFira/wasm-rustc/tree/artifacts-test-7

### Rust compiler and standard library

Copyright (c) The Rust Project Contributors. Except where otherwise noted,
Rust is offered under Apache-2.0 or MIT terms, at the recipient's option.
Rust binary distributions also contain separately attributed third-party
materials documented by the Rust project's generated copyright inventory.

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

This page is a summary. The complete, verbatim licence and notice files for
every component above are bundled inside the app and readable with no network:

**Settings → About Crabrix → Open-source licenses → any component.**

They are also in the repository under `Crabrix/Resources/Licenses/`. Those
files are authoritative; this summary does not replace their terms.
