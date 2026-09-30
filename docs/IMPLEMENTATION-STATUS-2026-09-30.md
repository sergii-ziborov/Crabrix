# Academy, runtime, toolchain: implementation status

This is a technical handoff for the 30 September 2026 development candidate. It is not a release claim or an App Store submission. The candidate source and dependency mapping is in [`release-manifests/candidate-2026-09-30.json`](../release-manifests/candidate-2026-09-30.json); an IPA hash is not available.

## Decisions retained

- Move the complete existing Academy corpus without rewriting it. Keep the existing bundle ID, price, local compiler, and user projects.
- Maintain a public fork of WasmKit 0.4.1 at upstream `a0471eaee817c523b8023d8ebb1c70ff70b7950a`. Build Rust from pinned sources through a public builder fork. Do not start an independent engine or compiler rewrite.
- Target a several-fold improvement in actual Check/Run workflows, measured on the same device and toolchain. Do not describe smaller Simulator gains as that result.
- Keep application, course data, runtime, and builder public while retaining upstream notices and separating the licenses of authored course content.

## Public inputs and current code

| Repository | Current development identity | Result |
| --- | --- | --- |
| [Crabrix](https://github.com/sergii-ziborov/Crabrix) | Stacked draft PRs [#1](https://github.com/sergii-ziborov/Crabrix/pull/1) through [#10](https://github.com/sergii-ziborov/Crabrix/pull/10), with app-input commit `f8d1bb78cbbd8b8b0fe632e124786da7c82be9b5` | Academy reader, signed delivery, first-launch transition, product simplification, runtime adapter and bounded output/cache changes are reviewable. |
| [crabrix-courses](https://github.com/sergii-ziborov/crabrix-courses) | `663f22ac`, release `coursepack-v1.0.1` | Seven signed packs; 48 units, 742 lessons, 200 challenges, 46 gallery projects and 358 term pairs. |
| [crabrix-runtime](https://github.com/sergii-ziborov/crabrix-runtime) | App-pinned `719f94d7d27368549502828217e3dbc7e6738852`, draft [output-bound PR](https://github.com/sergii-ziborov/crabrix-runtime/pull/1) | WasmKit-derived fork with read-only preopens, cancellation adapter, and bounded WASI stdout/stderr writes. |
| [crabrix-toolchain](https://github.com/sergii-ziborov/crabrix-toolchain) | Source-locked builder branch `d624c59` | Build recipe and lock validation exist; no Crabrix-built rustc/sysroot release yet. |

The four repos are public. The course release and signed catalog have a verified public fetch. The current app still bundles the older `artifacts-test-7` compiler and sysroot as a compatibility baseline. `buildEnvironment.imageDigest` is deliberately unset in the toolchain lock, so the release validator rejects a source-build claim until a controlled Linux x86_64 build environment and its digest are recorded.

## Observed checks

- Executed Swift-model export and CoursePack semantic parity: `missing=0`, `unexpected=0`, `unapprovedChanges=0`. This checks transport parity, not every learner solution.
- iOS 18.2 Simulator full fast suite on the latest app code: 402 passed, 2 opt-in compiler gates skipped, 0 failures. Selected compiler gates separately passed E0502 Check, repaired Run, multi-file Run, output stress, and a pinned CourseSession repair flow at their recorded stacked revisions. The full seven-course practice deck matched the legacy question/snippet/Rust-term snapshot.
- Runtime fork: 121 WASI tests and two bounded-stdio tests passed. The app's synthetic `fd_write` test confirmed write-time refusal, typed stop, empty capture, and successful next Run.
- The candidate input manifest verifies the app source commit, SwiftPM graph digest, exact runtime revision, old toolchain hashes, and signed course catalog sequence. It has no IPA hash.

## Performance evidence

The [A/C warning-Check comparison](performance/2026-09-30-warning-check-simulator.json) measured the old 0.3.1 runtime against the forked 0.4.1 candidate on the same old compiler. The [file-parser/dispatch probe](performance/2026-09-30-file-parser-dispatch-simulator.json) recorded five Release Simulator samples per variant. The candidate's tested token dispatch delivered roughly 1.1× improvement in the first/changed Check comparison; the temporary direct-dispatch probe was roughly 1.2× in its narrower Check workload and remains disabled. These are Simulator observations without device RSS or thermal data. A several-fold speedup is **not established**.

The application now avoids a whole-file `Data` to `[UInt8]` copy during Wasm parsing and a second whole-file `Data` copy when saving program Wasm. It replays cached Check diagnostics, bounds parsed program modules by entry count and estimated file cost, and evicts them after memory warnings. These changes need device measurement before attributing a speed or memory improvement to them.

## Remaining acceptance work

1. Migrate achievement/category policy and profile totals without revoking earned rewards; then remove legacy content declarations from the production target. Historical attempts still need their full course/content/validator/toolchain/project identity and idempotent migration.
2. Complete CoursePack interruption, crash-boundary, disk-full, guaranteed resume, skipped-upgrade, and offline dependency gates. Do not infer them from happy-path installation.
3. Build rustc and sysroot from the pinned sources on a controlled Linux x86_64 builder, record all bootstrap/environment digests, compare two clean builds, publish notices and artifacts, then validate the same compiler/Cargo corpus on the candidate runtime.
4. Run the A/B/C performance and security corpus on physical iPhone and iPad, including cold Check, changed Check/Run, cancellation, output/disk stress, RSS/thermal, and memory-pressure recovery. Only publish a several-fold claim if measurements support it.
5. Update the site, Store description and review notes against the final binary. Produce a signed archive/release manifest with its actual IPA hash. App Store submission and correspondence remain separate owner actions.

## CI execution

From this branch onward, PRs run the fast app suite and unsigned Release build. The full bundled compiler/Cargo job runs on a manual workflow dispatch or push to main/release. This keeps the expensive integration gate separate from every stacked draft PR; a skipped PR compiler job is not a PASS. Run it explicitly on the integrated candidate and record the resulting workflow URL before release.
