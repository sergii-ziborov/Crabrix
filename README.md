# Crabrix hypothesis POC

This is intentionally **not** the full Crabrix product. It tests one product loop with a real local Rust compiler:

1. edit a Rust program;
2. receive a structured `rustc` diagnostic;
3. see a causal explanation for E0502;
4. complete a 30-second compiler-validated exercise;
5. apply the smallest repair and verify the project again.

The interface is responsive for iPad/iPhone-sized browser windows. Compilation and execution happen on the Mac that runs the local server.

## Run

Requirements: Node.js 20+ and `rustc` in `PATH`.

```bash
npm start
```

Open <http://127.0.0.1:4173>.

## Test

```bash
npm test
```

The tests invoke the real local `rustc`, verify structured E0502 parsing, run a valid program, and check that an infinite loop is terminated.

## What this validates

- the IDE → diagnostic → explanation → practice → repair interaction;
- whether a causal borrow-checker explanation feels more useful than raw compiler text;
- whether short practice can remain connected to the user's project;
- a basic bounded worker lifecycle for local experiments.

## What this does not validate

- shipping `rustc` or a compiler-in-Wasm runtime inside an iOS app;
- physical-device memory, thermal, sandbox, or offline behavior;
- App Review acceptance;
- Cargo, crates.io, GitHub, multi-file projects, or adaptive review.

This server executes user-entered code on the local machine. It binds only to `127.0.0.1` and is a product experiment, not a hardened multi-user sandbox.
