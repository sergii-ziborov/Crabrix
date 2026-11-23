# Academy progress compatibility audit (Phase 0)

Audited 23 November 2026, read-only, at Crabrix `main` `9517ad1` (branch `feature/academy-mcp`, no code
changes), crabrix-courses `main` `cc73b6d`, crabrix-sdk `main` `729e747`. File references are
`path:line` in those trees. Nothing here was migrated or changed.

**Bottom line for the Academy MCP:** official progress exists only on the learner's iOS device (and
in the learner's own backups). The website stores no lesson progress. The SDK and relay store no
progress at all. A read-only Academy MCP that serves public lesson content cannot read, write or
compete with any of the stores below.

## 1. iOS — where educational state lives

All `UserDefaults` keys are in the app's standard domain (app container; no App Group for these keys).

| State | Storage | Writer(s) | Linked to lessons by | In learning backup? |
|---|---|---|---|---|
| Completed lessons | `UserDefaults` `crabrix.learn.completedLessonIDs` (sorted `[String]`) — `Crabrix/Features/Compiler/CompilerViewModel.swift:357`, persisted at `:2999` | `CompilerViewModel.completeLesson` `:1957`; removed only by `resetCourseProgress` `:1988`; restore `LearningProgressPreferences.apply` `Crabrix/Progress/LearningProgressArchive.swift:54` | lesson ID (flat, global set) | yes |
| Bridge credits | `UserDefaults` `crabrix.learn.creditedLessonIDs.v1` (`[target: bridge lesson]`, written only when non-empty) — `LearningProgressArchive.swift:7`, `CompilerViewModel.swift:3003` | `completeLesson` (via `LessonCredits.completing`), `resetCourseProgress` (`LessonCredits.afterReset`), restore | lesson ID → bridge lesson ID | yes (optional field, `LearningProgressBackup.swift:20`) |
| Quick-check answers | `UserDefaults` `crabrix.learn.lessonAnswerIndices` (`[lessonID: Int]`) — `CompilerViewModel.swift:358` | `recordLessonAnswer` `:2016` (first committed **correct** answer only; `ContentView.swift:334`), cleared per lesson by course reset | lesson ID; value is the **authored** answer index (display shuffle is view-only, `RustLessonProgression.swift` `LessonAnswerOrder`) | yes |
| Lesson reset dates | `crabrix.learn.lessonResetDates.v1` — `CompilerViewModel.swift:361` | `resetCourseProgress` | lesson ID | yes |
| Compiler-lab attempt evidence | `crabrix.learn.attemptEvidence.v1` (JSON, last 500) — `CompilerViewModel.swift:359`, append `:3011` | lab Run validation `:2971` | `LessonAttemptIdentity` (course, language, contentVersion, lessonID, validator, toolchain, project revision) | **no** |
| Automatic repair fingerprints | `crabrix.learn.automaticRepairs.v1` — `CompilerViewModel.swift:360` | lab repair flow `:1941` | project UUID | no |
| Rating / XP / achievements / counters | `crabrix.progress.state.v1` = `CrabrixProgressState` (`totalPoints`, `lessonsCompleted`, `unlockedAchievementIDs`, `processedEventKeys`, … `Crabrix/Progress/CrabrixProgress.swift:14`) — `CrabrixProgressStore.swift:18` | `CrabrixProgressStore.record(_:eventKey:)` `:122`; lesson XP is awarded once per `lesson:<id>:first-completion` event key from `ContentView.swift:758` (observes `completedLessonIDs`, so **credits never award XP**) | event keys, solved Atlas pattern IDs | yes (`progressData`) |
| Topic mastery (spaced repetition) | `crabrix.mastery.v1` — `Crabrix/Progress/TopicMastery.swift:150` | practice/term train | topic = lesson ID | yes |
| Flashcard reviews | SQLite `Application Support/Crabrix/Learning/flashcards.sqlite` — `Crabrix/Progress/FlashcardReviewStore.swift:111` | Flashcards UI | card ID (lesson-derived) | yes |
| Drill session counters | `crabrix.learn.trainingSessions`, `.recallSessions`, `.flashcardSessions` — `LearningHubView.swift:287-289` | Learn hub | — | yes |
| Typing ledger | `crabrix.typing.v2` — `Crabrix/Progress/TypingLedger.swift:22` | editor | revisions | no |
| Code contribution | `crabrix.contribution.v3` (legacy `.v2`) — `Crabrix/Progress/CodeContribution.swift:313-314` | editor | — | no |
| Installed CoursePacks | `Application Support/Crabrix/Courses/<course>/<lang>/<version>` + index + install journal — `CourseBootstrap.swift:69`, `CourseInstaller.swift:177-221` | `CourseInstaller.install` / `uninstall` `:79` | course ID + contentVersion | no (re-download) |
| Accepted catalog | `Application Support/Crabrix/Courses/catalog-state.json` — `AcademyContentStore.swift:105`; bundled baseline `Crabrix/Resources/ActiveCourseCatalog/catalog.v1.json` (sequence 27 on main) | `CourseCatalogClient` | catalog sequence | no |
| First-launch mode | `crabrix.academy.initialInstall.v1` — `CourseBootstrap.swift:12` | `CourseLaunchPolicy.resolve` (reads legacy keys `:13-27`, writes mode once) | — | no |
| My Projects (incl. lesson labs and Examples copies) | `Application Support/Crabrix/projects/` + `project-index.json` — `Crabrix/Projects/ProjectLibrary.swift:119-124`; provenance `CrabrixProject.Provenance` (`source: academy`, `CourseOrigin{courseID, contentVersion, lessonID, templateHash}`; Examples use `lessonID` `example/<id>`, never lesson evidence — `CrabrixProject.swift:58-75`) | ProjectLibrary transactions with previous/recovery snapshots (`:153-196`) | project UUID; lesson ID in provenance | no (project export / recovery ZIP `:303-309`) |
| Git repositories | `Application Support/Crabrix/repositories/` — `ProjectLibrary.swift:720` | Git workspace | project UUID | no |
| Git HTTPS credentials | Keychain service `com.sergiiziborov.Crabrix.git-https.v1` — `Crabrix/Projects/GitCredentialVault.swift:11` | Git UI | — | no (never in backups) |
| Learning backups | local `Latest.crabrixprogress`, `Before restore.crabrixprogress`, `restore-journal.json` in the Learning directory (`LearningBackupCoordinator.swift:166,209,256`); optional iCloud key-value store `crabrix.learning.backup.v1.*` (`:20,43-45`, opt-in `crabrix.learning.cloudBackup.enabled`) | `LearningBackupCoordinator` | snapshot ID | — |

