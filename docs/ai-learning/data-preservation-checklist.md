# Data preservation checklist (spec §15)

Each check maps to an existing automated test, or is marked **GAP** with the test to add.
iOS tests: `CrabrixTests/*` (unit/integration, Simulator) and `CrabrixScreenshotTests/*` (UI).
Fixtures must use the app's real formats (`UserDefaults` keys, `.crabrixprogress`, signed packs),
never real learner data.

## 15.1 Reference learner (fixture to build) — GAP

No single fixture today combines every state. Add `CrabrixTests/AcademyLearnerFixtureTests.swift`
that writes, in an isolated `UserDefaults` suite and temp `Application Support` root:
several completed lessons across basics/ownership/algorithms, answers, one passed and one failed
lab in `crabrix.learn.attemptEvidence.v1`, two bridge credits, flashcards and mastery records,
`crabrix.progress.state.v1` with XP and achievements, two installed signed packs (from
`MigrationCoursePacks`), one lesson-lab project and one edited Examples copy, a Git repository.
Snapshot all of it (hash per store) as the "before" state.

## 15.2 Before update — record

| Record | Existing test that already captures it | Gap |
|---|---|---|
| Course list, IDs, versions | `CourseBootstrapTests.testBundledBaselineInstallsOfflineAndRelaunchKeepsIdentity`; crabrix-courses `tests/test_coursepack.py` | — |
| Completed lessons and answers | `ProjectAuthoringTests.testLessonAnswerAndReviewStateSurviveTheExpectedTransitions` | fixture hash (15.1) |
| Lab results | `CourseBootstrapTests.testAttemptEvidenceDecodesOldRecordsWithoutInventingCourseVersion` | fixture hash |
| Project contents | `ProjectImportTests.testDurableStoreKeepsEveryProjectBeyondRecentLimit`, `testInterruptedTransactionRestoresPreviousSnapshot` | fixture hash |
| Local storage state | `LearningBackupTests.testRoundTripAndStableContentIdentity` (content hash) | include attempt evidence/typing in the fixture hash (not in backups) |
| Website account | none needed: accounts hold no learning data (`site/app/account/export/route.ts`) | — |

## 15.3 After update — verify

| Check | Test |
|---|---|
| Every previously available lesson opens | `InstalledCourseRepositoryTests.testAllBundledPacksReadAsExistingAcademyModels`; site `tests/return-path.test.mjs` (every lesson path) |
| Progress kept; completed stay completed | `CourseDeliveryGateTests.testPublicCourseUpgradeKeepsOpenLessonSnapshotAndStableIDs`; `PracticalCourseUpdateTests.testSignedPracticalUpdateLoadsWithoutChangingAnOldRepository`; `InterviewCourseUpdateTests.testProductionSignedUpdateLoads52UniqueQuestionsAndKeepsOldSession` |
| Saved answers / indices unchanged | crabrix-courses `tests/test_practical_paths.py::test_existing_identity_order_questions_and_answer_indices_are_preserved`, `tests/test_academy_corrections.py` |
| Projects untouched; Examples not overwritten | `CourseDeliveryGateTests.testPublicExamplesUpgradeKeepsEditedProjectAndLoadsEveryInfographic`; `ProjectAuthoringTests.testResetCourseProgressKeepsOtherCourseAndProject` |
| CoursePacks open; updates work | `CourseInstallerTests` (14), `CoursePackVerifierTests` (3), `CourseDownloadManagerTests` (7), `LessonBridgeTests.testProductionSignedBridgePacksInstallAndDecode`, UI `BridgeCourseTests.testDownloadOpenAndCaptureABridgeLesson` (download + Update) |
| Compiler and Debug work | `BundledCompilerGateTests`, `RustDebuggerTests`; UI `RustDebuggerUITests` |
| Existing MCP works | crabrix-sdk `npm test` (83 tests: `protocol`, `room`, `room-v2`, `agent-link`, `mcp-reliability`, `runtime-*`, `sdk`) |
| Offline not degraded | `CourseBootstrapTests.testBundledBaselineInstallsOfflineAndRelaunchKeepsIdentity`, `OfflineWebPreviewTests` |
| Fixture hashes equal before/after | **GAP** (15.1 test, second half) |

