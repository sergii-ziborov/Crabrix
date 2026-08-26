# Physical-device feasibility gate

Simulator success is necessary but not sufficient. A release decision requires the following run on a supported physical iPhone and iPad.

## Preparation

- Build a Development configuration containing the pinned `artifacts-test-7` toolchain.
- Select the same signing team for `Crabrix` and `CrabrixShare`.
- Register `group.com.sergiiziborov.Crabrix` for both identifiers and regenerate their provisioning profiles.
- Install from Xcode while the device is connected.
- Disconnect the cable after installation.
- Enable airplane mode and verify Wi-Fi is off.
- Cold-launch Crabrix.

## Required checks

| Gate | Procedure | Pass condition |
| --- | --- | --- |
| Bundle | Open Runtime status | Both `rustc.wasm` and `sysroot-wasip1` are found inside the app bundle |
| Check | Run the bundled E0502 sample | A structured E0502 diagnostic is produced with correct source lines |
| Repair | Apply the suggested line reorder and Check again | `rustc` exits successfully |
| Run | Run the repaired sample | The compiled guest Wasm prints `crab` |
| Repeat | Perform 20 checks | No crash; record median/p95 time and peak memory |
| Thermal | Continue checking for 10 minutes | Record `ProcessInfo.thermalState`; no critical state |
| Recovery | Background/foreground during a check | UI recovers without corrupting the work directory |
| Infinite loop | Run `fn main() { loop {} }` | Work is terminated and CPU returns to idle |

## Current hard blocker

WasmKit 0.3.1 exposes a synchronous interpreter without a public fuel/epoch interruption API. Running compilation off the main actor keeps SwiftUI responsive, but a guest infinite loop cannot yet be safely killed. A soft UI timeout would hide the result while leaving CPU work alive, so Crabrix deliberately does not claim this gate.

Before App Store work, choose and verify one of:

1. add a bounded-instruction/fuel mechanism to the interpreter;
2. use an iOS-safe interpreter runtime with proven interruption support;
3. instrument emitted Wasm with cooperative budget checks.

Do not replace this test with a simulated timeout.

## Automated evidence already available

The dedicated Release test scheme now proves the following before a physical-device session:

- structured E0502 diagnostics;
- single-file compile/run and captured stdout;
- a Cargo-shaped multi-file project (`Cargo.toml`, `src/main.rs`, `src/greeter.rs`);
- three consecutive compile/run cycles in one compiler instance;
- denial of an 80 MiB guest allocation at the configured 64 MiB program limit;
- path validation and a single writable `/sandbox` preopen for the user program.

These tests reduce device-session risk. They do not replace the 20-run memory,
thermal, airplane-mode, lifecycle, or infinite-loop checks above.

The App Group requirement was added with the GitHub Share Extension. A
profile/entitlement mismatch is a provisioning blocker, not evidence for or
against compiler feasibility.
