# Rust debugger and browser compiler assessment — 27 October 2026

## Results

| Direction | Verified now | Remaining work |
| --- | --- | --- |
| Frontend npm commands in the iOS app | Existing browser package preparation and offline builds; follow-up aliases and preview/prefix dispatch pass hosted tests | Follow-up commands require a new app build; they are not in previously delivered build 101 |
| Rust debugger in the app | Pinned WasmKit engine's 36 debugger tests pass on the Mac | Compiler debug-info repair, Rust source/type mapping, public session API, bounded coordinator and native UI |
| Rust compiler on the website frontend | Actual pinned compiler compiles, links and runs Rust in a Chromium Worker with no compilation backend | Public editor, opt-in verified toolchain cache, resource limits and desktop/mobile browser qualification |

Bun and the production compiler/runtime pins were not changed. No debugger
controls or experimental Rust playground were added to the production app/site.
Existing Duo/iPad/editor geometry was not modified.

## Frontend npm scope

Build 101 already provides explicit `npm install` / `npm ci`, local
`npm run dev`, `npm start`, `npm run start`, and local `npm run build/check`.
These are operations of Crabrix's browser builder, not execution of arbitrary
`package.json` scripts. Imported browser source, manifests and licenses remain
editable and available offline after preparation. Run/Check do not acquire new
packages. A mixed Cargo project can use `cd web` to select its browser app.

The follow-up source adds:

- `npm i` as an alias of browser dependency preparation.
- `npm run preview` to build and open the isolated web preview.
- `npm run-script build` and the equivalent supported run-script aliases.
- `npm --prefix web install` / `npm run preview --prefix=web`, without changing
  Terminal's current directory. An explicit missing manifest does not silently
  fall back to another app. Escaping project paths and duplicate prefixes fail.

Node/server execution, arbitrary package binaries, lifecycle scripts, host
plugins, extra script arguments and `npm install <name>` remain unsupported.
Declare the dependency in `package.json`, import it, then prepare the browser
graph. No server process is started by `dev` or `preview`.

Hosted Simulator gate: **21 passed, zero failed** — seven browser integration,
11 terminal and three existing keyboard tests. Evidence:
`build/browser-packages-20261027/NpmCommandsFollowup.xcresult` and
`build/browser-packages-20261027/npm-commands-followup.log`.

## Native Rust debugger

The app pins `crabrix-runtime` revision
`e714b3efb3f4973bfd20ea41cb2cf0d6eb27713d`. Its `WasmDebuggingSupport` trait
contains instruction-address breakpoints, resume/step, call frames, locals,
globals, linear-memory reads and a GDB protocol adapter. It is an interpreter
debugger; the Rust guest is not a native process to attach LLDB to.

The engine-level API is currently package-scoped and the trait is not enabled by
the production app. Existing support is not a finished in-app Rust debugger.
Reading a numeric Wasm local is distinct from showing the Rust variable name,
type, ownership-aware value or `Vec`/`String` representation.

Ran the **actual pinned runtime**, with its default traits explicitly enabled:

```sh
swift test -c release \
  --traits FileSystem,MultiThread,Disassembler,WasmDebuggingSupport \
  --filter DebuggerTests
```

**36 tests in one suite passed**, including repeated breakpoints, stepping,
recursion, indirect calls and register-held values. This is a Mac engine gate,
not an iPhone debugger UI test. Runtime source and production package pin stayed
unchanged. Log: `build/browser-packages-20261027/runtime-debugger-probe-complete.log`.

### Confirmed compiler blocker

The app's exact released `rustc.wasm` SHA-256
`0286dc52064283ef78ba153a554d86ae742e6c8cd638aea8662e07d3529233fc`
successfully compiles and links the normal program in the experiment. Both
`-Cdebuginfo=2` and `-Cdebuginfo=line-tables-only` instead reproduce:

```text
compiler/rustc_codegen_cranelift/src/debuginfo/line_info.rs:163:43
called `Option::unwrap()` on a `None` value
```

The same full-debug-info panic was independently reproduced by running that
compiler in the native pinned WasmKit CLI, outside the browser shim. This is a
compiler defect, not an ordinary Rust diagnostic and not proof that the guest
program is invalid. Normal app Run does not enable this broken debug profile.

