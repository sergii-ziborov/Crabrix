# iOS learning link (Crabrix 1.2.0, app side)

Built 24 November 2026 on `feature/learning-link`, uncommitted. Contract: `learning-link.md` ("App",
"Keys", "Website API", "Snapshot plaintext", "Inbox message plaintext", and the website
implementation notes). Additive only: no progress key, backup format, CoursePack, lesson ID,
navigation route or tab changed. Version and build numbers are untouched.

## What was added

| Piece | File |
|---|---|
| HKDF-SHA256 keys and tokens, AES-256-GCM envelopes with AAD, strict base64url | `Crabrix/Learn/LearningLinkCrypto.swift` |
| Credentials (`SecRandomCopyBytes`, 18-byte id, 32-byte secret), Keychain item, local state, website API client | `Crabrix/Learn/LearningLinkStore.swift` |
| Snapshot builder (`crabrix.learning-link-snapshot` v1), recent lessons store | `Crabrix/Learn/LearningLinkSnapshot.swift` |
| Installed-lesson catalog, tutor message validation, tutor plan and its store | `Crabrix/Learn/LearningLinkTutor.swift` |
| `LearningLinkController`: connect, debounced sync, inbox, status, disconnect, pause | `Crabrix/Learn/LearningLinkSync.swift` |
| Debug-only in-process API stub for UI tests (`-CrabrixLearningLinkStub`) | `Crabrix/Learn/LearningLinkDebugServer.swift` |
| "Connect my progress", confirmation sheet, client steps, "From your AI tutor" card | `Crabrix/UI/LearningLinkViews.swift` |
| `status.json` `learningLinks` (new `fetchReport()`, `fetch()` unchanged) | `Crabrix/Learn/AcademyAIStatus.swift` |
| Section near the top of Learn with AI; while connected, the public setup collapses to one line | `Crabrix/UI/LearnWithAIView.swift` |
| Tutor card at the top of the Learn library, Learn-appear trigger, recent-lesson recording | `Crabrix/UI/LearningHubView.swift` |
| Repository handoff, progress-change and foreground triggers (one line each) | `Crabrix/UI/ContentView.swift` |

## Stores

Reads only, never writes: `crabrix.learn.completedLessonIDs`, `crabrix.learn.creditedLessonIDs.v1`,
`crabrix.mastery.v1` (through `TopicMasteryStore`), and the installed course repository.

Writes, only while connected (all removed by Disconnect):

