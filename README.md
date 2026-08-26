# Crabrix — native iOS feasibility spike

Crabrix is now a **native SwiftUI application**. There is no WebView, localhost server, JavaScript runtime, or cloud compiler in the app.

This Phase 0 spike tests the hard product gate:

> Can a bundled Rust compiler type-check and run Rust locally inside an iPhone/iPad app while offline?

The app embeds:

- a SwiftUI editor and result UI;
- [WasmKit 0.3.1](https://github.com/swiftwasm/WasmKit), a WebAssembly interpreter written in Swift with iOS support;
- a pinned WASI build of `rustc` and its `wasm32-wasip1` sysroot from [Weblings / wasm-rustc](https://github.com/AngelOnFira/wasm-rustc/releases/tag/artifacts-test-7);
- structured `rustc` JSON diagnostic parsing for the E0502 experiment;
- local execution of the Wasm program emitted by the bundled compiler;
- an adaptive native `Projects / Build / Learn` navigation shell (top tab/sidebar on iPad, bottom tab bar on iPhone);
- an editable `UITextView` code editor with Rust and Cargo TOML syntax highlighting;
- a parsed Cargo project layout with `Cargo.toml`, `src/main.rs`, and sibling modules;
- Files/Working Copy folder import, `.crabrixproject` package export, and a persistent recent-project library with last-build status;
- bounded public GitHub snapshot import for repository and branch URLs, Cargo-root discovery, and stored source provenance;
- an iOS Share Extension that queues GitHub URLs through an App Group and never tries to foreground the host app;
- a five-level Rust learning path with 20 mapped lessons and three live compiler-backed labs;
- a bounded guest runtime with 64 MiB linear-memory and table-growth limits, `/sandbox` as the only writable preopen, and no network imports.

The toolchain is downloaded **at build time**, verified by SHA-256, and copied into the app bundle. The running app never downloads compiler components.

GitHub import is an explicit user action and is the only current runtime network path. It downloads a public ZIP snapshot without requiring a GitHub login. Archives are rejected when they contain traversal paths, symlinks, too many entries, or exceed the compressed/expanded size limits. Imported programs still execute in the network-free Wasm sandbox.

The Share Extension and host app use `group.com.sergiiziborov.Crabrix`. A signing team must register that App Group before installing this target on a physical device.

## Build

Requirements:

- Xcode 27 beta or newer (Swift 6.3+ is required by WasmKit 0.3.1);
- XcodeGen;
- `zstd` on the build Mac.

```bash
./scripts/bootstrap.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Crabrix.xcodeproj \
  -scheme Crabrix \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
  build
```

Open `Crabrix.xcodeproj` for device testing.

For a signed physical build, select the same Apple development team for the
`Crabrix` and `CrabrixShare` targets, register
`group.com.sergiiziborov.Crabrix`, and regenerate both provisioning profiles.
Simulator builds use the checked-in entitlements automatically.

## Verification

The normal test scheme excludes the expensive compiler gates:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Crabrix.xcodeproj \
  -scheme Crabrix \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
  test
```

Run the real bundled-compiler gates with the dedicated scheme:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -project Crabrix.xcodeproj \
  -scheme CrabrixCompilerGate \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.5' \
  test
```

Measured on the iPad Pro 13-inch (M5) Simulator used for this spike:

- optimized Release multi-file compile/run with safe token threading: 3.3 seconds;
- unoptimized Debug compile/run: approximately 50–59 seconds;
- three consecutive optimized compile/run cycles: approximately 10–11 seconds total;
- an 80 MiB guest allocation is rejected by the 64 MiB sandbox gate;
- public `AngelOnFira/weblings` snapshot import opens 21 bounded text/source files in the native editor on Simulator;
- unsigned ARM64 `iphoneos` build: succeeds.
- uncompressed Simulator `.app` bundle: approximately 160 MB (152 MB toolchain payload).

WasmKit 0.3.1's direct-threaded interpreter crashed in an optimized iOS
Simulator build while running the bundled `rustc` module. Crabrix explicitly
uses WasmKit's token-threaded fallback, which passed the Release multi-file gate.
The current memory limiter uses WasmKit's narrow `Fuzzing` SPI because the
public `ResourceLimiter` protocol is exposed while `Store.resourceLimiter` is
still SPI. This is tracked as a dependency-integration debt, not hidden as a
production-stable API.

These numbers prove the native integration path, not physical-device performance.

## Success criteria

The compiler gate passes only when all of these are demonstrated on a physical iPhone/iPad:

1. airplane mode is enabled before launch;
2. the app reports `Bundled rustc.wasm`;
3. **Check** produces a real E0502 JSON diagnostic;
4. the repaired program compiles and **Run** prints `crab`;
5. repeated checks stay within an acceptable memory/thermal envelope;
6. a non-terminating program can be stopped without leaving runaway work.

Items 1, 5 and 6 cannot be claimed from a Simulator run. See [docs/DEVICE-GATE.md](docs/DEVICE-GATE.md).

## Repository history

The earlier browser experiment is preserved in the `archive/web-poc` branch only. It is not part of the native app or its runtime.
