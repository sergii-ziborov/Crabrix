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
| [Crabrix](https://github.com/sergii-ziborov/Crabrix) | Stacked draft PRs [#1](https://github.com/sergii-ziborov/Crabrix/pull/1) through [#21](https://github.com/sergii-ziborov/Crabrix/pull/21), with current app-input commit `d992dfefa6565dd58fab28323124e29c44dd7869` | Academy reader, signed delivery, first-launch transition, product simplification, runtime adapter and bounded output/cache changes are reviewable. Term Train and Atlas achievements consume installed CoursePack data; lesson validation requires explicit session evidence; descriptor downloads now enforce a streaming byte limit. |
| [crabrix-courses](https://github.com/sergii-ziborov/crabrix-courses) | `663f22ac`, release `coursepack-v1.0.1` | Seven signed packs; 48 units, 742 lessons, 200 challenges, 46 gallery projects and 358 term pairs. |
| [crabrix-runtime](https://github.com/sergii-ziborov/crabrix-runtime) | App-pinned `719f94d7d27368549502828217e3dbc7e6738852`, draft [output-bound PR](https://github.com/sergii-ziborov/crabrix-runtime/pull/1) | WasmKit-derived fork with read-only preopens, cancellation adapter, and bounded WASI stdout/stderr writes. |
| [crabrix-toolchain](https://github.com/sergii-ziborov/crabrix-toolchain) | Source-locked builder branch `d624c59` | Build recipe and lock validation exist; no Crabrix-built rustc/sysroot release yet. |

The four repos are public. The course release and signed catalog have a verified public fetch. The current app still bundles the older `artifacts-test-7` compiler and sysroot as a compatibility baseline. `buildEnvironment.imageDigest` is deliberately unset in the toolchain lock, so the release validator rejects a source-build claim until a controlled Linux x86_64 build environment and its digest are recorded.

## Observed checks

- Executed Swift-model export and CoursePack semantic parity: `missing=0`, `unexpected=0`, `unapprovedChanges=0`. This checks transport parity, not every learner solution.
- iOS 18.2 Simulator full fast suite on app-input commit `d992dfef`: 411 passed, 2 opt-in compiler gates skipped, 0 failures. The two new downloader tests checked an invalid resume record falling back to an exact-digest fresh fetch and rejection of a descriptor above its byte limit before archive fetch. They do not establish interrupted transfer resume across process kill. A selected bundled compiler gate at `752181c0` passed the lesson E0502/repair Run flow with the explicit evidence contract. Term Train maps matches to mastery through its installed pair snapshot. The profile test verified installed totals before and after Atlas removal, while lifetime counts remained separate. Atlas method metadata in the signed pack matched all 20 legacy methods. The achievement store persists verified method metadata with learner progress, preserves earned badges after Atlas removal or method changes, and avoids duplicate award on refresh. All five installer tests passed, including rejection of an over-limit archive before staging and concurrent activation of seven packs through separate installers. Earlier compiler gates separately passed multi-file Run and output stress at their recorded stacked revisions.
- Runtime fork: 121 WASI tests and two bounded-stdio tests passed. The app's synthetic `fd_write` test confirmed write-time refusal, typed stop, empty capture, and successful next Run.
- The candidate input manifest verifies the app source commit, SwiftPM graph digest, exact runtime revision, old toolchain hashes, and signed course catalog sequence. It has no IPA hash.

## Performance evidence

The [A/C warning-Check comparison](performance/2026-09-30-warning-check-simulator.json) measured the old 0.3.1 runtime against the forked 0.4.1 candidate on the same old compiler. The [file-parser/dispatch probe](performance/2026-09-30-file-parser-dispatch-simulator.json) recorded five Release Simulator samples per variant. The candidate's tested token dispatch delivered roughly 1.1× improvement in the first/changed Check comparison; the temporary direct-dispatch probe was roughly 1.2× in its narrower Check workload and remains disabled. These are Simulator observations without device RSS or thermal data. A several-fold speedup is **not established**.

The application now avoids a whole-file `Data` to `[UInt8]` copy during Wasm parsing and a second whole-file `Data` copy when saving program Wasm. It replays cached Check diagnostics, bounds parsed program modules by entry count and estimated file cost, and evicts them after memory warnings. These changes need device measurement before attributing a speed or memory improvement to them.

## Remaining acceptance work

1. Remove other remaining production references to legacy Swift catalogs, then remove legacy content declarations from the production target. Atlas method achievements and profile installed totals use signed pack data; earned method metadata survives local pack removal in progress storage. Lesson validation and next-step navigation now require explicit caller-supplied data. New Run attempts have full course/content/validator/toolchain/project identity. Historical unversioned attempts still need exact legacy-snapshot attribution and an idempotent migration.
2. Complete CoursePack interruption, crash-boundary, disk-full, guaranteed partial-transfer resume, skipped-upgrade, and offline dependency gates. The downloader now recovers from an invalid resume record by starting one exact-digest fetch, but this is not a process-kill resume test.
3. Build rustc and sysroot from the pinned sources on a controlled Linux x86_64 builder, record all bootstrap/environment digests, compare two clean builds, publish notices and artifacts, then validate the same compiler/Cargo corpus on the candidate runtime.
4. Run the A/B/C performance and security corpus on physical iPhone and iPad, including cold Check, changed Check/Run, cancellation, output/disk stress, RSS/thermal, and memory-pressure recovery. Only publish a several-fold claim if measurements support it.
5. Update the site, Store description and review notes against the final binary. Produce a signed archive/release manifest with its actual IPA hash. App Store submission and correspondence remain separate owner actions.

## CI execution

From this branch onward, PRs run the fast app suite and unsigned Release build. The full bundled compiler/Cargo job runs on a manual workflow dispatch or push to main/release. This keeps the expensive integration gate separate from every stacked draft PR; a skipped PR compiler job is not a PASS. Run it explicitly on the integrated candidate and record the resulting workflow URL before release.

The [#11 fast CI run](https://github.com/sergii-ziborov/Crabrix/actions/runs/36732840896) completed successfully, including the unsigned Release build; its compiler job was skipped by design. The old [#10 run](https://github.com/sergii-ziborov/Crabrix/actions/runs/36732355146) was cancelled after its compiler job ran for about 46 minutes without a result. It is not a compiler-gate pass.
