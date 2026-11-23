# Learn Rust with Your Coding Agent — implementation plan and API contract

Status: phases 0–3 built, phases 4–7 in progress on `feature/academy-mcp` in Crabrix,
crabrix-courses and crabrix-sdk (23 November 2026). Nothing in this work changes existing progress, CoursePacks,
lesson IDs, Playground behaviour or existing MCP tools. Production deployment, npm/crates
publication and app builds happen only after the owner's separate permission (spec §17.5).

## Principle

Additive only. The Academy stays the source of truth (crabrix-courses). AI is an optional
teacher on top of it. Three equal ways to learn: Traditional, AI-Assisted, Agent-First.

## Pieces

| Piece | Where | What |
|---|---|---|
| Learning paths, teaching contract | `crabrix-courses/academy/` | Navigation metadata over existing lesson IDs; versioned teaching rules. Not part of any CoursePack. |
| Public Academy API (read-only) | site `app/api/academy/v1/…` | JSON views of the public web corpus, examples, paths and the contract. No accounts, no user data. |
| Academy MCP tools `crabrix_academy_*` | crabrix-sdk `src/academy*.ts` | Added to the local (unbound) Crabrix MCP server, and served alone, read-only, at `https://crabrix.com/mcp/academy` by the existing remote MCP process. Room tools, agent links and bound room sessions are unchanged. |
| Skill `crabrix-learn-rust` | crabrix-sdk `skills/` | New; `crabrix-handoff` unchanged. |
| `/learn/with-ai/` + entry points | site | New page; a block on `/learn/`; "Learn this lesson with AI" on lesson pages. Old URLs unchanged. |
| Compatibility audit | `docs/ai-learning/academy-progress-compatibility.md` and siblings | Phase 0 deliverables. |

Phases 4–7 (contracts below): Playground practice copies for more lessons (4), a portable
AI Learning State with an add-only merge and read-only progress import (5), an iOS "Learn with
AI" entry (6), switches, minimal events, feedback and a staged launch (7).

## Public Academy API v1 (contract shared by site and SDK)

Base: `https://crabrix.com/api/academy/v1`. All responses `application/json` unless noted,
`Cache-Control: public, max-age=300`, `ETag`. Every JSON body has `schemaVersion: 1` and
`catalogVersion` (first 12 hex of the crabrix-courses commit the site was synced from).
Errors: `{ "schemaVersion": 1, "error": { "code": "NOT_FOUND" | "BAD_REQUEST", "message": "…" } }` with 404/400.

### `GET /index.json`

```json
{
  "schemaVersion": 1,
  "catalogVersion": "cc73b6dd5d5d",
  "source": { "repository": "https://github.com/sergii-ziborov/crabrix-courses", "commit": "<40 hex>" },
  "platforms": {
    "web": "Every lesson listed here is public at its url.",
    "app": "The Crabrix iOS app installs signed CoursePacks; a lesson can reach the app later than the website."
  },
  "courses": [
    { "id": "basics", "title": "Rust Basics", "subtitle": "…", "level": "BEGINNER", "order": 0,
      "url": "https://crabrix.com/learn/basics/", "lessonCount": 29,
      "units": [ { "id": "foundations", "title": "…", "subtitle": "…", "lessonIds": ["what-is-rust", "…"] } ] }
  ],
  "lessons": [
    { "courseId": "basics", "unitId": "foundations", "id": "what-is-rust", "title": "What Rust Is",
      "concept": "…", "summary": "… (≤ 300 chars, plain text, backticks kept)", "rule": "…",
      "minutes": 7, "exerciseKind": "planned", "url": "https://crabrix.com/learn/basics/what-is-rust/",
      "playground": false, "bridgeFrom": null, "credits": [], "appAvailability": "released" }
  ],
  "paths": [ { "id": "rust-for-nodejs", "title": "…", "audience": "…", "description": "…", "stepCount": 40 } ],
  "examples": [ { "id": "ascii-histogram", "title": "…", "detail": "…", "difficulty": "starter",
                  "category": "graphics", "concepts": ["arrays"] } ],
  "teachingContract": { "version": "1.0.0", "url": "https://crabrix.com/api/academy/v1/teaching-contract.md" }
}
```

