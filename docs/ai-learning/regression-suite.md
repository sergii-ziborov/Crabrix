# Regression suite — run before and after every Academy MCP change

Baselines measured 23 November 2026 on the `feature/academy-mcp` branches before feature code landed.

| Repo | Command | Baseline |
|---|---|---|
| Crabrix site | `cd site && npm test` | 168 tests, 168 pass, 0 fail |
| Crabrix site | `cd site && node_modules/.bin/tsc --noEmit -p .` | pass (also passed at `cf19476` earlier today) |
| Crabrix site | `cd site && npm run build` (a first run may fail once with Next's upgrade nudge; retry) | passed at `cf19476`; not re-run for this audit |
| Crabrix site | browser check: `node build/bridges-site-20261123/check.cjs <origin> <outdir>` (390/820/1440 px, status, overflow, page errors, broken images) | 18/18 clean on production after the 23 Nov release |
| crabrix-courses | `python3 -m unittest discover -s tests` | 39 tests on `main` `cc73b6d`, OK (1 skipped); 42 with the in-progress `tests/test_academy_metadata.py` |
| crabrix-courses | `python3 tools/coursepack.py validate --courses courses/ --schema schemas/` | `Validated 10 courses and 839 lessons` |
| crabrix-courses | `python3 -I editorial/bridges_20261123/<course>/verify.py` (both bridges) and `python3 editorial/bridges_20261123/verify_what_is_rust.py` | 20/20 lessons each, 0 failures; what-is-rust 6/6 |
| crabrix-sdk | `npm test` | 83 tests, 83 pass, 0 fail |
| crabrix-sdk | `npx tsc --noEmit` | pass |

## iOS (targeted; the full suite is too large for this Mac's free disk)

Run on the "Crabrix iPhone" Simulator, Debug, with `-derivedDataPath build/dd-<name>` and delete it
afterwards:

```sh
xcodebuild test -project Crabrix.xcodeproj -scheme Crabrix \
  -destination 'platform=iOS Simulator,name=Crabrix iPhone' -derivedDataPath build/dd-academy \
  -only-testing:CrabrixTests/LearningBackupTests \
  -only-testing:CrabrixTests/LearningCloudBackupTests \
  -only-testing:CrabrixTests/CourseBootstrapTests \
  -only-testing:CrabrixTests/CourseInstallerTests \
  -only-testing:CrabrixTests/CoursePackVerifierTests \
  -only-testing:CrabrixTests/CourseDownloadManagerTests \
  -only-testing:CrabrixTests/InstalledCourseRepositoryTests \
  -only-testing:CrabrixTests/LessonBridgeTests \
  -only-testing:CrabrixTests/RustLessonProgressionTests \
  -only-testing:CrabrixTests/ProgressAndTrainTests \
  -only-testing:CrabrixTests/ProjectAuthoringTests \
  -only-testing:CrabrixTests/ProjectImportTests \
  -only-testing:CrabrixTests/FlashcardDeckTests \
  -only-testing:CrabrixTests/TopicMasteryTests
```

Network-dependent gates (run when packs or catalogs change): `CourseDeliveryGateTests`,
`PracticalCourseUpdateTests`, `InterviewCourseUpdateTests`, `WorkflowRouteTests` (some skip unless
their env flags are set). Production-pack check: `TEST_RUNNER_CRABRIX_BRIDGE_PACKS=<dir>` with
`LessonBridgeTests/testProductionSignedBridgePacksInstallAndDecode`. UI: scheme
`CrabrixScreenshots`, `-only-testing:CrabrixScreenshotTests/BridgeCourseTests`.

Last measured: `LessonBridgeTests` + `CourseBootstrapTests` + `RustLessonProgressionTests` = 42
passed, 0 failed (catalog 27, 23 Nov); `BridgeCourseTests` 1 passed.

Phases 1–3 do not change the app; the iOS set is a guard, required again in Phase 6.

## Pass criteria

Every baseline count above is equal or higher, with 0 failures. New tests add to the counts; no
existing test may be deleted or weakened except to replace an exact tool-name list with a superset
assertion that still lists the 18 existing names unchanged.
