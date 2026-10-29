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
https://github.com/sergii-ziborov/crabrix-runtime/tree/e714b3efb3f4973bfd20ea41cb2cf0d6eb27713d

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

### TypeScript 5.9.3

The local TypeScript checker includes the original Microsoft TypeScript compiler
and 100 standard declaration libraries from the pinned npm distribution. They
retain their upstream Apache-2.0 terms and attributions. The complete original
`LICENSE.txt` and `ThirdPartyNoticeText.txt` are bundled for offline reading in
the toolchain notice catalog. Project JavaScript and compiler plugins are not
executed by the checker.

Source and license: https://github.com/microsoft/TypeScript/tree/v5.9.3

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

### highlight.js 11.12.0

Offline web syntax grammars. Copyright Ivan Sagalaev and contributors. BSD-3-Clause.
Full license: `highlight.js-LICENSE.txt`. Source: https://github.com/highlightjs/highlight.js/tree/11.12.0
The grammar runs against source text in JavaScriptCore; user programs run only in the separate offline web preview.

## WABT wasm2c runtime 1.0.42

Copyright 2018 WebAssembly Community Group participants. Licensed under Apache License 2.0; the complete license is included in `Licenses/WABT-LICENSE.txt` and is available in Settings → Licenses.

Source: https://github.com/WebAssembly/wabt/tree/1.0.42/wasm2c

Crabrix uses wasm2c at app build time for the bundled compiler. Generated compiler C receives additional work, cancellation and native stack checkpoints. The wasm2c runtime uses explicit memory bounds checks and Crabrix's C trap scopes; no signal handler or JIT is enabled. User programs and procedural macro crates execute in the separate WasmKit sandbox.

## Offline browser build tools

### @babel/standalone 8.0.9

Copyright Babel contributors. MIT License. The bundled, unmodified standalone
compiler parses/transpiles browser JavaScript, TypeScript syntax and JSX with
fixed bundled plugins; project plugins and package lifecycle scripts are not run.
Full license: `babel-standalone-LICENSE.txt`.
Source: https://github.com/babel/babel/tree/v8.0.9/packages/babel-standalone

### node-semver 7.8.5

Copyright Isaac Z. Schlueter and contributors. ISC License. Bundled library code
selects npm registry versions; the npm CLI and Node runtime are not included.
Full license: `node-semver-LICENSE.txt`.
Source: https://github.com/npm/node-semver/tree/v7.8.5

The exact public npm archives, SRI hashes and generated runtime digest are pinned
in `scripts/web-compiler-source-lock.json`. Downloaded browser dependencies keep
their package manifests and license texts as editable project source.

## Temporary Playground collaboration

The fixed JavaScriptCore collaboration codec bundles Yjs 13.6.33, y-protocols
1.0.7, lib0 0.2.119 and isomorphic.js. Original MIT license texts are included
in Open-source licenses. User project source is data and is never evaluated by
this codec. Browser-only editor/runtime notices are available at
https://crabrix.com/licenses/PlaygroundThirdPartyNotices.txt.

## Local Rust formatting

Pinned rustfmt 1.10.0-nightly runs in WasmKit from bundled RustTools/rust_fmt.wasm. Rustfmt-NOTICE.txt contains original Rust/Scalar license texts. RustTools/RustfmtVendorNotices.zip includes the pinned registry dependency notices, original manifests and unmodified MPL option-ext sources. All can be read or exported offline from Open-source licenses. This formatter is separate from the bundled Rust compiler; it does not execute project Rust or fetch configuration.

## Native Git

libgit2 1.9.7 uses its original GPLv2 with linking exception. Its full COPYING
text is in libgit2-NOTICE.txt. GitCore/GitCoreNotices.zip retains original
dependency notices; GitCore/CrabrixGitCoreSource.zip contains the complete local
SwiftPM package, configured C sources, wrapper, tests and untouched upstream
source archive. Read notices and export corresponding source offline from
Open-source licenses. The iOS profile uses Apple SecureTransport and system
zlib/iconv; it does not run external Git processes or project hooks.

## Local Rust semantic analysis

The MIT/Apache-2.0 rust-analyzer source is pinned to the compiler's Rust source
revision abc48c0b8aba37d3f3862a9d5c76eb4e78f90e88. The local wrapper and two
documented compatibility patches compile to an import-free WebAssembly module.
The analysis library contains text from the same Rust core/alloc/std revision.
SemanticCore/SemanticVendorNotices.zip retains original notices for the complete
194-component source/build inventory, including Rust COPYRIGHT, per-file license
metadata and original LICENSES. These notices are readable offline from
Open-source licenses. User code is analysis data; the analyzer executes no
project build scripts, external procedural macros or network requests.
