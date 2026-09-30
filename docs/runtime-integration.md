# Runtime integration

The public [CrabrixRuntime fork](https://github.com/sergii-ziborov/crabrix-runtime) keeps WasmKit upstream history and notices. Its base is WasmKit 0.4.1 at `a0471eaee817c523b8023d8ebb1c70ff70b7950a`; the app pins fork commit `9dc0ef77c101d2b1f1433ece34a0e47889770335`. There is no second production engine in the SwiftPM graph. The old vendored source remains only as historical source in the repository and is not linked into the app target.

`RustcRuntime` uses token threading, software memory bounds checks, upstream fuel metering, the fork's cancellation probe at fuel checkpoints, and a fresh `Store` and WASI instance for each invocation. Host calls are guarded, and network socket imports return guest `ENOSYS`. Separate `CompilerHostPolicy` and user program policy set memory, table, fuel, and wall-clock budgets. A fuel trap maps to a typed instruction-budget stop. The program output and writable sandbox have a quota monitor.

The fork adapter tests cover fuel exhaustion, pure-loop cancellation, fresh-run recovery, memory page limits, and guarded WASI links. The app's five sandbox policy tests and bundled E0502 Check passed against the pinned remote revision on iOS Simulator. The earlier local fork test also compiled and ran a repaired program, multi-file project, and root-feature case with the old toolchain. See [validation](VALIDATION.md) for what was actually run.

## Remaining gates

The compiler's source/sysroot/registry preopens are not yet enforced as read-only WASI capabilities; `/work` and `/artifacts` are currently writable to support output. Its `outputLimitBytes` policy constant is not yet a write-time hard limit. Cold host parse cannot currently be stopped in the middle of parsing. Parsed program module cache bounds, warning snapshot parity, device measurements, and memory-pressure recovery still need implementation and evidence. Do not interpret the existing fuel tests as proof of these separate properties.
