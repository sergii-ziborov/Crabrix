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
| Stop during a build | Start a fresh Run, tap Stop after ~3 s | The build returns as stopped and CPU returns to idle |
| Stop a printing loop | Run a program that prints in an endless loop, then Stop | Execution ends and CPU returns to idle |
| Infinite loop | Run `fn main() { loop {} }` | Work is terminated and CPU returns to idle |
| Cargo first build | Create the Cargo Packages template and Run | Packages download, compile, and the program prints; record wall-clock and peak memory |
| Cargo offline rebuild | Enable airplane mode and Run the same project again | The build reuses cached artifacts and succeeds with no network |
| Cargo cache-eviction rebuild | Tap **Pin exact graph for offline**, remove purgeable Cargo cache, enable airplane mode, and Run | Exact pinned archives rehydrate source and the locked build succeeds without network |
| Vendor & Edit | Vendor a downloaded crate, add a harmless source edit, Run, inspect Diff, then Reset | Patched fingerprint builds, registry source stays unchanged, and Reset restores registry identity |

## Interruption architecture and remaining proof

Crabrix wraps every WASI host function the guest imports, so cancelling traps a
guest on its next syscall. The pinned vendored WasmKit fork additionally calls
an `InstructionLimiter` after each deterministic batch of 4,096 guest
instructions. The same interrupter therefore reaches a pure compute guest that
never calls WASI. Runtime budgets also cap wall-clock time, output, writable
bytes/files, memory, and tables.

Automated tests prove both instruction-budget exhaustion and explicit
cancellation of a handcrafted pure-compute Wasm loop. They also prove the UI
Run gate reopens after the compiler worker drains. The old statement that
`loop {}` cannot be killed is no longer true for this source tree.

What remains is physical evidence, not a missing interruption mechanism:

1. `loop {}` stops promptly on every device class;
2. CPU returns to baseline rather than merely hiding UI state;
3. memory is released;
4. the immediately following Check/Run starts and completes;
5. repeated stop cycles do not accumulate orphan work.

Do not replace these observations with a simulated UI timeout.

## Automated evidence already available

The dedicated Release test scheme now proves the following before a physical-device session:

- structured E0502 diagnostics;
- single-file compile/run and captured stdout;
- a Cargo-shaped multi-file project (`Cargo.toml`, `src/main.rs`, `src/greeter.rs`);
- three consecutive compile/run cycles in one compiler instance;
- denial of an 80 MiB guest allocation at the configured 64 MiB program limit;
- path validation and a single writable `/sandbox` preopen for the user program;
- resolution, checksum-verified download, extraction, compilation, and linking of
  a real crates.io package, followed by running the linked program;
- interruption of a running compile within the asserted window;
- deterministic instruction-budget and explicit-cancel traps for a pure loop;
- four-case private Algorithm Atlas verifier injection for every pattern
  (expected values are not in the editable project), including an independent
  semantic input and surrounding-whitespace variants;
- crates.io **Vendor & Edit**, including a distinct patch fingerprint and real
  patched dependency link;
- a pre-build package-source audit that blocks oversized or non-UTF-8
  programming source when Crabrix cannot expose it through complete View/Edit;
- offline pinning followed by deletion of purgeable source/archive cache and a
  successful frozen rehydrate;
- root `CARGO_PKG_*` environment values from the project manifest;
- separate persisted evidence for metadata Check and full Link.

These tests reduce device-session risk. They do not replace the 20-run memory,
thermal, airplane-mode, lifecycle, CPU-idle, or immediate-second-run checks
above.

The App Group requirement was added with the GitHub Share Extension. A
profile/entitlement mismatch is a provisioning blocker, not evidence for or
against compiler feasibility.
