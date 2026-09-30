# Validation record — 30 September 2026

This records observed results for the current development branch. It is not an App Store submission or physical-device certification. The current tested app source commit is `91f7756`; older gate results explicitly name their earlier input. Documentation commits may differ without changing build inputs.

| Area | Observed result |
| --- | --- |
| Course export | Seven courses, 48 units, 742 lessons, 200 Atlas challenges, 46 gallery projects, 358 term pairs from executed Swift models. |
| Course semantic parity | `missing=0`, `unexpected=0`, `unapprovedChanges=0` for signed CoursePack 1.0.1. |
| Course reader | Simulator test installed seven bundled packs, read 742 lessons, compared written content and all 200 runtime Atlas validators to legacy models; passed. |
| Offline bootstrap | Simulator test activated bundled packs twice and retained the same version/hash identities; passed. |
| Public course fetch | `CrabrixCourseDeliveryGate` fetched the signed public catalog and `basics` release, verified and installed it on Simulator; passed. |
| Clean source checkout | The pushed `ecd2af0` commit built successfully in an isolated checkout without the owner's unrelated local edits. Its offline bootstrap, full reader/Atlas parity, and five sandbox tests passed there. |
| Local course removal | Clean checkout at `91f7756` built and passed two bootstrap tests (including delete/relaunch/open-session retention) and three installer tests for tamper, compatibility, and interrupted activation. |
| Runtime fork | Adapter cancellation/fuel tests, relevant upstream WASI/fuel suites, and memory page limit tests passed in the runtime repo. |
| App runtime | Remote exact fork build, five sandbox tests, and bundled E0502 Check passed on Simulator. Repaired Run, multi-file, and root-feature gates passed earlier with the local checkout of the same runtime revision and old toolchain. |
| Source-built toolchain | Not run. The public builder is source locked but has no released Crabrix-built compiler artifact. |

The Simulator used for the app gates was an iOS 18.2 device with Xcode 27.0 beta (`27A5228h`). Logs from local gates are not copied verbatim into public docs because they can contain machine paths; counts above come from completed command output. Re-run commands from the README and the repository CI before a release.

Outstanding: clean-install course selection, full course update interruption/crash/disk-full matrix, guaranteed transfer resume, legacy progress identity mapping, removal of the duplicate production Swift catalogs, compiler read-only preopen rights and output stress, physical-device memory/thermal/Stop gates, A/B/C runtime measurements, own source-built toolchain, and a final release manifest linked to an actual IPA. The current candidate manifest records the tested source inputs but has no IPA hash.