| Where | What |
|---|---|
| Keychain, service `com.sergiiziborov.Crabrix.learning-link.v1`, account `learning-link` | `{"linkId","secret"}`; `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, so it is in no iCloud Keychain, device backup or `.crabrixprogress` file |
| `crabrix.ai.learningLink.v1` | connectedAt, lastSyncedAt, snapshot content digest, lastAgentReadAt, pendingInbox. No id, no secret |
| `crabrix.ai.recentLessons.v1` | up to 10 `{courseId, lessonId}`, newest first. The app had no record of the last opened lesson, so this is recorded when a lesson opens in Learn, and only while connected |
| `crabrix.ai.tutorPlan.v1` | at most 20 assignments (newest first), the latest focus, the latest note, the last 100 applied inbox ids |

A `crabrix.ai.learningLink.v1` without its Keychain item (defaults restored onto another device)
counts as not connected and is cleared.

## Behaviour

- **Connect**: confirmation sheet with counts and the exact JSON ("See exactly what is sent"), then
  `POST /api/learn-links/v1/` (hashes only), one retry with a fresh id on 409, then the first
  `PUT …/snapshot/`. Any failure deletes what was made (website and Keychain). A link left in the
  Keychain by an earlier installation is deleted on the website first.
- **Paths end in `/`** (the site uses `trailingSlash: true`). Redirects are never followed, so a
  bearer token is never re-sent anywhere. Ephemeral session: no cookies, cache or stored credentials,
  15 s timeout.
- **Sync** only while connected and not paused: 5 s after a progress change (completions, credits,
  resets, restores), after a return from the background (the first activation at launch is
  ignored), when the Learn library or Learn with AI appears (after 1.5 s), and Sync now. An unchanged
  snapshot (same content digest, `capturedAt` ignored) is not uploaded again for 12 hours, which also
  keeps an active link from the 90-day expiry. One upload at a time; later requests coalesce.
- **Size**: plaintext at most 196,560 bytes (256 KB envelope). Over that, topics are dropped first,
  then recent lessons; progress is never trimmed. Still over: not uploaded, status line says so.
- **Inbox**: when Learn appears or the app returns to the foreground, at most once per 30 s.
  Decrypt with AAD `…|inbox`, validate, merge, save, then `DELETE` every fetched message, valid or
  not (an invalid one never becomes valid). Message ids already applied are skipped, so a message
  whose acknowledgement failed is not applied twice and a dismissed lesson does not return. A changed
  plan schedules a sync so the snapshot echoes it.
- **Validation** (whole message rejected): over 8 KB, not JSON, wrong format or version, unknown
  kind, bad `createdAt`, more than 5 lessons, no valid lesson, a focus with nothing valid.
  Per field (dropped, rest kept): a lesson whose ids fail the Academy pattern, whose lesson is not in
  its installed course, or that belongs to another installed course; text over its limit (reason
  200, goal 300, concept 80, note 500, agent 60, counted in code points like the SDK), more than 10
  concepts, a `pathId` that is not `^[a-z0-9-]{1,128}$`. A lesson of a course that is not installed
  is kept and shown with "Download this course in Learn to open the lesson" and no Open button.
  Text is normalised exactly like the SDK's `plainText` (hidden and control characters to spaces,
  white space collapsed, one line) and shown with `Text(verbatim:)`: never Markdown, links or
  instructions. `agent` is optional. Future `createdAt` is clamped to now.
- **Card**: at the top of the Learn library while there are open assignments or a focus. Lesson
  title and course from the installed repository, the reason, Open (`[.course, .lesson]`, the same
  route as the course map and Weak Topics), Dismiss per item and for the focus. An assignment is done
  only when `completedLessonIDs` contains it (credits do not count); done ones leave the card and
  are counted in its footer.
- **Errors**: offline, 429 (respects `Retry-After`, at most 1 h) and 5xx only change the status
  line. 503 pauses until the next foreground. 404 means revoked or expired: the device disconnects,
  wipes the secret and says so.
- **Disconnect** (destructive alert): `DELETE …/<linkId>/`, then wipe the Keychain item and the
  three `crabrix.ai.*` keys. Offline: wipe anyway, keep only the link id and the write token in a
  second Keychain item (`pending-deletion`, this device only; no key, no read token) and retry the
  `DELETE` whenever the app becomes active or Learn appears, until the website answers 204 or 404.
  The learner is told the copy is deleted the next time they are online and to remove the
  connector from their agent (an agent's reads would otherwise keep the link alive).
- **Pause**: `status.json` `learningLinks: "paused"` (or `learnWithAI: "paused"`, or a 503) hides
  Connect and stops every request. Connected learners still see their URL and Disconnect.
- **Snapshot** follows the SDK validator (`crabrix-sdk/src/learning-link.ts`): every id matches the
  Academy pattern (others are left out), `app` ≤ 40, courses ≤ 100 with titles ≤ 120 code points,
  topics ≤ 30 weakest by correct ratio, recent ≤ 10, `tutor.assigned[].reason` and `tutor.note`
  included and re-checked so a stored value can never make the server refuse the snapshot.

Debug builds only: `-CrabrixLearningLinkStub` (in-process API, throwaway defaults suite, in-memory
secret), `-CrabrixLearningLinks on|paused`, and `-CrabrixLearningLinkOrigin` /
`-CrabrixLearningLinkMCPOrigin` for loopback origins (`http://127.0.0.1` or `localhost` only).
Release builds always use `https://crabrix.com`.

## Test evidence

Simulator "Crabrix iPhone", Xcode 27.0, Debug, `-derivedDataPath build/dd-learning-link` (deleted
afterwards).

