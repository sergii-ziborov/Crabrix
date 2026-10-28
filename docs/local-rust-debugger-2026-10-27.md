# Local Rust source debugger — 27 October 2026

## Implementation

Debug uses the same pinned Rust compiler and interpreter as Run. A shared Lezer
Rust parser inserts checkpoints into a separate source snapshot; the actual Rust
compiler compiles that snapshot. The executing Wasm calls a bounded host import
with source-site IDs and bounded local-value snapshots. No user Rust is evaluated as
JavaScript and no code is compiled or executed by the website backend.

The native app prepares and executes Debug on its compiler queue, pausing that
queue with a condition variable. The browser compiler lives in a Worker and
waits on shared atomic control memory. Both interfaces support source
breakpoints, Continue, Step into/over/out, Pause, Stop, call frames and safe
primitive, String, Vec and concrete local struct previews. The original source and normal Run flags remain unchanged.
Generated artifacts have separate cache identities. No runtime/compiler package
pin or native Duo/editor/dock/keyboard layout was replaced.

The compiler's earlier DWARF-generation panic is still a limitation. This
implementation uses source checkpoints rather than claiming DWARF support.

## Boundaries shown in the interface

- Synchronous and async source functions/statements are stepped. A small Future
  wrapper enters and leaves a frame on each poll, so suspended or cancelled
  futures do not leave stale frames on another task's active stack. This is an
  active poll stack, not a persistent Tokio task history or concurrency profiler.
- Primitive values, String, Vec, arrays, Option and concrete local structs have
  bounded previews. Generated field readers work without derive(Debug) and never
  call a user's Debug implementation. Structs/collections show up to 16 fields or
  elements, nesting stops at four levels, and each preview has a 256-byte UTF-8
  budget. Opaque fields are marked `<not inspected>`.
- Generic, packed and conditionally shaped structs can stay opaque. Potentially
  moved, borrowed or captured locals are conservatively omitted. Const bodies,
  macro expansions and dependency internals are not stepped. No watch expression
  is evaluated. Normal Run is available for unsupported Debug source forms.
- Tokio current-thread execution is provided by the app's offline Cargo path.
  Browser compilation supports std and local modules; browser Tokio/Cargo packages
  have not been added by this debugger change.
- Statement attributes and compile-time source-introspection forms that cannot
  safely preserve their meaning fail Debug with an explanation; normal Run is
  still available. Debug can alter timing and is not a concurrency profiler.
  Literal `include_str!` and `include_bytes!` resource paths are supported;
  included Rust source is preserved as original data. Computed resource paths,
  executable `include!` and `column!` remain explicit normal-Run fallbacks.
- A breakpoint on a non-executable line binds to the next available statement in
  the same file. Highlighting identifies the next statement to execute.
- Editing shared source stops a stale Debug snapshot. Remote cursor/selection
  updates alone do not stop execution. Participants debug independently.
- Browser Debug requires cross-origin isolation and SharedArrayBuffer. Missing
  support produces an actionable message; ordinary Run does not require it.
- Paused time is excluded from execution deadlines. A pause expires after
  30 minutes. Stack depth, checkpoint count, local payload and guest memory/output
  remain bounded. Stop wakes the paused interpreter; the UI stays responsive.

## Sharing and interface

The native and web creation sheets default to **one hour**. A new room receives
its full selected lifetime when created, independent of editor preparation time.
The web sheet uses four themed lifetime buttons, one creation action and a
separate secondary source download. Existing shared links retain their original
expiration; maximum lifetime remains 24 hours. No account storage was added.

## Verification receipts

Detailed machine-readable results are in
`docs/local-rust-debugger-verification-2026-10-27.json`. Local raw results,
xcresults and screenshots are under ignored `build/debugger-20261027/`.

- Real browser compiler host-import and instrumented Rust checkpoint probes.
- Eleven normal-versus-Debug semantic comparisons, plus two explicit unsupported
  Debug forms whose normal execution still succeeds: recursion, borrowing,
  delayed initialization, closures, const evaluation, Unicode, scopes, modules,
  return/break/continue and unit functions.
- Browser UI: entry pause, breakpoint, all three step modes, actual frames and
  primitive locals, exact `total=6` stdout, unchanged source, offline builds after
  acquisition, Stop and recovery.
- Browser interview: a full one-hour room at creation, shared source changes stop
  Debug, source and selection exchange continue, creator ends the room.
- Twenty-four Chromium theme/viewport checks across phone, tablet and desktop: twelve normal and twelve paused Debug layouts.
- Fifteen final native host tests passed, including real iOS WebKit Debug/Run and all three existing terminal keyboard regressions. The complete native UI flow passed independently on iPhone and iPad Simulators against the frozen final app bundle.

The final website is published on Hetzner. Public HTTPS Debug and one-hour sharing passed; two actual Simulator apps and Chromium also exchanged edits and each ran the final shared source locally with exact stdout. See `docs/site-debugger-release-2026-10-27.json`.

Physical iPhone timing and external Universal Link delivery require an available
physical device; Simulator results are not device performance measurements.

## Delivery

The user-requested publication of the already approved 1.1.2 (103) completed
with App Store status READY_FOR_SALE. The current debugger update is version
**1.1.3 (110)**: Apple processing is VALID, Internal QA is IN_BETA_TESTING,
and its App Store submission is WAITING_FOR_REVIEW with manual publication.
Build 108 had been approved but remained unpublished; it was replaced only after
110 passed the signed-package and TestFlight gates. Build 109 was an intermediate
archive and was not distributed. All 19 inherited screenshots remain complete
with Code first in every device set. Store text, review notes and beta
instructions were read back after updates. The actual App Store IPA matches the
bundled debugger and offline legal source; signed entitlements retain the App
Group and Universal Links. See `docs/app-store/release-1.1.3-build110.json`.
Historical build 108 verification remains in its separate release receipt.


## Aggregate and async follow-up

The follow-up extends the existing inspector and protocol without changing editor,
Duo, dock or keyboard geometry. The native inspector wraps long values below their
name/type. The browser table constrains long fields; narrow toolbars wrap within
screen width. Qualification is recorded separately in
`docs/local-rust-debugger-values-2026-10-27.json`: 17 native host tests, six native UI tests, 20 normal-versus-Debug semantic comparisons, two explicit safe fallbacks, and twelve browser layouts. Tokio 1.54.1 current-thread tasks, timers, channels and cancellation run from a frozen offline plan. The Simulator debug run took 43.5 seconds; this is not a physical iPhone performance claim.

## Included-resource follow-up

The 28 October fix supports the built-in Rust + Web generator and restores
pre-Debug gutter taps on compact screens. See
`docs/local-rust-debugger-resources-2026-10-28.md` for the report, limits and
verification. That follow-up supersedes build 108; its delivery receipt records
the actual selected TestFlight and review build.