`playground` is true when `/playground/?lesson=<courseId>/<lessonId>` opens a starter
(lessons with `playgroundProject`, and Algorithm Atlas steps that have a recorded trace).
`bridgeFrom` is `"c" | "javascript" | "typescript" | null`; `credits` lists
`"courseId/lessonId"` for bridge lessons. Algorithm Atlas steps are included (600).
`appAvailability` is `"released"` (in the App Store app) or `"next-app-version"` (web first;
the bridge courses and "What Rust Is" until Crabrix 1.1.9 ships). The lesson view has it too.

### `GET /lessons/{courseId}/{lessonId}.json`

```json
{
  "schemaVersion": 1, "catalogVersion": "…",
  "courseId": "…", "courseTitle": "…", "unitId": "…", "unitTitle": "…", "id": "…", "title": "…",
  "concept": "…", "minutes": 7, "exerciseKind": "planned", "url": "https://crabrix.com/learn/…/",
  "writing": { "summary", "rule", "explanation", "exampleCode", "exampleCaption", "task", "success",
               "practiceCode", "question", "answers", "correctAnswer", "feedback", "recall" },
  "depth": { "traceSteps", "misconception", "correction", "transferChallenge", "connections" },
  "algorithm": { …public Atlas fields… } | null,
  "bridge": { "from", "fromLabel", "fromCode", "fromCaption", "contrasts", "credits" } | null,
  "illustration": { "url": "https://crabrix.com/learn-media/…png", "alt": "…", "caption": "…" } | null,
  "playground": { "available": true, "url": "https://crabrix.com/playground/?lesson=…" } | { "available": false, "url": null },
  "related": [ { "courseId", "lessonId", "title", "relation": "previous" | "next" | "covers" | "coveredBy" } ]
}
```

Only fields already published on the lesson web page. Private grading harnesses and check
files are never in the web corpus and never in this API.

### `GET /paths/{pathId}.json`

`{ schemaVersion, catalogVersion, id, title, audience, description, steps: [ { courseId, lessonId, title, url, note } ] }`

### `GET /examples/{exampleId}.json`

`{ schemaVersion, catalogVersion, id, title, detail, difficulty, category, concepts, readme, files: { "Cargo.toml": "…", "src/main.rs": "…" }, entryFile, illustration: { url, alt, caption } | null }`

### `GET /teaching-contract.md`

`text/markdown`, the versioned teaching contract.

## MCP tools (crabrix-sdk)

All read-only (`readOnlyHint: true`, `openWorldHint: true`), namespaced `crabrix_academy_*`,
fetched from the API above (`CRABRIX_ACADEMY_ORIGIN`, default `https://crabrix.com`), cached
in memory by ETag. No tool sends user code, room links or progress to the server.

| Tool | Input | Output |
|---|---|---|
| `crabrix_academy_catalog` | `courseId?`, `cursor?`, `limit?` (≤ 50) | Courses (compact), or one course's units with lesson ids/titles, paginated |
| `crabrix_academy_search` | `query`, `courseId?`, `limit?` (≤ 20), `cursor?` | Ranked lessons: ids, title, concept, short summary, url |
| `crabrix_academy_get_lesson` | `courseId`, `lessonId`, `view: summary \| teaching \| full` | The lesson, unchanged text; `teaching` omits answers |
| `crabrix_academy_get_exercise` | `courseId`, `lessonId` | Task, starter (`practiceCode` / Atlas input), success criteria, the quick-check question without its answer, how the app verifies it, Playground link |
| `crabrix_academy_get_hint` | `courseId`, `lessonId`, `level` 1–5, `revealSolution?` | Graded help from the lesson's own material; level 5 needs `revealSolution: true` and returns only what the Academy publishes (worked example, Atlas expected answer) |
| `crabrix_academy_learning_path` | `pathId?`, `completedLessonIds?`, `cursor?` | Path list, or one path's steps marked done only from the ids the caller supplies |
| `crabrix_academy_get_examples` | `query?`, `exampleId?`, `includeSource?` | Example list, or one example (source only when asked) |
| `crabrix_academy_open_playground` | `courseId`, `lessonId` | `{ available, url, note }`; never creates a room |
| `crabrix_academy_review_attempt` | `courseId`, `lessonId`, `evidence` | The lesson's own rubric and a status that is at most `ai_reviewed`; never `verified` |
| `crabrix_academy_next` | `pathId?`, `completedLessonIds?`, `currentLessonId?` | Next steps; states that progress came from the caller, not from Crabrix |

