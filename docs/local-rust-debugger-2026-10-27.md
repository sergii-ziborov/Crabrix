# Local Rust source debugger — 27 October 2026

## Implementation

Debug uses the same pinned Rust compiler and interpreter as Run. A shared Lezer
Rust parser inserts checkpoints into a separate source snapshot; the actual Rust
compiler compiles that snapshot. The executing Wasm calls a bounded host import
with source-site IDs and primitive-value snapshots. No user Rust is evaluated as
JavaScript and no code is compiled or executed by the website backend.

The native app prepares and executes Debug on its compiler queue, pausing that
queue with a condition variable. The browser compiler lives in a Worker and
waits on shared atomic control memory. Both interfaces support source
breakpoints, Continue, Step into/over/out, Pause, Stop, call frames and safe
primitive locals. The original source and normal Run flags remain unchanged.
Generated artifacts have separate cache identities. No runtime/compiler package
pin or native Duo/editor/dock/keyboard layout was replaced.

The compiler's earlier DWARF-generation panic is still a limitation. This
implementation uses source checkpoints rather than claiming DWARF support.

## Boundaries shown in the interface

- Synchronous source functions and statements are stepped. Async and const
  function bodies, macro expansions and dependencies are not stepped internally.
- Safe primitive arguments/locals are inspected. Arbitrary structs, collections,
  borrowed or captured values are not decoded. No watch expression is evaluated.
- Statement attributes and compile-time source-introspection forms that cannot
  safely preserve their meaning fail Debug with an explanation; normal Run is
  still available. Debug can alter timing and is not a concurrency profiler.
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
with App Store status READY_FOR_SALE. The debugger update is version 1.1.3 (107):
Xcode Cloud succeeded, Apple processing is VALID, Internal QA is IN_BETA_TESTING,
and the App Store submission is WAITING_FOR_REVIEW with manual publication.
All 19 inherited screenshots are complete with Code first in every device set;
store text, review notes and beta instructions were read back after updates.
The actual App Store IPA matches the bundled debugger compiler and offline legal
source; its signed entitlements retain the Crabrix App Group and Universal Links.
See `docs/app-store/release-1.1.3-build107.json`.
