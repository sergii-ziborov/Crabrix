# Browser-hosted Rust feasibility probe

This development experiment executes the app's **actual pinned `rustc.wasm`**, its
matching WASI sysroot, and the resulting Rust program in a browser module Worker.
It is excluded from the production website and native app. There is no compile
API, source upload, server-side process invocation, Bun, or Node runtime inside
the browser. The optional local HTTP server serves static files only.

## Reproduce

Use the verified release assets specified by
`Crabrix/Resources/toolchain.lock.json`. The preparation script verifies the
compiler and sysroot archive SHA-256 pins. It downloads
`@bjorn3/browser_wasi_shim` **0.4.2** from the npm registry, verifies its pinned
SHA-512, and retains its original source and MIT/Apache-2.0 license texts in the
development output. Nothing from that dependency is added to app resources.

```sh
python3 scripts/probes/browser-rust/prepare.py \
  --toolchain-directory /absolute/path/to/verified/release-assets
python3 -m http.server 3392 --bind 127.0.0.1 \
  --directory build/browser-rust-feasibility-20261027
```

In another terminal, with Playwright and its Chromium installed:

```sh
node scripts/probes/browser-rust/check.cjs
```

`PLAYWRIGHT_MODULE` can point to an existing Playwright module installation.
`PROBE_URL` can override the loopback origin. Run this on an unused port. The
checker saves the original Rust, generated `program.wasm`, and a JSON receipt in
the output directory. All source is first sent to the Worker with `postMessage`.
Only toolchain assets are downloaded by that Worker.

## Qualification and limits

- Verified Rust compilation, linking, stdout, stdin, and an actual borrow-checker
  `E0502` diagnostic in Chromium on the Mac.
- The test aborts **all** HTTP requests after toolchain initialization; subsequent
  compilation and execution still pass. No source leaves the browser.
- The UI event loop continues to tick while the Worker compiles and executes.
  Stop is Worker termination. No SharedArrayBuffer or isolation headers were
  needed by this single-threaded prototype.
- The compiler must receive `CLIF2WASM_OBJECT=1`, matching the app's integrated
  object/linker mode. Legacy direct emission cannot link ordinary std programs.
- `-Cdebuginfo=2` currently reproduces an internal compiler panic in
  `rustc_codegen_cranelift/src/debuginfo/line_info.rs:163`. The checker records this
  independently. Normal Run does not enable this broken debug mode.
- This is **not** Safari/iPhone qualification, a Cargo/package implementation, a
  source debugger, a persistent offline cache, or a production sandbox.
- Static experiment assets total about **191.3 MiB uncompressed**. The recorded
  loopback timings exclude real Internet transfer and production caching work.
  Reported linear memory is Wasm memory at completion, not total or peak browser
  process memory.
- Before a public playground, implement opt-in toolchain download, immutable
  verified caching, worker lifecycle/restart, time and output limits, accessible
  editing/diagnostics, supported-target messaging and real Safari/mobile gates.
  Enforce guest limits without changing headers or navigation of existing pages.

See `docs/rust-debugger-browser-feasibility-2026-10-27.md` for the native debugger
assessment and exact evidence scope.
