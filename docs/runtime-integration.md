# Runtime integration

The public [CrabrixRuntime fork](https://github.com/sergii-ziborov/crabrix-runtime) keeps WasmKit upstream history and notices. Its base is WasmKit 0.4.1 at `a0471eaee817c523b8023d8ebb1c70ff70b7950a`; the app pins fork commit `731d09b7c779e62fd42832312c42d29f69475361`. There is no second production engine in the SwiftPM graph. The old vendored source remains only as historical source in the repository and is not linked into the app target.

`RustcRuntime` uses token threading, software memory bounds checks, upstream fuel metering, the fork's cancellation probe at fuel checkpoints, and a fresh `Store` and WASI instance for each invocation. Host calls are guarded, and network socket imports return guest `ENOSYS`. Separate `CompilerHostPolicy` and user program policy set memory, table, fuel, and wall-clock budgets. A fuel trap maps to a typed instruction-budget stop. The program output and writable sandbox have a quota monitor.

The fork adapter tests cover fuel exhaustion, pure-loop cancellation, fresh-run recovery, memory page limits, guarded WASI links, and read-only nested descriptors. The app's five sandbox policy tests, bundled E0502 Check, repaired Run, and multi-file Run passed against the pinned remote revision on iOS Simulator with the old pinned toolchain. See [validation](VALIDATION.md) for what was actually run.

## Remaining gates

Compiler source, sysroot, and registry preopens now use read-only WASI rights; `/work` and `/tmp` remain writable outputs. The compiler's `outputLimitBytes` policy constant is not yet a write-time hard limit. Cold host parse cannot currently be stopped in the middle of parsing. Parsed program module cache bounds, warning snapshot parity, device measurements, and memory-pressure recovery still need implementation and evidence. Do not interpret the existing fuel tests as proof of these separate properties.
