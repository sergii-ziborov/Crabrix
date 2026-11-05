# Local Serde and Tokio lesson projects — 5 November 2026

Five existing lessons now have pinned editable Cargo projects in the signed
Academy packs and an authenticated Open in Playground link on their full web
lesson. The ordinary guest Playground remains public. No new course, native
navigation, compiler replacement, MCP execution grant or account requirement for
the app was introduced.

- Serde strict typed JSON decoding, domain validation and semantic round-trip.
  This uses real serde 1.0.229 / serde_json 1.0.151 with explicit Serialize and
  Deserialize traits. Unknown, duplicate, missing, negative/overflow and blank
  name inputs are checked, plus Unicode and input-size limits. It does not
  promote the experimental derive compiler.
- Tokio 1.54.1 current-thread runtime, JoinSet completion, Semaphore backpressure
  and watch shutdown, using only rt/sync. Native threads, sockets, OS signals,
  multithread scheduling and arbitrary Tokio features are outside this profile.

Browser Cargo now evaluates target predicates against facts captured from the
exact shipped compiler (`rustc --print cfg --target wasm32-wasip1`, opt-level=0,
panic=abort). Captured facts are bound to the compiler SHA. Invalid syntax or
unknown target keys fails closed. Required applicable edges are resolved, false
selectors are excluded, and overlapping incompatible requirements are refused.

Dependency build.rs is compiled and executed locally in a separate bounded WASI
instance. Its own source is read-only; only isolated output/scratch are writable.
It sees no user sources, other packages, sysroot, host environment, network or
subprocess execution. Bounds: 64 MiB guest memory, 4 MiB generated/scratch data,
2 MiB per file, 256 entries, depth 16, 1,024 opens, 500,000 syscalls and cumulative
write/offset limits. Direct resizing, descriptor renumbering, links, renames,
native linker directives and runner environment overrides are refused. Only
bounded cfg/check-cfg/env and non-capability Cargo notices are accepted. Build
dependencies, proc macros and native links still need a separate profile.

Existing archive/graph/artifact/deadline limits, source checksums and offline Run
semantics remain. Check/Run/Debug do not fetch missing crate archives. Source edits
and observer outputs do not start execution. MCP stays manifest-free shared-std-v1.

Validation:

- All five exact programs pass offline Run and Debug with the released compiler
  in the native iOS 27.1 Duo Simulator. One XCTest executes ten real runs, with
  actual debug pauses and equal outputs; a separate test installs signed old/new
  packs and retains the old opened repository snapshot.
- All five pass the same browser Worker pipeline in the local CLI gate, with
  fetch forbidden after preparation. Actual in-app browser preparation and Serde
  Run/Step over/Continue also finish with exit 0.
- 144 site tests, TypeScript/production build, 28 CoursePack tests and 17 actual
  host Cargo reading programs pass. New regressions cover target selection,
  bounded build-script I/O/directives, path validation, RSC serialization and
  narrowly validated post-login return paths.
- Browser layouts at 390, 768, 1024 and 1440 in Light, Dark, Amber Circuit and
  Cyberpunk retain visible Run controls without horizontal page overflow.
- HTTP checks retain guest lesson/media gating, private/no-store starter delivery,
  a public ordinary Playground and no public raw course JSON.

[Browser Worker results](local-cargo-2026-11-05/browser-worker.json),
[native summary](local-cargo-2026-11-05/native-summary.json),
[layout matrix](local-cargo-2026-11-05/browser-layout.json),
[access checks](local-cargo-2026-11-05/http-access.json),
[actual Debug screenshot](local-cargo-2026-11-05/browser-serde-debug.png),
[reproduction](../scripts/probes/local-cargo/README.md).

Course IDs, question answer positions, separate protected lab harnesses and
existing progress are retained. Runnable demonstrations still complete through
the lesson question; an unchanged run is not advertised as a new graded challenge.
Projects 1.0.10 and Concurrency 1.0.8 are new immutable releases. Educational
quotation permissions live centrally in CONTENT-LICENSE.md and the generated
website/offline legal copies, with no repeated lesson banner. Other open-source
licenses are unchanged.

Primary technical references:
[Rust cfg semantics](https://doc.rust-lang.org/reference/conditional-compilation.html),
[Tokio WASM support](https://docs.rs/tokio/1.54.1/tokio/#wasm-support),
[explicit Serde traits](https://serde.rs/impl-serialize.html).