Resources: `crabrix://academy/teaching-contract` (markdown), `crabrix://academy/paths` (json).
Prompts: `learn_rust_with_crabrix` (`background`: beginner \| nodejs \| c \| experienced, `mode`:
guided \| socratic \| pair \| review, `goal?`) and `continue_crabrix_learning`.

Remote: `POST/GET/DELETE https://crabrix.com/mcp/academy` — stateless Streamable HTTP, only
the academy tools/resources/prompts, no room access. Existing `/mcp/<room>/…` agent links
are matched first and behave exactly as before.

## Progress rule

AI never writes official progress. Status vocabulary: `verified` exists only inside the
Crabrix app/Academy checks; tools return `ai_reviewed`, `compiled_by_learner` (learner
reported) or `not_verified`. `completedLessonIds` given to tools are labelled as
caller-supplied and are never stored.

## Phase 4 — Playground practice copies

The Playground keeps its editor, Run, Debug, Cargo profile and permissions. Nothing new checks
code. `/playground/?lesson=<courseId>/<lessonId>` keeps opening the lesson's own starter
(`playgroundProject`) or Atlas trace exactly as before. In addition it opens a **practice copy**
for lessons listed in crabrix-courses `academy/practice-starters.json`:

```json
{ "schemaVersion": 1, "generatedFrom": "<crabrix-courses commit>", "checkedWith": "rustc 1.x (host, --edition 2021, check only)",
  "starters": [ { "courseId": "basics", "lessonId": "variables", "source": "practiceCode" | "exampleCode",
                  "sha256": "<hex of the source text>", "check": "compiles" | "fails-by-design", "edition": "2021" } ] }
```

- `source` is the lesson field the copy is made from, unchanged. The site serves a copy only
  while the field's current sha256 equals the recorded one, so an edited lesson never opens a
  stale or unchecked starter.
- `practiceCode` that fails to compile is listed only for lessons whose task is to fix it
  (`fails-by-design`); the Playground notice says so.
- The copy is a new, unsaved Playground document (`Cargo.toml` + `src/main.rs`). Opening it never
  overwrites a draft: the existing draft store keeps its own entries.
- API: the lesson view's `playground` becomes `{ available, url, kind }`, `kind` =
  `"lesson-project" | "practice-copy" | "algorithm-trace" | null`. `index.json` lessons keep
  `playground: boolean`.
- Examples: `/playground/?example=<exampleId>` opens a copy of an Examples project (all 46 are
  std-only, ≤ 3 files). The example view gets `playground: { available, url, kind: "example-copy" }`.
  The original Example is never changed; the copy is a new unsaved document.

## Phase 5 — AI Learning State v1

A portable JSON file the learner owns. It is never the official record and never replaces it.
Canonical schema: crabrix-courses `academy/learning-state.schema.json`. File name suggestion
`crabrix-learning-state.json`.

