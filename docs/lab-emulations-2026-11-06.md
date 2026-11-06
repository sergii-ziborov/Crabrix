# Algorithm Atlas laboratory — 6 November 2026

The website changes are public. Crabrix 1.1.7 (133) is VALID and
IN_BETA_TESTING in the existing Internal QA group. This candidate was not
submitted to App Review; the existing build 132 review assignment was preserved.
The [Apple and signature receipt](app-store/release-1.1.7-build133.json) records
the exact source, binary hash, checks and readback time.

## Completed behavior

- Every one of the 600 Atlas lesson stages opens a personal Playground copy of
  its exact verified source and original input, with Cargo.toml and provenance.
  Run and Debug use that editable copy. The original replay and lesson progress
  remain independent. The existing local draft/save behavior is preserved.
- Index labels belong to the selected collection's direct source indexing or
  enumeration. Costs and other scalar parameters are not automatically array
  indices. Strings, raw strings and nested comments are excluded. These labels
  are presentation hints, rather than a full Rust name resolver; indirect and
  arithmetic index expressions remain unlabeled.
- Previous-state comparisons follow the same function activation across nested
  calls. Map/set changes follow typed structural keys and membership, with
  added/changed values and a removed-items disclosure on the website.
- Switching lesson stages resets playback. Hiding the browser tab pauses it.
  Native section inspection clears stale data and offers an explicit retry on
  an initial acquisition error.

## Verification

- Website: 158 tests, TypeScript check and production build passed. All 600
  source-copy mappings were checked. All 400 distinct examples passed the
  browser Debug transformation and host rustc metadata/type checking. That
  additional check is not a claim of executing all 400 programs on wasm32.
- Browser: original Run returned `2`; an edited input returned `-1`, while the
  lesson replay retained `2`. Breakpoint, step and continue worked. The public
  site also completed Run and Debug with output `2`. Array, map, set, graph,
  matrix and linked-tree examples were inspected, including Model, Recognize
  and Challenge stages. The page fitted 320 px and 390 px widths.
- Native: 42 Atlas/course tests passed with zero skips and failures, including
  all 600 signed lesson mappings / 400 recordings and an actual edited personal
  copy through Run and Debug. Tampering, stale source, exact large integers and
  removal without deleting personal projects/progress were covered.
- Distribution: manual local Release archive/export, strict signatures for the
  app and Share extension, source/profile entitlement checks, packaged legal
  document comparison, Apple validation/upload and Internal QA readback passed.
  No automatic CI or new App Review submission was used.

Native manual visual and physical-device checks were not completed: the Mac was
locked. No such checks are claimed by the release receipt. TestFlight notes
describe the remaining hands-on checks.

Recordings use a native Rust target; editable code uses wasm32-wasip1. The UI and
copy README disclose that target-sized values such as `usize` can have different
limits. The recordings are never presented as executions of subsequently
edited code. See [the execution model](algorithm-visualizations.md).

Operator proof artifacts are under the ignored
`build/lab-emulations-20261106/` directory: `verification.json`,
`AtlasReplay133.xcresult`, `debug-corpus-metadata.json`,
`public-lab-debug.jpg`, `public-lab-run.jpg` and `map-mobile.png`.
