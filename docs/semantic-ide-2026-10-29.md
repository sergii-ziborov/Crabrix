# Local Rust symbols — candidate qualification

This is **unreleased source work**, not part of 1.1.3 (115) selected for review.
The full roadmap remains in [the audit](roadmap/audit-2026-10-29.md).

The candidate embeds rust-analyzer from the exact public Rust compiler source
revision `abc48c0b8aba37d3f3862a9d5c76eb4e78f90e88`. Two documented compatibility
patches allow public ABI crate visibility with the pinned build compiler and
POSIX virtual paths on import-free Wasm. The app executes the analyzer in a
background WebKit Worker. Project code is data; analysis uses no backend, native
process, external procedural macro or project build-script execution.

## Supported operations

Rust symbols are available from Project settings and the native text-selection
menu: definitions, references within owned project files, type/documentation,
call signature, actual-type completion with import resolution, and semantic
rename. Library/dependency definitions open as read-only text. Imports and
rename require a preview of every exact edit, then the unchanged full workspace
revision. A generation check also rejects edit→restore ABA races. Applied
changes can be undone across the complete tree through Project settings while
that resulting revision is still current. Saving uses the ordinary atomic
project store and Shared path.

Source context in the preview is a bounded convenience view. The exact edit
list remains visible separately; each individual edit is limited to 4 KiB.
The broader edit budget is 4,096 edits and 8 MiB inserted text.

## Analysis profile

The root edition, features and prepared Cargo graph are used with the bundled
wasm32-wasip1 target. Up to 252 dependency crates plus the root are supported.
Sources are bounded to 2,048 Rust files, 1 MiB per file and 8 MiB including
prepared dependencies. Dependency file sizes and the accumulating budget are
checked before each bounded read; oversized crates are not first loaded in full.
Pinned core/alloc/std contribute another 1,011 text files.
Auxiliary sysroot crates are not loaded. Generated-source/build-script graphs,
external proc macros, virtual workspace selection, symlinks and unavailable
prepared dependency source receive explicit unavailable messages. Analysis
never prepares packages implicitly. Compiler Check remains independent.

The Wasm module has **no host imports** and a **256 MiB memory maximum**. Native
document loading and analysis requests have a 15-second deadline. Stop, closing, backgrounding
and source changes cancel the inspector and release its Worker. Runtime queries
support incremental owned-file updates; the current UI uses explicit inspection
sessions, rather than a persistent background index during typing. A changed
source invalidates the open inspector before any navigation/edit can apply.

`SemanticCore/manifest.json`, the build receipt and the prebuild verifier bind
the exact module, wrapper, patches, text library and 194-component original
license inventory. Build/reproduction instructions are in
[Vendor/CrabrixSemanticCore](../Vendor/CrabrixSemanticCore/README.md).

## Evidence so far

The pinned module is 20,932,943 bytes, SHA-256
`c67132fb1ed7eced4617a6eb408c497e7c0706e6a24a55aec1c826019bdae9a5`.
Actual Wasm contract tests resolved scoped references, rename and auto-import
with 178,061,312 bytes of linear memory in that workload; this is not a general
peak-memory or physical-device benchmark.

The first integrated iPhone Simulator series passed **22 tests**, covering the
actual Worker, String/Vec/custom receiver completion, prepared dependencies and
read-only navigation, cross-file definitions, scoped rename, signature, Unicode
edits, stale apply, Stop/recovery and all offline notices. Additional complete
undo, root generated-source rejection, controller ABA and native UI checks are
being qualified. Final phone/iPad results must be recorded before delivery.
Evidence lives under `build/semantic-ide-20261028/`.