```json
{
  "format": "crabrix.ai-learning-state",
  "schemaVersion": 1,
  "updatedAt": "2026-11-23T18:00:00Z",
  "producer": "crabrix-ios 1.2.0 (140)",
  "learningPath": "rust-for-nodejs",
  "teachingMode": "guided",
  "currentLesson": { "courseId": "ownership", "lessonId": "borrowing" },
  "learner": { "background": "nodejs", "knownTechnologies": ["TypeScript", "Fastify"],
               "preferredLanguage": "en", "goal": "Write backend services in Rust" },
  "aiSession": { "lastSummary": "", "suggestedNextLesson": null, "conceptsNeedingReview": ["borrowing"] },
  "officialProgress": {
    "source": "crabrix-ios",
    "capturedAt": "2026-11-23T18:00:00Z",
    "appVersion": "1.2.0 (140)",
    "completed": [ { "courseId": "basics", "lessonId": "variables" } ],
    "credited": [ { "courseId": "basics", "lessonId": "functions", "viaLessonId": "node-functions" } ]
  },
  "evidence": [ { "courseId": "basics", "lessonId": "loops", "kind": "ai_reviewed", "at": "2026-11-23T18:00:00Z" } ]
}
```

Fields and limits (a reader rejects a file outside them; unknown keys are dropped and reported):

| Field | Rule |
|---|---|
| `format`, `schemaVersion` | exactly `crabrix.ai-learning-state`, `1`. A higher version is refused with "needs a newer Crabrix", never partly read. |
| `updatedAt`, `capturedAt`, `at` | RFC 3339 UTC, 2020–2100. |
| `producer` | ≤ 80 chars, informational. |
| `learningPath` | a path id or null. `teachingMode`: `guided`/`socratic`/`pair`/`review`. |
| `currentLesson`, `suggestedNextLesson` | `{courseId, lessonId}` or null; ids `[a-z0-9][a-z0-9.-]*`, ≤ 160. |
| `learner` | `background` `beginner`/`nodejs`/`c`/`experienced`/`other`/null; `knownTechnologies` ≤ 20 × 60 chars; `preferredLanguage` ≤ 35; `goal` ≤ 500. All optional, all learner-authored. |
| `aiSession` | `lastSummary` ≤ 2000; `conceptsNeedingReview` ≤ 50 × 80 chars. |
| `officialProgress` | null, or a **copy** made by the Crabrix app (`crabrix-ios`) or read from a `.crabrixprogress` backup file (`crabrix-backup-file`). `completed` ≤ 10 000, `credited` ≤ 10 000; `courseId` may be null when the app no longer has that course installed. Agents and tools never create or edit it. |
| `evidence` | ≤ 500 learner/agent-reported items, `kind` `discussed`/`compiled_by_learner`/`ran_by_learner`/`ai_reviewed`. Never official. |
| whole file | ≤ 512 KB UTF-8 JSON. No code, no room or agent links, no keys, tokens, passwords, emails or file paths: a reader rejects strings that look like a Crabrix room/agent link with a key, a private key block or a common token prefix. |

**Merge (`merge(base, incoming)`), the only way two states combine:**

1. Both are validated first; an invalid or newer-version input changes nothing.
2. `officialProgress.completed` and `credited` are unions by `lessonId`; a lesson in `completed`
   is dropped from `credited`. Nothing is ever removed, so an older or partial export cannot lower
   progress. `capturedAt`/`source`/`appVersion` come from the later capture.
3. `evidence`: union by `(lessonId, kind)`, the later `at` kept; capped at 500 by dropping the oldest.
4. Context fields (`learningPath`, `teachingMode`, `currentLesson`, `learner.*`, `aiSession.*`):
   the side with the later `updatedAt` wins field by field, but an empty value never replaces a
   non-empty one. `conceptsNeedingReview` and `knownTechnologies` are unions (capped).
5. `updatedAt` = the later of the two. The merge is deterministic and idempotent:
   `merge(a, a) == a`, `merge(merge(a, b), b) == merge(a, b)`.
6. The result comes with a report: counts added/kept per section and every dropped key.

