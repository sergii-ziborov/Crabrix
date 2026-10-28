# Academy algorithm walkthroughs

The website's Algorithm Atlas has 200 patterns / 600 lessons. Each lesson's
interactive walkthrough is tied to the SHA-256 of its exact `writing.exampleCode`.
Model and recognition lessons share a fixture; challenges use a second fixture.
There are 400 distinct lesson traces plus one independent public demonstration.

The same corpus now has a separately signed
[native offline-replay candidate](offline-atlas-replay-2026-10-28.md). Its optional
data packs are public GitHub release assets; website lesson routes retain their
existing account gate. This does not add backend execution.

## What the learner sees

- Forward/backward stepping, restart, explicit play/pause, speed and scrubbing.
- Exact pre-statement state, the highlighted original Rust line and the call stack.
- Indexed arrays with changes and index labels, matrices, maps, adjacency graphs
  with directed edges/weights, linked lists and binary tree nodes.
- Scalar variables, closure arguments/accumulators and actual standard output.
- A responsive layout: data above code on phones, alongside code on wider screens.
- The existing free-account gate for full lessons. The open course demo uses a
  separate input; full traces are not in `public/` or an unauthenticated API.

## Execution model

Walkthroughs are **recorded examples**, not a second general-purpose debugger.
Their Rust is compiled and executed on the maintainer's computer at author time.
The deployed server reads a selected JSON file after authorization; browser
playback is entirely local and never sends execution requests. The Playground's
local compiler/debugger is unchanged.

The planner uses Lezer's Rust AST to insert statement checkpoints and function /
closure call guards. Captures borrow standard Debug values briefly; the original
lesson source is never edited. Concrete teaching structs get Debug derives in
the temporary instrumentation build only. A capture that fails Rust's borrow,
move or type checking is removed using compiler diagnostic spans. Its absence is
disclosed in the UI. This preserves the program's ownership rules.

For every fixture the generator compiles and runs the original and instrumented
Rust, compares stdout exactly and checks it against the independently verified
Academy fixture oracle. Numeric Debug text is preserved as text, including u64
values above JavaScript's safe-integer limit. Values are pooled across steps;
each trace is bounded to 50,000 steps and 2 MiB. No execution is truncated silently.

## Regenerating after a lesson source change

From `site/`, using Node, pnpm, Python 3 and rustc:

```sh
pnpm exec esbuild scripts/plan-algorithm-traces.ts --bundle --platform=node --format=esm --outfile=../build/algorithm-atlas/planner.mjs
node ../build/algorithm-atlas/planner.mjs
python3 scripts/generate-algorithm-traces.py --editorial-root /path/to/crabrix-courses/editorial/academy_20261027
pnpm test
pnpm check
```

The editorial path is needed only during regeneration for the independent
fixture inputs/answers. It is never deployed. Rust sources and diagnostics stay
under the ignored `build/algorithm-atlas/`; generated lesson JSON is checked in.
The production build explicitly includes that JSON in Next's standalone output.

If a source changes without regenerated data, the source digest check rejects
the stale trace rather than displaying steps from an older algorithm. Tests
cover every lesson mapping, both fixtures per pattern, all frame references and
source lines, closure stepping and public-demo separation.
