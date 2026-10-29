# Project preflight — Simulator qualification, 29 October 2026

Source `9733ff82381ee3794636415d3a1bc45f43ff5ecd`. This work follows signed
App Review build 116 and is **not included in that build**. The current public
site/capability profile still describes the signed delivery. No later release is
claimed by the presence of this source.

The Files sidebar opens a bounded, themed, read-only report. It shows the entry,
WASI target, edition, current root features, exact package versions/features and
fingerprints, file policy and separate Check/Build/Run/Debug evidence. Inspection
runs outside the UI actor and neither invokes a compiler nor prepares packages.
An older manifest/lock/source generation cannot supply current graph status.

Known virtual-workspace, MSRV, library-entry, library-target and separate
build-dependency requirements are checked before costly compiler work. Cargo
configuration affecting the fixed target, flags, environment or source selection
is refused explicitly; known nonmatching target configuration is ignored with
an explanation. Unknown source/runtime behavior stays unverified. Support for
some Tokio/Axum code does not imply a listening TCP server, native linking,
subprocesses, OS threads or GPU access.

Recorded evidence binds source/resources and the combined bundled Rust/browser
compiler identity. Metadata Check is distinct from linked Build; source Debug
does not stand in for ordinary Run. Constructing a browser preview does not
prove successful JavaScript execution. In this first qualification browser Check was still syntax/bundling. The later
[TypeScript qualification](offline-typescript-2026-10-29.md) adds the real checker
and source/entry/operation context; that later receipt supersedes this limitation
for its qualified native browser profile.

A recorded compiler failure now has its own status instead of becoming a
permanent unsupported-platform verdict. Its original reason is retained and a
retry remains possible. Known static platform restrictions remain blocking.
Further structured classification of compiler/backend/host/resource failures is
still part of COMPAT-01; no diagnostic text is guessed to be a crate-name rule.

The existing syn helper now previews the manifest diff. Apply requires the exact
unchanged revision, including an ABA generation check, and validates both local
and Shared budgets. A complete original Cargo.toml is stored in an ordinary
project file under `.cargo/crabrix-feature-backups/`, so it survives save/reopen
and export. Explicit custom features are not overwritten. Apply does not fetch
dependencies; the user prepares the new graph separately.

## Qualification

[Receipt](project-preflight-qualification-2026-10-29.json): **62 passed, zero
failures/skips** — 30 native and one UI case on each of iPhone/iPad Simulator.
This covers known refusals, current/stale graph evidence, Check/Run/Debug
distinction, durable original-manifest preservation, ABA rejection, custom-profile
refusal, real React source without package acquisition, ordinary rlib/binary
Build, Web generator Debug, String/Vec/struct previews, Tokio async tasks and Stop.

Both native UI routes opened the report from Files, checked card bounds, closed
it, verified identical editor text and retained Code/Problems/Output/Terminal.
Original captures use Amber Circuit on phone and Cyberpunk on iPad and were
visually inspected. No physical-device timing or Duo hardware test is claimed.
Raw results and captures: `build/project-preflight-20261029/`.

The first native run correctly rejected a fixture with explicit custom syn
features; that test incorrectly expected the plain-dependency helper to rewrite
them. The final corpus separates the supported plain-entry suggestion from the
custom-profile refusal. The original failed result is retained alongside the
final source-bound matrix.