Not found: any server-side or cross-device sync of iOS progress other than the opt-in iCloud
key-value backup (searched `Crabrix/Progress`, `Crabrix/AcademyContent`, `Crabrix/Social`).
Game Center (`crabrix.gameCenter.enabled`, `Crabrix/Social/GameCenterService.swift:127`) is opt-in
reporting only, not a progress source.

## 2. How completion is decided

| Lesson evidence (`LessonEvidence`, `Crabrix/Learn/RustLearningPath.swift:77-93`) | Completed when |
|---|---|
| `reasoning(correctAnswer:)` (planned lessons) | the learner commits the correct quick-check answer and continues: `LearningHubView.completeAndContinue` `:252` → `ContentView.swift:325` → `completeLesson` |
| `compilerRun`, `repair`, `algorithmChallenge` (labs) | a **Run** in the lesson's lab project passes `LessonEvidenceValidator.validateCompilerAttempt` (`RustLearningPath.swift:339`, called `CompilerViewModel.swift:2971`); every attempt appends attempt evidence; pass → `completeLesson` `:2990` |
| bridge credit | completing a bridge lesson credits installed targets; counts as learned for the path, never as completion |

Only the app writes these. No network call, AI, website or MCP path can mark a lesson complete.

## 3. Lifecycle

| Event | Effect on progress |
|---|---|
| Course update | `CourseInstaller` copies into `.staging/<uuid>`, writes a journal, moves into place and rewrites the index; a failure keeps the old pointer (`CourseInstaller.swift:195-228`). Progress is keyed by lesson ID in `UserDefaults`, independent of pack files, so an update cannot reset it. Stable IDs and answer indices are enforced by crabrix-courses `tests/test_practical_paths.py` and `test_academy_corrections.py`. |
| Course reset (user) | `resetCourseProgress` clears that course's completions, answers and credits; keeps XP, achievements, attempt evidence and projects (`CompilerViewModel.swift:1982-2013`). |
| App update | Same container; `CourseLaunchPolicy` keeps the saved mode; bundled catalog newer than the accepted one is used (`CourseBootstrapTests.testCatalogOlderThanTheBundledOneIsUpToDateAndNeverReplacesIt`). |
| App reinstall | iOS deletes the container: all `UserDefaults` keys above, `Application Support/Crabrix` (projects, Git, courses, flashcards) are gone. Recovery only from an exported `.crabrixprogress` file or the opt-in iCloud backup (learning state only), and from user-exported project ZIPs. Keychain items may persist (iOS behaviour), not used for progress. |
| Restore | Replaces exactly the allowlisted learning keys (`LearningProgressArchive.swift:54-75`), keeps other preferences, writes `Before restore.crabrixprogress`, journaled and retried on launch. **Restore replaces, it does not merge.** Attempt evidence, typing, contribution are not restored. |

