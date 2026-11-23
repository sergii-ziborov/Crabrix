# Learn Rust with Your Coding Agent — implementation plan and API contract

Status: phases 0–3 in progress on `feature/academy-mcp` in Crabrix, crabrix-courses and
crabrix-sdk (23 November 2026). Nothing in this work changes existing progress, CoursePacks,
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

Later phases (not in this change): Playground starter projects for more lessons (4),
read-only progress import and AI Learning Context storage (5), an iOS "Learn with AI"
entry (6), staged launch with flags (7).

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