Producers: the Crabrix app exports it (read-only: it only reads the stores in
`academy-progress-compatibility.md` §1 and writes nothing); the SDK's local server can build one
from a `.crabrixprogress` file the learner names; agents write only the context and evidence
sections. No importer writes into the Crabrix app's progress in this release.

## Phase 6 — iOS "Learn with AI"

An extra entry in the Academy library and a "Learn this lesson with AI" action on lessons. It is
static content plus copy and share actions: connection steps per client, prompts, the current
lesson's context (`courseId`, `lessonId`, title, goal, public URL, practice options) and, only after
the learner switches it on, an AI Learning State export. It never blocks launch or lesson opening,
needs no network to show, adds no SDK and sends no events (the app keeps "Data Not Collected").

## Phase 7 — switches, events, feedback

`GET /api/academy/v1/status.json` (never cached for more than 60 s):

```json
{ "schemaVersion": 1, "learnWithAI": "on" | "paused", "academyApi": "on" | "paused",
  "academyMcp": { "url": "https://crabrix.com/mcp/academy", "state": "on" | "paused" }, "message": null }
```

| Switch | Effect | Leaves untouched |
|---|---|---|
| site `CRABRIX_AI_LEARNING=off` | `/learn/with-ai/` 404s, the `/learn/` block, lesson AI prompts, the sitemap entry and the feedback card disappear; `status.json` says `learnWithAI: "paused"` and the app shows a pause notice instead of setup steps. Needs a rebuild for static pages. | lessons, Playground, API |
| site `CRABRIX_ACADEMY_API=off` | `/api/academy/v1/*` except `status.json` answer 503 `UNAVAILABLE`. | everything else |
| site `CRABRIX_ACADEMY_EVENTS=off` | `/api/academy/v1/events` accepts and discards. | — |
| site `CRABRIX_ACADEMY_MCP_STATE=paused` | `status.json` reports the MCP paused. | — |
| SDK `serve-http --no-academy` or `CRABRIX_ACADEMY_MCP=off` | `/mcp/academy` answers 503; room agent links unaffected. | rooms |
| iOS `AcademyAIFeature.isEnabled` (build) and `status.json` | entry hidden at build time; paused notice at run time. | Academy, progress |

Events (website only): `POST /api/academy/v1/events/` (trailing slash: the site uses `trailingSlash`) with `{"event": "...", "detail": "..."}`, both
from fixed lists. The server adds one to a daily counter `(day, event, detail)` in SQLite and
stores nothing else: no cookie, IP, user agent, lesson id, code or text. The browser sends nothing
when Global Privacy Control or Do Not Track is on.

| event | detail | when |
|---|---|---|
| `with_ai_opened` | — | `/learn/with-ai/` shown |
| `client_selected` | `claude`/`claude-code`/`codex`/`cursor`/`other` | a client tab chosen |
| `instructions_copied` | client | a setup command or URL copied |
| `prompt_copied` | `beginner`/`nodejs`/`c`/`continue`/`lesson` | a prompt copied |
| `lesson_opened_from_ai` | — | a lesson URL with `via=ai` opened (the SDK adds it to links it returns) |
| `playground_opened_from_ai` | `lesson-project`/`practice-copy`/`algorithm-trace`/`example-copy` | Playground opened with `via=ai` |
| `first_run_from_ai` | — | first Run in a Playground opened with `via=ai` |
| `returned_to_learning` | — | a learner who copied AI setup earlier opens `/learn/` on a later day |
| `feedback_answered` | `yes`/`partly`/`not-working` | feedback card answered |

Official exercise completion happens only in the app, which reports nothing, so it is not counted.

Feedback: once, after the first meaningful AI interaction (a copied setup or prompt and a later
visit), a small inline card asks "Did learning Rust with your AI agent help?" (Yes / Partly / I
couldn't get it working) with an optional text field. The answer is counted as above; the text
is never sent to the server: "Email it" opens a draft the learner sends themselves. Dismissed or
answered, it never returns. The app shows the same card once in its Learn with AI screen and uses
a mail draft only.
