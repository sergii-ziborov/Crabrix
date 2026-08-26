# Crabrix — native iOS feasibility spike

Crabrix is now a **native SwiftUI application**. There is no WebView, localhost server, JavaScript runtime, or cloud compiler in the app.

This Phase 0 spike tests the hard product gate:

> Can a bundled Rust compiler type-check and run Rust locally inside an iPhone/iPad app while offline?

The app embeds:

- a SwiftUI editor and result UI;
- [WasmKit 0.3.1](https://github.com/swiftwasm/WasmKit), a WebAssembly interpreter written in Swift with iOS support;
- a pinned WASI build of `rustc` and its `wasm32-wasip1` sysroot from [Weblings / wasm-rustc](https://github.com/AngelOnFira/wasm-rustc/releases/tag/artifacts-test-7);
- structured `rustc` JSON diagnostic parsing for the E0502 experiment;
- local execution of the Wasm program emitted by the bundled compiler.

The toolchain is downloaded **at build time**, verified by SHA-256, and copied into the app bundle. The running app never downloads compiler components.

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
- unsigned ARM64 `iphoneos` build: succeeds.
- uncompressed Simulator `.app` bundle: approximately 160 MB (152 MB toolchain payload).

WasmKit 0.3.1's direct-threaded interpreter crashed in an optimized iOS
Simulator build while running the bundled `rustc` module. Crabrix explicitly
uses WasmKit's token-threaded fallback, which passed the Release multi-file gate.

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
