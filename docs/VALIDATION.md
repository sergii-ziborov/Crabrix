# Validation record — 30 September 2026

This records observed results for the current development branch. It is not an App Store submission or physical-device certification. The latest full fast suite used the `codex/runtime-cache-bounds-2026-09-30` build inputs with fork revision `719f94d7`; older gate results explicitly name their earlier input. Documentation commits may differ without changing build inputs.

| Area | Observed result |
| --- | --- |
| Course export | Seven courses, 48 units, 742 lessons, 200 Atlas challenges, 46 gallery projects, 358 term pairs from executed Swift models. |
| Course semantic parity | `missing=0`, `unexpected=0`, `unapprovedChanges=0` for signed CoursePack 1.0.1. |
| Course reader | Simulator test installed seven bundled packs, read 742 lessons, compared written content and all 200 runtime Atlas validators to legacy models; passed. |
| Offline bootstrap | Simulator test activated bundled packs twice and retained the same version/hash identities; passed. |
| First-launch selection | At `e6f1f60`, five `CourseBootstrapTests` passed on iOS 18.2 Simulator: fresh install selects Basics, legacy progress, projects, or saved settings select all seven packs, the decision remains stable after new progress is written, and relaunch/removal behavior is preserved. |
| Full fast app suite | `xcodebuild test -project Crabrix.xcodeproj -scheme Crabrix -configuration Debug -destination 'platform=iOS Simulator,id=3FAF353F-BA0C-4F22-9443-92F60E557BF6' -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO` on this branch: 401 passed, 2 opt-in gates skipped, 0 failures. This includes the bounded WASI output, parsed-module LRU, and CoursePack signature/archive checks. |
| Public course fetch | `CrabrixCourseDeliveryGate` fetched the signed public catalog and `basics` release, verified and installed it on Simulator; passed. |
| Clean source checkout | The pushed `ecd2af0` commit built successfully in an isolated checkout without the owner's unrelated local edits. Its offline bootstrap, full reader/Atlas parity, and five sandbox tests passed there. |
| Local course removal | Clean checkout at `91f7756` built and passed two bootstrap tests (including delete/relaunch/open-session retention) and three installer tests for tamper, compatibility, and interrupted activation. |
| Runtime fork | At `719f94d7`, two bounded-stdio tests and 121 `WASITests` passed, alongside earlier adapter cancellation/fuel and memory-limit gates. |
| App runtime | With the exact remote `719f94d7` fork and old pinned toolchain, six `WasmSandboxPolicyTests` passed (including denied `fd_write`, empty capture, and next-run recovery). Three bundled compiler gates passed: E0502 Check, repaired Run, and multi-file Run. A separate >1 MiB user-program output stress gate passed; its result reported the output limit and retained no more than 1 MiB. All on iOS 18.2 Simulator with no skipped tests in these selected runs. Earlier root-feature gates used the prior fork revision. |
| Parsed program cache | The two-entry/128 KiB LRU admission/eviction test passed on Simulator. Repaired Run and the three-run repeated-build compiler gate passed after replacing the whole-file artifact copy. Actual RSS recovery during a device memory warning remains unmeasured. |
| Source-built toolchain | Not run. The public builder is source locked but has no released Crabrix-built compiler artifact. |

The Simulator used for the app gates was an iOS 18.2 device with Xcode 27.0 beta (`27A5228h`). Logs from local gates are not copied verbatim into public docs because they can contain machine paths; counts above come from completed command output. Re-run commands from the README and the repository CI before a release.

Outstanding: full course update interruption/crash/disk-full matrix, guaranteed transfer resume, legacy progress identity mapping, removal of the duplicate production Swift catalogs, large-diagnostic compiler output stress and compiler workspace/tmp bounds, physical-device memory/thermal/Stop gates, a clean upstream 0.4.1 B baseline and device measurements, own source-built toolchain, and a final release manifest linked to an actual IPA. The [candidate manifest](../release-manifests/candidate-2026-09-30.json) maps the tested code-input commit to the pinned runtime, toolchain, and catalog; it has no IPA hash. The [five-run Simulator comparison](performance/2026-09-30-warning-check-simulator.json) is A/C evidence only; it does not show a multi-fold compiler speedup.
