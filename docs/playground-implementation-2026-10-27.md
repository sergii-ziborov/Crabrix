# Crabrix Playground — implementation record

## Authorized scope (latest user instructions)

- Public guest feature; no registration or account requirement.
- **No saving projects to website accounts, databases or disk.** This replaces
  the earlier account-library proposal.
- Rust compiles/executes locally in a browser Worker or the installed native app;
  no backend compilation/execution.
- Anonymous temporary sessions and shared links last at most 24 hours from
  creation. Show remaining time and exact expiry. Viewing/joining does not renew.
- Live coding interviews with simultaneous editing. The user initially asked for
  pure P2P, then explicitly authorized server traffic as well. A bounded temporary
  relay is permitted; no durable source storage. Clear privacy description.
- Reuse Crabrix's Auto/Light/Dark/Amber Circuit/Cyberpunk themes, code palette,
  familiar panels and accessible adaptive layout; preserve existing native UI.
- Single/multiple text source files, editor preferences, actual supported tools.
  Do not expose fake x86 assembly settings for a Wasm target.
- Download source on a tablet/computer and save an imported copy in native
  Crabrix. Opening a link does not extend its lifetime.
- App can create/share Playground links. Universal Links open the installed app
  on iPhone/iPad; browser fallback works without installation.
- Distinguish temporary Playground/session links from downloadable local project
  files. Permanent cloud-project links are outside this stage.
- Public GitHub/gist import with source/commit provenance and strict text limits.
- Debugging in the native app and website; repair/qualify compiler debug metadata
  rather than claiming a Debug build selector is an interactive debugger.
- Bound room/message/source quotas; capability access, TTL enforcement, safe
  imports, no automatic execution of received code, isolated compiler/program jobs.

## Architecture being implemented

Native/browser clients share a versioned text-only project document and Yjs
editing model. Temporary interview rooms relay authenticated encrypted document
updates and hold bounded encrypted snapshots **only in process memory**, with
automatic expiry. They are excluded from database/account exports and backups;
process restart can end a temporary session early. Bearer capabilities and the
client encryption key live in the link fragment, not request query/access logs.
Shared source is never served as HTML or executed by the relay.

The real signed/pinned compiler and sysroot are static verified browser assets,
loaded on demand and cached separately from user source. Each compilation and
execution uses a background Worker and fresh guest filesystem. Source does not
leave the client for Run/Check. Native Run remains local/offline after
source import; network is only needed for link acquisition and live collaboration.

Initial implementation limits: 16 text files; 64 KiB/file; 128 KiB/source project;
4 room participants; room life 1–24 hours. Room/API traffic and total resident
room memory have independent server limits. These are guest-feature budgets,
not new paid plans or restrictions on existing app project budgets.

## Status — production relay and release 103

- Browser workspace, actual WASM compiler Worker, bounded ciphertext relay,
  CRDT source/relative-selection protocol, native Swift/CryptoKit/JavaScriptCore
  client, app sharing/import hooks and associated-domain files are implemented.
- Ten relay/source/crypto/memory/upload-deadline tests passed. The actual browser
  engine enforces the rewritten guest-memory maximum. Production dependency audit
  reported zero known vulnerabilities on 27 October 2026.
- Independent Swift processes and Chromium passed bidirectional source/selection
  exchange, four peers, reload, and concurrent offline/online edits merging after
  reconnect. The iPhone Simulator app received remote source/selections, sent actual
  UITextView edits and compiled/ran the shared program successfully.
- The complete public editor and real compiler also ran successfully in iOS WebKit
  on the iPad Simulator. This is an actual compiler run, not a substituted compiler
  or a JavaScript-only code evaluator.
- Twelve final Chromium theme/viewport layouts passed, including the wrapped-header
  height fix. The complete workspace and dock remain inside the viewport.
- Associated Domains capability, the signed build 103 entitlement and its App Store
  provisioning profile match. The HTTPS AASA returns JSON without a redirect and
  Apple CDN returns the same document. External link delivery on a physical device
  with build 103 installed still needs a device check. The share extension retains
  its App Group.
- Detailed guide screenshots and source/privacy/third-party notices are synchronized.
- Two actual Simulator app instances (iPhone and iPad) joined the same room as
  Chromium. Changes from both actual editors reached the room. Both native apps
  and Chromium compiled/ran the final shared source locally. Both qualified UI
  runs completed successfully with separate xcresults. An earlier multi-destination
  Xcode finalizer hang and an ambiguous iPad keyboard selector were harness issues;
  the final independent-destination runs resolve those gates.
- Interactive source debugging remains unfinished: the production code generator
  cannot emit valid line metadata. Do not advertise a functioning source debugger.
- The two actual Simulator apps also passed against the production HTTPS relay,
  alongside Chromium. Both native tests waited for compilation to finish, opened
  Output, and asserted exact STDOUT `pair-run=42`. The source uses `gen` as an
  identifier, proving Rust 2021 survives native copying rather than silently
  switching to Rust 2024. Earlier checks that could match text still in the editor
  are superseded by these strict runs.
- The website is published on Hetzner. Build 1.1.2 (103) is available in TestFlight
  Internal QA and WAITING_FOR_REVIEW, replacing 101. Publication remains manual.
  All 19 App Store screenshots are complete, with Code first in each device set.
  Description, What's New, beta instructions and reviewer notes were read back
  after updating. See the signed-source and delivery IDs in the release receipt.
- First toolchain transfer reports received bytes. Its loading deadline measures
  inactivity so a slow but progressing initial download can finish. Compilation
  and program execution retain their separate 45-second and 30-second limits.
