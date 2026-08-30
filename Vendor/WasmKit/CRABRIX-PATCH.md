# Crabrix WasmKit patch

This directory vendors upstream WasmKit 0.3.1 at commit
`ee36070acc31878ef727b90d5bdc4c9cc1fff22e`.

Crabrix adds one embedding hook: an optional per-`Store`
`InstructionLimiter`. The token-threaded execution loop calls it after each
deterministic batch of 4,096 guest instructions. Throwing from the limiter
traps execution even when the guest never performs a WASI host call.

The hook exists to enforce separate compiler and user-program execution
budgets and to make Stop terminate pure-compute guests. All other vendored
source remains at the pinned upstream revision.

`WasmKitWASI` also exposes an opt-in `beforeHostCall` link hook. Crabrix uses
it for immediate cancellation at WASI boundaries without reaching through the
deprecated raw `hostModules` compatibility API.
