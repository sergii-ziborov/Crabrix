# Product direction — 30 September 2026

This document records the owner's additions to the Academy, runtime, and toolchain migration. The migration contract and acceptance gates remain in force except where the owner explicitly changes the product behavior below.

## Performance

- The new WasmKit 0.4.1 fork and Crabrix patches should target a several-fold improvement in the real app workflow.
- Measure the same compiler, corpus, build mode, and device on legacy 0.3.1, clean 0.4.1, and the patched fork. Distinguish cold compile, changed Check/Run, unchanged cache hits, downloads, memory, and cancellation.
- Publish a speed multiplier only after repeatable on-device measurements. Correctness and sandbox gates still apply. If a workload does not improve several-fold, report the actual result and continue profiling it.

## Navigation and project organization

- Simplify the Projects home. Tapping My Projects opens its management view; remove its duplicate search and filter UI from the home tab. Keep search and management where they belong, inside My Projects.
- Move GitHub and iCloud Drive/Files import actions into New Project. Creating a template and importing a project remain distinct actions in that sheet.
- Remove the app-level Build tab. The code workspace remains reachable from the current project and project list, with a clear route back to Projects.
- On each entry into a code workspace, show Code. Selecting any other source file while Output or another dock page is active also shows Code.
- Keep project folders and tags. Remove the separate project Type control and migrate old projects without dropping their folder, tags, or identity. Confirm existing type usage before removing storage.

## Learning and editor

- Remove Health and Energy as product mechanics, including gates and visible meters. Preserve completed lessons, ratings, achievements, and existing project/progress identity. Old vitals data may be ignored by the new version without deleting unrelated persisted data.
- Remove the literal “Go to Practice” label while retaining a discoverable practice action where needed.
- Show exercise hints in Output, associated with the same course session and exercise version as the result.
- Remove the Cargo Packages section from Settings; project dependency controls remain in the project workspace.

## Appearance and privacy

- Add a third explicit appearance choice, Cyberpunk, in addition to Light and Dark (and the existing automatic setting if retained). Apply it across the app, including the editor and system surfaces. Use the owner's RepoLens cyberboard as a visual reference for dark navy, cyan, amber, violet, and restrained neon treatment; do not use game artwork or logos.
- Add optional Face ID app protection using local device authentication. Provide a passcode fallback and a safe flow for devices without Face ID; do not add an account or upload biometric data.

## Delivery state at this decision

The public courses repository contains the complete 742-lesson / 200-Atlas-challenge corpus and signed packs. The public runtime fork is based on WasmKit 0.4.1 and the app is pinned to its exact revision. The source-locked toolchain recipe is public, but its own compiler/sysroot production and device performance gates remain open. The owner has not authorized an App Store submission.
