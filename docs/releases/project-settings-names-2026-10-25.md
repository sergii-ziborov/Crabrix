# Project settings and unique names — 25 October 2026

## Changes

- Project settings has Save at the leading edge and an accessible checkmark Close action at the trailing edge. The repeated save action below the fields is removed.
- Save persists metadata before closing; a write failure keeps the draft open. Export and archive actions also wait for metadata persistence.
- The unlabeled Favorite toggle next to Organize project is removed; the overview star remains the favorite control.
- The durable project store assigns unique display names to separate project IDs on creation, import and rename, using numeric suffixes and case-insensitive comparisons. Saving an existing ID excludes that project's own name from collision checks.
- Existing duplicate names are repaired through recoverable snapshot transactions. All IDs, files, metadata, build records and existing dates are retained. Existing suffixed names are reserved before repairing duplicates.
- The active workspace displays the assigned persisted name. Metadata-only edits in My Projects also use the saved name returned by the store.
- Verification found an existing stale-lockfile case when removing the final dependency. The obsolete lock is removed only when no dependencies of any kind remain; locks for projects with remaining dependencies are kept.

## Verification

The optimized CompilerCandidate simulator build succeeded with Xcode 27.1 RC. The final selected run passed **35 tests, 0 failures, 0 skips**: 18 ProjectImport tests, 14 ProjectAuthoring tests and 3 WorkspaceRevisionViewModel tests. The initial run exposed the stale-lockfile failure above; the final run includes its correction.

Coverage includes concurrent saves, repeated imported names and autosaves, case-insensitive rename collisions, suffix reservation, old duplicate-name repair, unchanged files and build history, reopening repaired records, and waiting for real metadata persistence before reporting success.

Local evidence: `build/compiler-optimization-20261024/project-settings-names-final.xcresult` and `project-settings-names-final-tests.log`.

The workspace's Duo header, fold sizing, tabs and keyboard geometry are unchanged. This app patch continues to use the existing signed production compiler; corrected experimental compiler inputs are tested separately.