The successful normal output contains neither `.debug_line` / `.debug_info`
nor a Wasm `name` custom section. A functional source debugger therefore needs
debug metadata from the code generator/linker as well as engine breakpoints.
Simply suppressing the panic does not establish source-location correctness.

Recommended implementation order:

1. Repair and qualify Wasm debug-info emission/linking on real Rust examples.
   Validate emitted addresses against actual Wasm instruction offsets.
2. Add a separate Debug profile/cache identity. Preserve the current fast Run
   path and its compiler flags.
3. Expose a bounded local session API from the runtime. Drive it on a serial
   background worker; preserve Stop, quotas and immutable project snapshots.
4. Read DWARF line tables for source breakpoints/stepping, then scopes and types
   for variables. Add Rust value formatting without evaluating arbitrary host
   expressions. Account for paused time separately from running time.
5. Add the smallest native debugger controls after verifying iPhone, iPad and Duo
   layouts. A network GDB server is not required for a local in-app UI.

## Actual frontend compiler experiment

Reproducible sources: `scripts/probes/browser-rust/`. The preparation script
checks the existing compiler and sysroot pins and a pinned, licensed WASI shim.
The Worker checks SHA-256 for each asset before use. The compiler receives the
same `CLIF2WASM_OBJECT=1` integrated linker setting as the app. The generated Wasm
program runs in the browser engine with only WASI imports and no network bridge.

The local HTTP server is Python's static-file server. The test blocks all HTTP
requests after initialization. Source is supplied by `postMessage`, not by an
HTTP request or a compiler API. Tested:

- A real Rust function/program compiles, links and prints `answer=42`.
- The real borrow checker rejects an invalid program with `E0502`.
- `std::io` reads supplied stdin and prints `sum=21`.
- Page timers continue to run while the Worker is busy.
- A compiled infinite program reports its execution start, then Worker
  termination stops it from the still-responsive page.
- No network request occurs during compilation/execution; zero source uploads.
- This single-threaded probe works with `crossOriginIsolated: false`.

Recorded final run, **Chromium 151.0.7922.34 on the Mac**, loopback assets:

| Measurement | Result |
| --- | --- |
| Toolchain initialization | 826.6 ms |
| Small Rust compile/link | 829.7 ms |
| Compile plus execute | 835.1 ms |
| Compiler linear memory at completion | 81,788,928 bytes |
| Program linear memory at completion | 1,179,648 bytes |
| Generated Wasm | 561,094 bytes |
| UI timer ticks during normal checks | 422 |
| Worker Stop round trip after execution started | 4 ms |

These are development measurements, **not an Internet first-load benchmark,
peak/RSS memory measurement, large Tokio result or iPhone/Safari measurement**.
Uncompressed experiment assets total **200,624,127 bytes (191.3 MiB)**. The
existing sysroot ZIP is much smaller than its extracted representation; a public
version needs deliberate transfer/caching design and must not eagerly download
the compiler for ordinary Academy visitors.

Receipt: `docs/rust-debugger-browser-verification-2026-10-27.json`.
Detailed local logs/artifacts remain in `build/browser-rust-feasibility-20261027/`.

### Public website scope

A client-only Rust playground is technically viable with our compiler. Begin
with standard-library lesson snippets, stdin/stdout and real compiler errors.
Do not advertise the app's full Cargo compatibility: package resolution,
build scripts, macros and filesystem persistence were not ported by this probe.

Before publishing, add explicit toolchain acquisition, pinned immutable browser
caching with quota/recovery, worker restart/timeout/output limits, accessible
editing and diagnostics, and real Chromium/Firefox/Safari/iOS gates. Keep Rust
program source out of logs, analytics and server requests. Compiler assets can
be hosted as static files while all compilation and execution remain local.

## Primary references

- [Pinned runtime debugger source](https://github.com/sergii-ziborov/crabrix-runtime/blob/e714b3efb3f4973bfd20ea41cb2cf0d6eb27713d/Sources/WasmKit/Execution/Debugger.swift)
- [Compiler debug-info flags](https://doc.rust-lang.org/rustc/codegen-options/index.html#debuginfo)
- [WebAssembly DWARF conventions](https://github.com/WebAssembly/tool-conventions/blob/main/Debugging.md)
- [Browser WASI shim](https://github.com/bjorn3/browser_wasi_shim)
