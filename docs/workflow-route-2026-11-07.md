# Git → CLI → HTTP API → SQL → diagnostics → delivery

Implemented as a local release candidate, Crabrix **1.1.8 (134)** with
Projects CoursePack **1.1.0** and the `workflow-terminal-v1` capability.
The production catalog, public website and App Review submission are unchanged.

The owner subsequently authorized merging all Crabrix worktrees, TestFlight upload
and App Review submission. The Atlas worktree history is integrated with its
already cherry-picked changes retained. The generated-project source now also
pins 1.1.8 (134), and production-signed catalog 24 is bundled with this compatible
binary. Its immutable course assets are published as the workflow-route-2026-11-07
prerelease; the public main catalog remains 23 during qualification. Apple delivery
status will be recorded independently after archive/upload/processing readback.

## Learning content

The course source is the sibling `crabrix-courses` checkout at
`76d607ad0dc24f9497d7c1db8208b19a8e1bd515`. Six ordered units extend Cargo & Real
Projects with four lessons each:

| Unit | Practice |
| --- | --- |
| Git | Inspect exact changes, select commit paths, switch branches, recover a historical file |
| CLI | Preserve argv, resolve configuration, bound stdin, separate output and failures |
| HTTP API | Route methods/paths, validate limits, encode JSON, make write replay idempotent |
| SQL | Enforce constraints, query deterministically, bind parameters, preserve transactions |
| Diagnostics | Add context, correlate requests, measure latency, bound retry budgets |
| Delivery | Define gates, separate configuration, verify artifacts, preserve rollback compatibility |

Each lesson has a complete worked Rust program, reading question, separate typed
`solution.rs` lab with a private caller, boundary cases, misconception/trace/transfer
practice and a contextual PNG. The four SQL labs execute submitted SQL against
fresh SQLite fixtures. Running a worked example does not mark its independent
lab complete. Existing lesson identities, saved answer positions and unit prefixes
are retained. The authored snapshot totals **798 lessons/stages**: 198 Rust and
600 Atlas, plus the existing 46 Examples in their separate package.

**Open Task Ledger** on a route lesson's Apply page creates an independent personal
project. Every route lesson references the same public source template; personal
copies retain their own identity and data. The template includes a native std-only
CLI/HTTP handler and a complete separate Axum/SQLx desktop server. The web snapshot
contains all 24 worked readings and a public companion ZIP, without private lab
callers. Route lessons have reciprocal contextual article links.

## Terminal and editor

The terminal forwards quoted/empty CLI arguments, invocation-local environment
values and redirected project-file stdin into the real compiled Rust program.
These values remain fresh when an executable is cached. For example:

```sh
sqlite3 tasks.db .read migrations/001.sql
cargo run --database tasks.db -- add "learn Rust"
env TASK_LIMIT=7 cargo run --database tasks.db -- list
cargo run -- import < input.txt
cargo serve --port 8080 --database tasks.db
http run requests/create.http
curl -i http://127.0.0.1:8080/tasks
sqlite3 tasks.db 'SELECT id,title,done FROM tasks ORDER BY id'
http stop
```

`--database` before Cargo's `--` is an explicit Crabrix database grant. SQLite
files are persisted under the personal project's identity, outside source and
course downloads; deleting the project removes its databases. Prepared parameters
retain literal data, including embedded NUL and Unicode. A failed or unfinished
open transaction is rolled back. Completed autocommit statements retain normal
SQLite semantics. Queries, database size, results and execution time are bounded;
extension loading, attached databases and PRAGMAs are denied.

The localhost listener passes one HTTP request to a frozen Rust source snapshot
on stdin and sends its actual stdout response over TCP. It supports Content-Length
framing, bounds connections/requests and stops on project switch or backgrounding.
It adds request correlation/status/duration receipts. The terminal HTTP client
supports explicit headers, methods and inline/project-file bodies; it permits
HTTPS and HTTP loopback URLs, refuses redirects, and bounds response size/time.
Secret environment/header values are redacted from terminal history. Transcript
previews are bounded independently of the compiler's full Output.

Shell, SQL, HTTP request files, Dockerfile, diff/patch and environment files have
native syntax highlighting, alongside existing Rust/JSON/TOML/YAML. Terminal input
and typed responses use the matching lexers. The web CodeMirror editor selects
the corresponding grammars, including extensionless Dockerfile and `.env` names.

These are documented target profiles: native iOS runs the std-only WASI handler
with explicit SQLite/HTTP host adapters. Docker, host shell scripts, Axum networking
and hosted CI execute in the desktop/server profile. The browser's SQL worked
readings print statements; the native database labs execute them. The terminal
does not claim arbitrary shell pipelines or Linux process support.

## Verification

Artifacts live under the ignored `build/workflow-route-20261107/` directory.

- Source corpus: 34 Python tests, validation of 8 packs/798 lessons, 24 executed
  readings, and 96 compiled lab variants. All references pass; unchanged starters,
  semantic regressions and forged-verdict variants fail (72 rejections).
- Native Simulator gate: `WorkflowRouteTests`, `ProjectTerminalSessionTests`,
  `SyntaxHighlighterTests`, `CoursePackVerifierTests` and `GitWorkspaceTests`.
  All 36 pass with local Simulator signing. This includes all 24 lab contracts,
  actual loopback HTTP → Rust → SQLite, shared CLI/database state, retained old
  package snapshots and new signed test-package installation. Final receipt:
  `build/workflow-route-20261107/final-native.xcresult` (36 executed, zero failures).
- Test package: Projects ZIP uses the openly published test publisher key only.
  The production trust store is unchanged. Its ignored fixture is documented in
  the content repository's `editorial/workflow_route_20261107/README.md`.
- Website: TypeScript check, all 160 tests and production build pass. Local
  production HTTP checks cover all 24 new pages and Playground links, 24 article
  backlinks, the companion ZIP and a route PNG. The ZIP's 22 source files match
  the public course template and exclude private grading/build/database artifacts.
- Desktop: native companion's 3 tests and the desktop constraint test pass;
  real HTTP/SQL acceptance checks creation, idempotent replay, conflict, invalid
  input, injection-shaped data, latency/retry probes, graceful stop and restart
  persistence. The release script builds from clean content revision `76d607a`,
  records the toolchain/revision, and verifies SHA-256. A modified artifact copy
  is correctly rejected.

The Dockerfile's Rust image tag exists, but a container build was not executed:
the local Docker daemon is unavailable. Hosted CI, physical-device layout and
performance, production publication and App Store submission remain release
qualification work. Do not publish Projects 1.1.0 to older apps; its descriptor
requires Crabrix 1.1.8 and `workflow-terminal-v1`.
