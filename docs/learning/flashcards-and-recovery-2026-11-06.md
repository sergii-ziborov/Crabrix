# Flashcards and private learning recovery

Native target: Crabrix 1.1.7 (130). This record describes the implementation;
TestFlight and review status require the independent Apple release receipt.

The fourth practice uses the installed, signed curriculum. Only completed lesson
IDs enter the learner's deck. Every one of the current 771 lessons has a concept
card; 761 also have a question card. Ten Atlas questions have too much contextual
code for a short card and are omitted rather than shown with truncated code.
Concepts and answers reuse the same authored lesson material; no generated answer
or new question bank can silently disagree with the lesson. A session contains up
to 12 distinct lessons, with repeated explanations separated.

Don’t know, Hard and Easy save a self-assessment and reveal the answer. Left/right
swipes map to Don’t know/Easy. Show answer permits a preview before grading, and
Next is explicit so an explanation never disappears on a timer. Difficult cards
return sooner. A changed answer receives a new schedule without erasing lifetime
attempts. Reduce Motion replaces rotation with a fade. These self-assessments do
not award compiler-verification credit or submit new achievement events.

## Persistence and recovery

SQLite transactions store each review and its attempt receipt together. Duplicate
submissions cannot reschedule the same attempt. Existing lesson, rating, mastery,
Term Train and Code Recall formats are retained. Each card has a stable identity
and a content revision. Local SQLite uses WAL, FULL synchronization and iOS file
protection; exports are logical records, never a raw copy of a live WAL database.

Profile → Learning backup offers optional automatic private Apple iCloud key-value
storage and explicit Files/iCloud Drive export/import. Automatic upload is off by
default. Each installation has a separate key, so a fresh empty installation does
not overwrite an older installation's recovery copy. Apple synchronization is
asynchronous; “queued” is not a delivery acknowledgement. An account change pauses
automatic uploads. Bounded iCloud quota failures retain the local file and export
path. The personal iCloud path has no Crabrix account, relay or backend database.

The backup allowlist contains lesson completion, saved question indices, mastery,
flashcard schedules, practice session counters, rating/achievement metadata and
lesson reset dates. It excludes projects and resources, credentials, Git access,
room keys, runtime permissions, profile photo and dependency caches. Game Center
alone cannot restore the full lesson history. After reinstalling, missing courses
can be downloaded again; restoration does not install the legacy migration packs.

Files have a versioned compressed envelope, checksum and bounded decoder. The
checksum detects corruption, not authorship or compiler-backed achievement proof.
Files are not password protected. Decode, nesting, counters, identifiers, dates,
record counts and sizes are checked before applying a restore. The cloud snapshot
is capped at 200 KiB, the decoded file at 4 MiB and encoded file at 5 MiB. Larger
histories require the visible file fallback instead of silent truncation.

Restore shows the date and contents first, keeps “Before restore”, then journals
application across SQLite and the explicit learning preference allowlist. A durable
generation prevents replaying an old completed restore over later work. An
unfinished restore is recovered before progress stores cache state on launch. If
recovery cannot finish, new learning is paused: Retry or explicitly return to the
known-good previous snapshot. The interrupted journal and previous copy are kept.
Builds, debug sessions, app locking and in-flight review writes block restoration.
Restoring never imports, launches or grants execution authority to a project.

## Verification

- Signed Simulator build: 1.1.7 (130); 46 targeted tests passed, no failures/skips.
  They cover existing progress/training and bootstrap behavior, all bundled lesson
  card coverage, corruption/version/bounds rejection, interrupted recovery,
  previous-copy fallback, unrelated preference preservation, cloud empty-install
  protection/deduplication, quota/account fallback and restore availability.
- Real SQLite CLI checks passed persistence/reopen, transaction rollback/retry,
  duplicate/conflicting attempt IDs, schedules and changed-answer history.
- All current 771 authored lessons have a concept card; 761 contextual questions
  fit without truncation. The signed legacy 742-step migration fixture is tested
  separately and has not been rewritten to match later editorial content.
- 151 website tests and TypeScript passed. The public Academy release has its own
  [publication verification](../seo/2026-11-06/public-academy.md).
- iPhone Simulator: imported a recovery file through Files and explicit preview/
  confirmation; restored completion and Term Train count; opened the learned
  lesson's card, graded Hard, observed its answer and next-day review schedule.
- Live delivery between two real Apple iCloud accounts/devices has not been
  verified in this environment. No simulated or queued delivery is counted as a
  successful Apple synchronization. Final device-layout checks are recorded in
  the native release receipt, not inferred from the build.
