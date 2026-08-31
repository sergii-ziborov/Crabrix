# Crabrix third-party notices

Crabrix is proprietary software. The following components are not covered by
the Crabrix proprietary license and remain available under their respective
open-source licenses.

## Bundled compiler runtime and toolchain

### WasmKit 0.3.1

Copyright (c) 2020 Akio Yasui. Licensed under the MIT License.

WasmKit includes derived utility code from Swift System and a derived Swift
keyword list from Swift Syntax; both are licensed under Apache-2.0. See the
upstream `NOTICE.txt` for those attributions.

Source and license: https://github.com/swiftwasm/WasmKit/tree/0.3.1

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

These packages are resolved transitively through WasmKit. Their exact pinned
versions are recorded in `Dependencies/Package.resolved`:

- Swift Argument Parser 1.8.2 — Apache-2.0 — https://github.com/apple/swift-argument-parser
- Swift Atomics 1.3.1 — Apache-2.0 — https://github.com/apple/swift-atomics
- Swift Collections 1.6.0 — Apache-2.0 — https://github.com/apple/swift-collections
- Swift Log 1.15.0 — Apache-2.0 — https://github.com/apple/swift-log
- SwiftNIO 2.101.3 — Apache-2.0 — https://github.com/apple/swift-nio

Swift Log and SwiftNIO carry additional upstream attribution in their
respective `NOTICE.txt` files. The license and NOTICE files shipped with the
resolved source packages are authoritative; this summary does not replace
their terms.
