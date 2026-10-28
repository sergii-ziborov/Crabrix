# Crabrix local semantic core

This wrapper builds a bounded rust-analyzer library into import-free
`wasm32-unknown-unknown`. The app runs it in an isolated WebKit Worker; Rust
project source is data. It does not run external proc macros/build scripts,
download dependencies, start native processes or send analysis to a server.

The upstream subtree and Rust core/alloc/std source are pinned to public revision
`abc48c0b8aba37d3f3862a9d5c76eb4e78f90e88`, matching the bundled compiler.
`upstream-manifest.json` records two explicit compatibility patches: public ABI
crate visibility for the build compiler, and POSIX virtual-path recognition on
the import-free Wasm target. Neither patch changes source type inference.
The supported Salsa `no_salsa_async_drops` cfg avoids native drop threads.

## Reproduce

Use the Rust source repository at the pinned commit and the Rust compiler
version in the bundled `build-receipt.json`. First prepare `stdlib.json` with
`prepare-sysroot.py --rust-source /path/to/rust --output
Crabrix/Resources/SemanticCore/stdlib.json`. Then run:

```sh
python3 Vendor/CrabrixSemanticCore/build.py \
  --rust-source /path/to/rust --work /path/to/build \
  --target-dir /path/to/cargo-target --stage
```

The pinned Cargo.lock covers the analyzer graph. Prepare original notices with
`package-notices.py`, using Cargo metadata from that graph, the pinned analyzer
source root and the pinned Rust license tree. This inventory includes all 194
source/build components, not just final code.
After changing any runtime asset, bind the receipt and verify:

```sh
python3 Vendor/CrabrixSemanticCore/stage-assets.py \
  --receipt /path/to/build/build-receipt.json
python3 scripts/verify_semantic_core.py
```

The verifier runs before app builds. It checks artifact/source/patch hashes,
the import-free module's 256 MiB memory maximum, source identity and original
license documents. Runtime assets have a separate SHA-256 check before WebKit
loads them. `candidateOnly` remains true until qualification; an artifact's
presence is not a release claim.

## Profile

- Definition, project references, hover, signature, completion, completion-import
  resolution and semantic rename use rust-analyzer's actual results.
- Own source: at most 2,048 Rust files, 1 MiB/file and 8 MiB including prepared
  dependency sources; at most 252 dependency crates plus the entry crate.
- Standard library: 1,011 pinned text files; auxiliary sysroot crates and
  external proc macros are excluded. Conditional compilation follows the bundled
  wasm32-wasip1 target, exact root/dependency features and edition.
- External proc-macro or build-script-generated source graphs are explicitly
  unavailable. Compiler Check is independent and remains authoritative.
- Changed owned files update incrementally. Graph/library changes get a fresh
  bounded heap. Closing, Stop, timeout and backgrounding release the Worker.
- Library sources are read-only. Edits require a preview and the exact original
  workspace revision, with no source-only hash shortcut across intervening edits.

Original MIT/Apache notices and Rust's per-file license metadata are in the
app's offline notice archive. The two patches and wrapper are AI-assisted work;
upstream source attribution is retained.
