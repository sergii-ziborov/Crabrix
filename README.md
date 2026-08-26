# Crabrix — native Rust workspace for iPhone and iPad

Crabrix is an early-development **native SwiftUI application** for learning,
editing, checking, and running Rust locally on iPhone and iPad. There is no
WebView, localhost server, JavaScript runtime, or cloud compiler in the app.

The current Phase 0 build validates the hardest product gate:

> Can a bundled Rust compiler type-check and run Rust locally inside an iPhone/iPad app while offline?

The app embeds:

- a SwiftUI editor and result UI;
- [WasmKit 0.3.1](https://github.com/swiftwasm/WasmKit), a WebAssembly interpreter written in Swift with iOS support;
- a pinned WASI build of `rustc` and its `wasm32-wasip1` sysroot from [Weblings / wasm-rustc](https://github.com/AngelOnFira/wasm-rustc/releases/tag/artifacts-test-7);
- structured `rustc` JSON diagnostic parsing for the E0502 experiment;
- local execution of the Wasm program emitted by the bundled compiler;
- an adaptive native `Projects / Build / Learn / Settings` navigation shell (top tab/sidebar on iPad, bottom tab bar on iPhone);
- an editable `UITextView` code editor with Rust and Cargo TOML syntax highlighting;
- a parsed Cargo project layout with `Cargo.toml`, `src/main.rs`, sibling modules, colored file-type icons, and native file/folder creation;
- Files/Working Copy folder import, `.crabrixproject` package export, and a persistent recent-project library with last-build status;
- bounded public GitHub snapshot import for repository and branch URLs, Cargo-root discovery, and stored source provenance;
- an iOS Share Extension that queues GitHub URLs through an App Group and never tries to foreground the host app;
- a course hub for Basics, Ownership, advanced Cargo projects, and interview preparation, followed by visual lesson journeys, a distinct explanation/objective/task brief for every lesson, and live compiler-backed labs;
- quick practice that covers answer selection, concept matching, and drag-to-arrange code without forcing every lesson into the editor;
- four fully offline example projects for pixel art, a terminal dashboard, generative constellations, and collection practice;
- draggable/collapsible project and diagnostic panels on iPad, plus a fixed-width, vertically resizable `Problems / Output / Terminal` dock with highlighted streams/commands and live build state on both the workspace and project library;
- a review-before-insert Rust completion action: deterministic offline suggestions everywhere and optional Apple Foundation Models completion on eligible iOS 26+ devices;
- Auto, Light, and Dark themes, adjustable editor text, build keep-awake control, and a searchable crates.io catalog with owner/download metadata and per-package version selection;
- a bounded guest runtime with 64 MiB linear-memory and table-growth limits, `/sandbox` as the only writable preopen, and no network imports.

The toolchain is downloaded **at build time**, verified by SHA-256, and copied into the app bundle. The running app never downloads compiler components.

Runtime network access is limited to explicit user actions: public GitHub snapshot import and crates.io package discovery. The catalog fetches metadata only; it does not download crate sources. GitHub archives are rejected when they contain traversal paths, symlinks, too many entries, or exceed the compressed/expanded size limits. Imported programs still execute in the network-free Wasm sandbox.

The project terminal is an app-scoped command console, not an arbitrary iOS
shell. It keeps a separate transcript per project and maps `cargo check`,
`cargo run`, `cargo tree`, `ls`, `cat`, `pwd`, and `clear` to Crabrix's native
project and compiler operations.

The learning build profile favors iteration speed over optimized guest code.
`Run` emits an unoptimized teaching artifact, stores successful `program.wasm`
output under a source/toolchain hash in the app cache, and freshly executes that
artifact on an unchanged repeat run. The first compile still invokes the real
bundled `rustc`; subsequent identical runs avoid recompilation, including after
an app restart while iOS retains the cache.

Apple Intelligence completion is also local and optional. Crabrix checks
`SystemLanguageModel.availability` at runtime and falls back to its small,
deterministic Rust completion table when the system model, supported hardware,
or Apple Intelligence setting is unavailable. Suggested text is never inserted
without an explicit user action.

The Share Extension and host app use `group.com.sergiiziborov.Crabrix`. A signing team must register that App Group before installing this target on a physical device.

## License and ownership

Crabrix is commercial proprietary software, not an open-source MIT project.
Copyright © 2026 Serhii Ziborov. All rights reserved. The source is publicly
visible for review and evaluation; reuse, modification, redistribution, sale,
or derivative works require prior written authorization. See [LICENSE](LICENSE).

Bundled third-party components keep their original licenses. Their required
attributions are maintained separately in
[Crabrix/Resources/ThirdPartyNotices.md](Crabrix/Resources/ThirdPartyNotices.md).

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
- unchanged cached Debug run after an app restart: 44 milliseconds on the same Simulator;
- three consecutive optimized compile/run cycles: approximately 10–11 seconds total;
- an 80 MiB guest allocation is rejected by the 64 MiB sandbox gate;
- public `AngelOnFira/weblings` snapshot import opens 21 bounded text/source files in the native editor on Simulator;
- unsigned ARM64 `iphoneos` build: succeeds;
- signed Release install and launch smoke test: succeeds on an iPhone 13 mini running iOS 26.5;
- uncompressed Simulator `.app` bundle: approximately 160 MB (152 MB toolchain payload).

The local free-development provisioning profile used for that install smoke
test did not include App Groups. It validates the host app's installation and
launch, but not Share Extension handoff; that path still requires the registered
App Group described above.

WasmKit 0.3.1's direct-threaded interpreter crashed in an optimized iOS
Simulator build while running the bundled `rustc` module. Crabrix explicitly
uses WasmKit's token-threaded fallback, which passed the Release multi-file gate.
The current memory limiter uses WasmKit's narrow `Fuzzing` SPI because the
public `ResourceLimiter` protocol is exposed while `Store.resourceLimiter` is
still SPI. This is tracked as a dependency-integration debt, not hidden as a
production-stable API.

The current Stop button immediately releases the app UI, ignores the stale
compiler result, and reports sandbox cleanup. WasmKit 0.3.1 does not expose a
safe hard-interruption/fuel API for an already-running interpreter, so Crabrix
does not start a second compiler job until that worker has drained. A true
hard-timeout remains part of the physical-device gate.

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
