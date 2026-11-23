# iOS "Learn with AI" (Phase 6, with the Phase 7 switches and feedback)

Built 24 November 2026 on `feature/academy-mcp`, uncommitted. Contract: `PLAN.md` Phases 5–7.
Additive only: no progress key, backup format, CoursePack, lesson ID, tab, Playground or project
code path changed.

## What was added

| Piece | File |
|---|---|
| Feature switch, MCP URL, five clients' steps (from the website), the four prompts, `lessonPrompt()` mirror, honest limits | `Crabrix/Learn/AcademyAI.swift` |
| AI Learning State v1 encoder and the share-sheet file `crabrix-learning-state.json` | `Crabrix/Learn/AILearningState.swift` |
| `status.json` pause switch | `Crabrix/Learn/AcademyAIStatus.swift` |
| `crabrix.ai.*` flags and the feedback mail draft | `Crabrix/Learn/AILearningFlags.swift` |
| `LearnWithAIView`, `LessonAISheet`, client picker, copy buttons, feedback card | `Crabrix/UI/LearnWithAIView.swift` |
| Library card "Learn with AI" and route `.learnWithAI` (launch argument `-CrabrixLearn with-ai`) | `Crabrix/UI/LearningHubView.swift` |
| Toolbar action "Learn this lesson with AI" (sparkles) on every lesson | `Crabrix/UI/LessonDetailView.swift` (new optional `learnWithAI:` parameter, default `nil`) |

Path for learners (same words as the website): **Learn → Learn with AI → Continue learning**,
switch on **Include my completed lessons**, then **Copy prompt** (the Continue learning prompt with
the state under it), **Share file** or **Copy as text**.

- The toggle is off on every visit and is not stored. Off: `officialProgress` is `null` and the
  Continue learning prompt is the plain website text.
- `currentLesson` is the lesson when the screen is opened from a lesson's sheet ("Connect your agent
  to Crabrix Academy"), otherwise `null`. `learningPath` `null`, `teachingMode` `"guided"`,
  `learner {}`, `aiSession {}`, `evidence []`.
- `completed` = `completedLessonIDs`, `credited` = `creditedLessonIDs` minus completed, both sorted by
  lesson ID, `courseId` from the installed repository or `null`. Pretty-printed, sorted keys.
  An ID outside the schema pattern `^[a-z0-9][a-z0-9.-]{0,159}$` is left out (a reader would reject
  the whole file); all 742 bundled lesson IDs match.
- The lesson sheet holds only public details (courseId, lessonId, title, rule or concept, public URL,
  practice line: the lesson's compiler lab when it has one, otherwise the web Playground through
  `crabrix_academy_open_playground`). "Copy and open Claude/ChatGPT" copies first, then opens
  `https://claude.ai/new` / `https://chatgpt.com/codex` without a `?q=` prefill.
- `LearningRoute` is `Hashable` in `@State` only, never encoded or restored, so the new case cannot
  break saved state (a test pins that it is not `Codable`).

## Stores it reads, and what it writes

Reads, only when the learner exports with the toggle on: `completedLessonIDs` and
`creditedLessonIDs` as `CompilerViewModel` already holds them (persisted at
`crabrix.learn.completedLessonIDs` and `crabrix.learn.creditedLessonIDs.v1`), and the installed
courses for `courseId`. Nothing else: no answers, flashcards, mastery, XP, attempt evidence, code,
projects, room links, Git credentials or paths.

Writes only two `UserDefaults` keys:

| Key | Value |
|---|---|
| `crabrix.ai.firstCopyAt.v1` | seconds since 1970 of the first copied setup step or prompt |
| `crabrix.ai.feedback.v1` | `answered` or `dismissed` |

The exported file is produced by a `DataRepresentation` when a share destination asks for it; the
app writes no file of its own. Feedback goes only into a `mailto:` draft (same pattern as
`ProblemReport`; clipboard fallback when no mail app answers). No events, no analytics, no SDK:
"Data Not Collected" holds.

Network: one `GET https://crabrix.com/api/academy/v1/status.json` when `LearnWithAIView` appears
(never at launch, never on lesson open or in the lesson sheet), ephemeral session, no cookies, cache
or credentials, 5 s timeout, no redirects. `learnWithAI: "paused"` → a pause notice replaces the
setup steps (prompts and export stay). 404 → on. Anything else (offline, timeout, 5xx, non-JSON) →
everything shown with "Offline — you can still copy the steps".

## Switching it off

- Build time: `AcademyAIFeature.isEnabled = false` in `Crabrix/Learn/AcademyAI.swift` hides the
  library card and the lesson action, and the route shows "unavailable".
- Run time: `CRABRIX_AI_LEARNING=off` on the site makes `status.json` say `learnWithAI: "paused"`.
- Debug builds only: `-CrabrixAIStatus on|paused|offline` replaces the status request (UI tests).

## Test evidence

Simulators: "Crabrix iPhone" (iOS 26.5) and a disposable iPad Pro 11-inch (M5), Xcode 27.0,
Debug, one `-derivedDataPath build/dd-learn-with-ai` (deleted afterwards).

| Run | Result |
|---|---|
| New unit tests, `CrabrixTests/LearnWithAITests.swift`: `AILearningStateEncoderTests` (10), `AcademyAIContentTests` (5), `AcademyAIStatusTests` (4), `AILearningFlagsTests` (2), `LearnWithAIDataPreservationTests` (1) | 22 passed, 0 failed |
| Targeted regression set from `regression-suite.md` plus the 22 above | 145 executed, 2 skipped (need production pack directories), 0 failed |
| Classes in `ProgressAndTrainTests.swift` and `TopicMasteryTests.swift` (13 classes) | 68 passed, 0 failed |
| `CrabrixScreenshotTests/LearnWithAIUITests` (scheme `CrabrixScreenshots`), iPhone | 1 passed |
| same, iPad | 1 passed |

The data-preservation test seeds a `UserDefaults` suite with the real keys and types
(completed, credited, answers, reset dates, attempt evidence, drill counters, appearance, install
mode), `crabrix.progress.state.v1` through `CrabrixProgressStore.record`, `crabrix.mastery.v1`
through `TopicMasteryStore`, a flashcards SQLite through `FlashcardReviewDatabase.review` and a
project through `ProjectStore.save`; snapshots every value and file; builds every prompt, exports with
and without progress, sets both feedback flags; then requires every value and file to be
byte-identical and the only new keys to be the two `crabrix.ai.*` flags.

Screenshots (iPhone and iPad, dark, light, paused, offline, accessibility XL text, share sheet,
feedback card, lesson sheet): `build/learn-with-ai-ios/learn-with-ai-{iphone,ipad}-NN-*.png`.

Not run: the full `CrabrixTests` target (disk), `ReleaseScreenshotTests` (its Learn and lesson frames
now include the new card and the sparkles button).
