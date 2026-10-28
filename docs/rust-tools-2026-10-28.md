# Local Rust tools — stage 2 candidate

This work is newer than App Review build **1.1.3 (111)**. It is not in that
signed build. Qualification and a subsequent signed delivery are separate gates.

## User tests

The bundled WASI sysroot includes real `libtest`. Crabrix compiles a separate
test artifact using `rustc --test -Zpanic_abort_tests -Cpanic=abort`. Discovery
uses the harness JSON listing. Each selected test runs in a fresh single-threaded
WASM guest, reusing the compiled artifact. A failed assertion/panic can abort that
guest; later tests still run. The ordinary `main` is not run.

Commands:

```text
cargo test
cargo test name_filter
cargo test --lib
cargo test --bin MyBinary name_filter
cargo test -- --list
cargo fmt
cargo fmt --check
rustfmt src/main.rs
```

This is the **selected-entry unit-test profile**, not a complete Cargo executor.
Normal dependencies must be available through the existing supported package
profile. Integration targets, independent dev-dependencies, doctests, custom
harnesses and additional harness arguments are unsupported. Ignored tests are
skipped. `#[should_panic]` cannot be validated by this panic-abort harness and is
reported as **unsupported**, never passed. Unsupported flags are rejected.

Output lists passed, failed, skipped, unsupported, canceled and not-run cases;
compile errors remain compiler errors. A source button opens the actual available
test declaration, without claiming an exact assertion position. Per-test stdout,
stderr and raw harness output remain available within bounded capture limits.
The profile supports up to 256 discovered tests, a 120-second execution-suite
budget, a 4 MiB report budget and 64 KiB per captured field. The terminal summary
is limited to 256 KiB; individual bounded details remain in Output.

Stop interrupts the active guest. A source change invalidates the report and
rejects stale results. User tests do not complete Academy lessons, award rating,
or replace the ordinary last Build/Run record. No compiler runs on a backend.

## Formatting

Real **rustfmt 1.10.0-nightly / Rust 1.100.0** is bundled as a WASI reactor,
separate from the project compiler. Source and recipe are pinned to
[Scalar formatters 2d82e248](https://github.com/scalar/formatters/tree/2d82e2487968175b844ca84fa57d51ddc0f95d97),
using Rust source `1303417c416e1595173d9689e7394c31e136ae95`.
Artifact SHA-256:
`a3d4f84da1d32de38d2c2805db86ceb293ed2547b18bdcb87214e41bc2db6eee`.

File and project actions live in existing Project settings. Project format
excludes `vendor`, `node_modules`, `target`, `.build`, `.git` and `.crabrix`
subtrees. Files are formatted in a private temporary directory; the formatter
does not execute user Rust, discover host configuration, or access the network.
Edition follows Cargo.toml (2015/2018/2021/2024). One root `rustfmt.toml` or
`.rustfmt.toml` is accepted. Simultaneous config files are rejected.

Supported scalar keys: `edition`, `style_edition`, `max_width`, `hard_tabs`,
`tab_spaces`, `newline_style`, `use_small_heuristics`, `fn_call_width`,
`struct_lit_width`, `struct_variant_width`, `array_width`, `chain_width`,
`single_line_if_else_max_width`, `single_line_let_else_max_width`,
`use_field_init_shorthand`, `use_try_shorthand`, `reorder_imports`,
`reorder_modules`. Unknown keys, invalid values or a conflicting edition fail
with the original source intact. Nested module discovery is disabled; owned
files are selected and processed explicitly.

All results are applied together only when the complete original revision still
matches and the resulting local/Shared file budgets pass. Check mode never
changes source. Parse errors and Stop keep source intact. Native editor Undo
restores the exact previous selected text and selection; **Undo formatting** in
Project settings restores the entire formatted tree while its revision still
matches. Further user/remote edits invalidate that action. Formatting may move
line-based breakpoints, so affected existing positions are explicitly called out.

The worker has a 128 MiB memory cap, 15-second per-file deadline, bounded fuel,
64 KiB diagnostics and the existing 2 MiB source/output limit. It runs on its
own background queue. Project/Duo/editor geometry is not changed by these tools.

## Redistributed source and notices

`RustTools/manifest.json` pins the artifact and notices hashes. The archive holds
all 233 registry packages in the pinned formatter/compiler dependency closure,
including build-time packages, with original manifests and available notices.
Unmodified MPL `option-ext` source files are included. Supplemental original
wasi-libc notices have their own recorded upstream revision: the WASM artifact
does **not** identify its wasi-libc source revision. These are not presented as
an exact dependency version claim. Notices can be read/exported offline.
`python3 scripts/verify_rust_tools.py` verifies this inventory.

## Qualification

35 native cases passed on iPad Simulator, covering the actual WASM tools,
transactional source checks, native Undo/Redo, terminal parsing, offline license
reading and keyboard layout. Two UI flows passed on each phone/iPad Simulator:
phone typing + Test/Format/Undo, iPad resource Debug + Test/Format/Undo. The latter
includes the actual generated offline JavaScript preview after breakpoint/step.
Logs, captures and xcresults are under `build/rust-tools-20261028/`. A final
nine-case rerun passed after the error-path isolation changes. Physical-device
performance is not claimed.