## 15.4 Old versions

| Check | Test | Gap |
|---|---|---|
| Old progress with the new app | `LearningBackupTests.testInterruptedRestoreRecoversBothFormatsPreservesOtherPreferencesAndIsNotReplayed`, `LessonBridgeTests.testLegacyBackupWithoutCreditsStillRestores`, `CourseBootstrapTests.testLegacyProgressOrProjectsSelectFullOfflineMigration` | — |
| Old CoursePack with the new app | `CourseInstallerTests.testJournalWrittenInAnOlderContainerPathStillRecovers`, `CourseBootstrapTests.testInstalledPracticeDecksMatchCompleteLegacyBaseline` | — |
| Pack the app cannot read | `CourseInstallerTests.testSignedUpdateThisAppCannotReadKeepsTheWorkingVersion`, `LessonBridgeTests.testBridgeDataWithoutTheCapabilityOrMalformedIsRefusedAtInstall` | — |
| Existing Playground SDK with updated MCP | SDK `test/protocol.test.ts` (tool list), `test/agent-link.test.ts` (bound server hides room tools) | **GAP**: old 0.5.0 client against a server with academy tools (tool list superset, same schemas) |
| Projects created before the update | `ProjectImportTests.testLegacyMigrationRetainsItsOriginalPreviousSnapshot` | — |
| Temporary rooms with older clients | SDK `test/room-v2.test.ts`, `mcp-reliability.test.ts` ("an old relay still works") | — |

## 15.5 Repeated updates

| Check | Test |
|---|---|
| Release → candidate → release, no duplicates/resets | `CourseDeliveryGateTests.testUpdatePlannerSelectsLatestCompatibleVersionWithoutDowngrading`, `CourseInstallerTests.testReplacedVersionTreesAreRemovedAndTheActiveOneKept` |
| Migrations idempotent | `CourseBootstrapTests.testFirstLaunchDecisionPersistsBeforeNewProgressIsWritten`, `testDeletingLocalMaterialDoesNotReactivateItOnRelaunch`; `ProgressAndTrainTests.testStableRewardEventIsAppliedOnceAcrossRelaunch`; `LearningBackupTests.testInterruptedRestore…IsNotReplayed` |

Phases 1–7 introduce **no** migration and no change to any existing schema. New persistent data,
all outside every existing learner store:

| New data | Where | Written by | Removing it |
|---|---|---|---|
| `academy/*` metadata (paths, contract, practice starters, learning-state schema) | crabrix-courses, site `content/` | authors | no learner effect |
| `crabrix.ai.*` UserDefaults flags (first use, feedback answered) | iOS app | Learn with AI screen | no learner effect |
| `crabrix.ai.*` localStorage/sessionStorage markers | learner's browser | with-ai page, lesson pages, Playground | no learner effect |
| `academy-events.sqlite` `(day, event, detail, count)` | site `/data` volume | events route | `rm`; accounts unaffected |

Because nothing is migrated, a repeated update (release → candidate → release) has nothing to
re-run: there is no step that could duplicate or reset data. The AI Learning State is never
imported into the app in this release, so the "restore replaces" path is untouched.

## New tests required by this feature

1. Site: Academy API returns only public fields; never `verificationSource`, `challenge`, `checks`,
   `starterProject` secrets; dotted Atlas IDs resolve; ETag/caching headers; unknown ID → 404 JSON.
2. SDK: existing 18 tool names and schemas unchanged (superset assertion replaces the exact list in
   `test/protocol.test.ts:75`); academy tools absent from the bound room server; `/mcp/academy`
   answers without touching rooms; `review_attempt` never returns a verified status;
   `open_playground` performs no relay request; caller progress is not persisted.
3. crabrix-courses: every learning-path step references an existing lesson; paths are not part of
   any pack (`tools/coursepack.py build` output unchanged).
4. iOS (Phase 6 only): the 15.1 fixture before/after hash test.
5. Phases 4–7: practice copies match the lesson text (courses + site tests) and every copy is
   checked in the real browser Playground; learning-state merge never lowers official progress
   (SDK); the backup reader accepts a real app-made file and refuses corrupted ones (SDK); the
   event endpoint stores counters only (site); switches leave lessons, Playground and rooms alone
   (site, SDK).
