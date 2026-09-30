# Validation record — 30 September 2026

This records observed results for the current development branch. It is not an App Store submission or physical-device certification. The latest full fast suite used app source commit `e6f1f60`; older gate results explicitly name their earlier input. Documentation commits may differ without changing build inputs.

| Area | Observed result |
| --- | --- |
| Course export | Seven courses, 48 units, 742 lessons, 200 Atlas challenges, 46 gallery projects, 358 term pairs from executed Swift models. |
| Course semantic parity | `missing=0`, `unexpected=0`, `unapprovedChanges=0` for signed CoursePack 1.0.1. |
| Course reader | Simulator test installed seven bundled packs, read 742 lessons, compared written content and all 200 runtime Atlas validators to legacy models; passed. |
| Offline bootstrap | Simulator test activated bundled packs twice and retained the same version/hash identities; passed. |
| First-launch selection | At `e6f1f60`, five `CourseBootstrapTests` passed on iOS 18.2 Simulator: fresh install selects Basics, legacy progress, projects, or saved settings select all seven packs, the decision remains stable after new progress is written, and relaunch/removal behavior is preserved. |
| Full fast app suite | `xcodebuild test -project Crabrix.xcodeproj -scheme Crabrix -configuration Debug -destination 'platform=iOS Simulator,id=3FAF353F-BA0C-4F22-9443-92F60E557BF6' -onlyUsePackageVersionsFromResolvedFile CODE_SIGNING_ALLOWED=NO` at `e6f1f60`: 393 tests executed, 2 opt-in gates skipped, 0 failures. This includes three CoursePack signature/archive checks after correcting the fixture lookup for XcodeGen's flat bundle layout. |
| Public course fetch | `CrabrixCourseDeliveryGate` fetched the signed public catalog and `basics` release, verified and installed it on Simulator; passed. |
| Clean source checkout | The pushed `ecd2af0` commit built successfully in an isolated checkout without the owner's unrelated local edits. Its offline bootstrap, full reader/Atlas parity, and five sandbox tests passed there. |
| Local course removal | Clean checkout at `91f7756` built and passed two bootstrap tests (including delete/relaunch/open-session retention) and three installer tests for tamper, compatibility, and interrupted activation. |
| Runtime fork | Adapter cancellation/fuel tests, relevant upstream WASI/fuel suites, and memory page limit tests passed in the runtime repo. |
| App runtime | Remote exact fork build, five sandbox tests, and bundled E0502 Check passed on Simulator. Repaired Run, multi-file, and root-feature gates passed earlier with the local checkout of the same runtime revision and old toolchain. |
| Source-built toolchain | Not run. The public builder is source locked but has no released Crabrix-built compiler artifact. |

The Simulator used for the app gates was an iOS 18.2 device with Xcode 27.0 beta (`27A5228h`). Logs from local gates are not copied verbatim into public docs because they can contain machine paths; counts above come from completed command output. Re-run commands from the README and the repository CI before a release.

Outstanding: full course update interruption/crash/disk-full matrix, guaranteed transfer resume, legacy progress identity mapping, removal of the duplicate production Swift catalogs, compiler output stress, physical-device memory/thermal/Stop gates, a clean upstream 0.4.1 B baseline and device measurements, own source-built toolchain, and a final release manifest linked to an actual IPA. The current candidate manifest records source inputs but has no IPA hash and predates the latest product changes. The [five-run Simulator comparison](performance/2026-09-30-warning-check-simulator.json) is A/C evidence only; it does not show a multi-fold compiler speedup.