```sh
xcodebuild test -project Crabrix.xcodeproj -scheme Crabrix \
  -destination 'platform=iOS Simulator,name=Crabrix iPhone' -derivedDataPath build/dd-learning-link \
  -only-testing:CrabrixTests/LearningLinkCryptoTests -only-testing:CrabrixTests/LearningLinkSnapshotTests \
  -only-testing:CrabrixTests/TutorMessageValidationTests -only-testing:CrabrixTests/TutorPlanMergeTests \
  -only-testing:CrabrixTests/LearningLinkAPITests -only-testing:CrabrixTests/LearningLinkControllerTests \
  -only-testing:CrabrixTests/LearningLinkKeychainTests -only-testing:CrabrixTests/LearningLinkDataPreservationTests \
  -only-testing:CrabrixTests/LearnWithAIDataPreservationTests -only-testing:CrabrixTests/LearningBackupTests \
  -only-testing:CrabrixTests/LessonBridgeTests -only-testing:CrabrixTests/CourseBootstrapTests

TEST_RUNNER_CRABRIX_LINK_SCREENSHOTS=$PWD/build/learning-link-ios \
xcodebuild test-without-building -project Crabrix.xcodeproj -scheme CrabrixScreenshots \
  -destination 'platform=iOS Simulator,name=Crabrix iPhone' -derivedDataPath build/dd-learning-link \
  -only-testing:CrabrixScreenshotTests/LearningLinkUITests
```

| Run | Result |
|---|---|
| New unit tests in `CrabrixTests/LearningLinkTests.swift`: crypto 8, snapshot 8, validation 7, plan 5, API 6, controller 12, Keychain 1, data preservation 1 | 48 passed |
| With `LearnWithAIDataPreservationTests` (1), `LearningBackupTests` (5), `LessonBridgeTests` (15), `CourseBootstrapTests` (11) | 80 executed, 79 passed, 1 skipped (`testProductionSignedBridgePacksInstallAndDecode`, needs production pack directories), 0 failed |
| `LearningLinkUITests/testConnectMyProgressTutorCardAndDisconnect` (stub, no network for the link) | passed |
| `LearningLinkUITests/testEndToEndAgainstWebsiteAndMCP` with `TEST_RUNNER_CRABRIX_LINK_E2E_SITE=http://127.0.0.1:3471` and `…_E2E_MCP=http://127.0.0.1:3472` (local site and SDK 0.7.0 `serve-http`) | passed: connect, `crabrix_my_progress`, `crabrix_assign_lessons`, a read-token inbox POST, the card, an empty inbox afterwards, `crabrix_my_lesson`, Disconnect, then 404 and `LEARN_LINK_NOT_FOUND`. Skipped when the variables are not set |
| The same test against production (`…_E2E_SITE=https://crabrix.com`, `…_E2E_MCP=https://crabrix.com`, no override) | **not run**: free disk space fell below 6 GB. A failed run deletes its production link in `tearDown`; a link left in the app is disconnected at the start of the next run |

- Crypto: the app reproduces `learning-link-vectors.json` exactly (key, both tokens, both token
  hashes, the ciphertext from the vector nonce, decryption with its AAD), and the test checks its
  embedded copy against the file.
- Data preservation: seeds the same real keys, types and files as the Learn with AI test, then
  connects, records a lesson, syncs, applies two inbox messages, dismisses, syncs again and
  disconnects. While connected every seeded value and file is byte-identical and the only new keys
  are the three `crabrix.ai.*` keys (plus the Keychain item); after Disconnect the defaults domain
  equals the seeded one exactly. The uploaded snapshot has none of the seeded answers, evidence,
  points, project names or code.
- SDK compatibility: `testSnapshotsFromSampleProgressPassTheSDKRules` ports the SDK validator's
  rules; additionally both sample snapshots it writes (a fixture and a hostile one with 130 courses,
  emoji titles, invalid ids and oversized tutor text) were uploaded to the local site and read back
  through the real SDK `crabrix_my_progress` without error.

Screenshots (iPhone, dark, light, accessibility XL, paused, local end to end):
`build/learning-link-ios/learning-link-iphone-*.png`.

Not run: the iPad simulator (disk), the full `CrabrixTests` target, `LearnWithAIUITests` and
`ReleaseScreenshotTests` (the new section now sits above "Connect your agent" in Learn with AI, so
their frames move down).