## 4. Website

| State | Storage | Notes |
|---|---|---|
| Optional accounts | SQLite `AUTH_DB_PATH` or `auth-data/accounts.sqlite`: `users(id, username, password_hash, recovery_hash, created_at)`, `sessions`, `rate_limits` — `site/lib/auth-store.ts:20-33` | No lesson progress. |
| Account export | `site/app/account/export/route.ts` returns username, createdAt and `"websiteLearningProgress": "Not collected"` | Confirms no web progress. |
| Lesson progress on the web | **none** — searched `site/app`, `site/lib`, `site/components` for progress/completion storage; account page text says progress stays on the device (`site/app/account/page.tsx:12`) | |
| Playground drafts | IndexedDB `crabrix.playground.drafts` / store `drafts` (source only, max 32) — `site/lib/playground-drafts.ts:6-8`; opt-in flag `localStorage crabrix.playground.keepDrafts.v1` | Room secrets never stored. |
| Playground preferences | `localStorage crabrix.playground.preferences.v1`, `crabrix.playground.format` (v2 flag) — `components/playground/workspace.tsx:51,118,185`; theme key `site/lib/theme.ts:24` | |
| Relay rooms | in-memory `Map` in the site process, limits `ROOM_LIMITS` — `site/lib/playground-rooms.ts:44,64` | Ciphertext only; lost on restart. |

## 5. SDK / MCP

Nothing persistent: no file writes in `crabrix-sdk/src` (only `doctor.ts` reads the home path for
masking). Room keys and plaintext live in process memory; the remote MCP (`src/remote.ts`) holds a
room key per session (max 64 sessions, 30 min idle, `remote.ts:26`), writes nothing to disk.

## 6. Spec §8.1 answers

| Question | Answer |
|---|---|
| Where is progress stored? | iOS only: §1 table. Web: none. SDK: none. |
| Who may change it? | Only app code paths listed in §1/§2, and user-initiated restore. |
| How are answers linked to lesson IDs? | `[lessonID: authored answer index]`; first correct commit only. |
| How are completed tasks determined? | §2: quiz evidence or validated compiler Run; credits are separate. |
| How do course updates work? | Atomic staged install with journal; progress untouched (§3). |
| Where is web users' progress? | Not collected. |
| How does iOS local progress work? | `UserDefaults` + `flashcards.sqlite`, optional backups (§1). |
| What happens on reinstall? | Container is wiped; recover from `.crabrixprogress` export or opt-in iCloud backup; projects only from exported ZIPs. |
| How are projects saved? | `Application Support/Crabrix/projects` with transactional snapshots; Git separate; credentials in Keychain. |
| Recovery mechanisms? | Learning backup (file, iCloud KVS, Before-restore copy, restore journal); project previous/recovery snapshots and recovery ZIP; course installer journal recovery. |

## 7. Consequences for the plan

1. Phase 1 (read-only Academy MCP) touches none of these stores. Keep it that way: no progress
   parameter is ever persisted; caller-supplied `completedLessonIds` stay in the request.
2. Phase 5 (progress integration) has exactly one existing portable format: the
   `.crabrixprogress` learning backup. It contains `completedLessonIDs`, answers, mastery,
   flashcards and credits, but **not** attempt evidence. A read-only importer for agents should
   parse that file locally (never upload it) and label everything "from your backup file".
3. Because restore replaces rather than merges, any future "import AI Learning State" into the app
   must not reuse the restore path; it needs its own merge that only adds.
4. The website has no progress to integrate; "Continue learning" on the web can only use what the
   learner provides.
