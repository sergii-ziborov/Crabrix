# Project reliability and Rust operation semantics — 28 October 2026

This is delivery 1 of the accepted [roadmap](roadmap/implementation-2026-10-28.md),
verified against starting revision `19e0296d711df137f973b5334588d335df839ac1`.
App delivery: **1.1.3 (111)**, source `13741f391c10d0dbd8c0fde7d71f839a56b7dd74`,
VALID / IN_BETA_TESTING / WAITING_FOR_REVIEW, manual publication.
[Signed delivery and metadata readback](app-store/release-1.1.3-build111.json).

## User-visible changes

Supported hidden source/configuration files survive durable reopening, editable
packages and source ZIPs. A shared editable-tree policy covers 2,048 files,
2 MiB of UTF-8 per file, 16,000,000 source bytes, and bounded metadata and paths.
The ZIP entry budget accounts for directories and metadata separately. Cargo's
2,048-package ceiling and Shared's smaller room quotas are separate contracts.
Raw repository imports retain the existing supported text-file profile; opaque
binary files and full Git history belong to the later portability delivery.

Format 3 stores SHA-256 source inventory. Missing or changed saved files produce
an explicit recovery notice or read error, rather than a smaller successful
project. Versions 0–2 remain readable without inventing a historical inventory.
The original legacy snapshot, including its earlier recovery, is retained during
migration. Unreadable projects remain discoverable when the index is rebuilt.

Saving reports unsaved/saving/saved/failed. Retry, project export and current-file
export remain available after a real write failure. Oversized current text stays
in the open editor; export or reduce it before leaving the app. This is not a
promise that failed writes survive process termination. My Projects exposes a
separate bounded raw recovery ZIP containing saved snapshots and metadata.
This rescue ZIP is for extraction, not the ordinary editable package importer.
Already-lost bytes cannot be recreated. An explicit project deletion removes its
retained local snapshots too.

Queued saves and export completion cannot overwrite a newer source tree. Build
history is shown as current only for matching source and compiler identities.
Terminal `cargo build` compiles the selected executable or rlib without invoking
`main`; `cargo run` remains distinct. Executable Build can populate Run's local
artifact cache. Library output is currently ephemeral. Supported bounded build
scripts remain compile-time work. Unsupported flags/target profiles are explicit.

The shared debugger avoids generated-name shadowing and unintended post-move
borrows from `dbg!`, custom macros, formatting expressions and consuming methods.
Resource rewriting requires a provable supported macro scope. Ambiguous aliases,
shadowing, opaque item-macro scopes and compile-time source introspection can
produce an explicit unsupported Debug result; normal Run remains available.
This is a conservative source instrumenter, not a full Rust name/type resolver.
Custom Debug implementations are not evaluated for previews. Existing bounded
String/Vec/structure previews, async active-poll stacks, Stop and web assets stay
local. The editable source is never replaced by generated checkpoint code.

Editor, fold, keyboard and dock geometry are retained. The save status is added
inside the existing project information strip. The guide explains the supported
profiles; the home page links directly to Rust, an algorithm replay and the app.
`/api/capabilities/` exposes read-only product metadata, accepts no source and is
not an MCP endpoint. Future GPT access through Shared is specified in the roadmap;
no connector, plaintext relay or server compiler is introduced in this delivery.

## Verification and delivery

The final native host gate passed all 67 tests on iPad Simulator: 17 authoring,
23 imports/storage/export/recovery, 12 terminal, 12 real-compiler debugger/build
and three keyboard/layout regressions. A further native test verifies exact over-budget UTF-8 rescue and cleanup,
bringing qualified host cases to 68. Phone and tablet checks cover the five UI
scenarios each through the initial runs and focused successful reruns. Signed
delivery is recorded in the signed delivery receipt above.
The real browser compiler corpus has passed 32 Run/Debug output comparisons and
eight explicit safe unsupported cases. A packaged Chromium flow has hit a real
breakpoint, stepped, inspected a local value and matched Run after networking was
blocked. The phone/tablet qualification uses Simulators; physical iPhone timing,
physical Universal Links and Duo posture changes are not newly qualified here.

Raw logs and xcresults: ignored `build/reliability-20261028/`. Previous failed
attempts remain in that directory and are not counted as successful final gates.
The first native gate found a stale expectation for the corrected build-script
message; that assertion was updated. One concurrent iPad UI run reached its web
counter just after the 20-second presence deadline; its subsequent click executed
JavaScript. The focused resource rerun passed. The second SwiftUI file-export modal exposed an unusable Cancel surface on
compact iOS. Current-file rescue now writes exact UTF-8 on a background task
and opens the existing native sharing surface, including Save to Files. Its
Close control and unchanged editor are checked on phone and tablet. Ordinary
editable-project export retains its single existing file exporter.

## Recovery and rollback

Keep an external editable-project export before updating or intentionally editing
package internals. Retained legacy/current/previous snapshots can be extracted
through the recovery ZIP. An older app may not understand format 3: do not use a
binary downgrade as a substitute for data recovery. Restore selected source bytes
from an exported copy or retained snapshot into a supported editable project.
Website deployment retains the previous container and takes an account-store
backup; the Shared relay and its running encrypted rooms are separate services.

Machine-readable qualifications: `docs/project-reliability-2026-10-28.json`.
