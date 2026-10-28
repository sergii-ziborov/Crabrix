# Playground MCP bridge 0.1.0 — qualification

The user activated MCP work for Playground on October 28, replacing its earlier
deferral. This is a local stdio bridge for Claude Code/Desktop or another MCP
host, using the existing encrypted Shared protocol. It is a separate download,
not a new backend compiler or an npm-registry publication.

## Implemented scope

- Connect to an explicitly supplied canonical Crabrix room link, or create a room
  with a one-hour default and a 24-hour maximum. No account is required.
- Read source, file inventory, current revision, expiry, participant names and
  remote UTF-16 selections. The bridge appears as **Claude · MCP**.
- Apply bounded multi-file changes to the exact read revision. The relay checks
  its sequence atomically before appending the encrypted Yjs update. A stale
  revision changes nothing. Identical acknowledged message IDs deduplicate a
  retry after a lost response. Older relays without this capability are refused
  for edits before sending the proposed source delta.
- Show a relative selection in native and browser editors; reject offsets that
  split a Unicode surrogate pair. Disconnect releases this process's room state.
- Eight tools, a status resource and a reusable task prompt. Owner-only early
  closure is available for a room this bridge created in the current connection;
  a joined edit link never grants ownership. The official MCP SDK
  serves current and legacy stdio negotiation; no handwritten JSON-RPC parser.

This version does not expose Check/Build/Run/Debug, shell, local files, package
installation, Git push or account storage through MCP. A human uses local
Run/Debug in the connected client. Remote execution permissions remain separate
future work. Rooms retain the existing four-peer, 16-file, 64 KiB/file and
128 KiB/source limits.

## Trust and packaging

Only the official origin is accepted by the production CLI. Private keys remain
in fragments and process memory; the relay receives bearer capabilities and
AES-256-GCM ciphertext. Source/comments remain untrusted data. There is no
filesystem/shell tool or project-controlled URL fetch. The user's MCP host/model
can receive plaintext source and complete links; its own retention policies
apply. Privacy text and all native/site mirrors disclose that boundary.

The versioned tarball contains a bundled Node 22 executable, bridge license,
original dependency licenses/notices and a source SHA-256 manifest. It declares
no runtime npm dependencies or installation scripts. It can be installed
directly from the website with npm, or extracted and launched with Node. The npm
registry is not claimed as a distribution channel. The page publishes the exact
archive digest; original app licensing stays separate.

## Confirmed checks

- Official SDK client discovers all eight tools, resource and prompt, and calls
  the bundled stdio binary from a temporary directory without node_modules.
- Real encrypted HTTP/SSE relay checks: source propagation to another editor,
  stale revision, server-side racing sequence conflict, duplicate acknowledgement,
  view-only denial, UTF-16/emoji selection, expiry and absence of plaintext in
  captured relay request bodies. Three package cases passed, including owner-only early closure. Twelve native model/license cases also passed; nearby participant badges stay inside the existing canvas without overlapping.
- Four live participants: MCP via official SDK stdio, Chromium, actual iPhone
  Simulator app and actual iPad Simulator app. Both native editors sent source
  and selections to MCP. MCP changes and selection reached the apps/browser.
  Independent real String/Vec debugging passed on all three clients. Selection
  alone kept Debug paused; a new source revision canceled stale debugging.
  All three local compilers produced `shared-final=42`. Native custom-scheme and
  HTTPS entry handling passed. These are Simulators, not physical devices or a
  live Claude-model invocation.
- MCP page: 390/820/1440 widths, light/dark, no horizontal page overflow or console
  errors, one site brand, actual downloadable archive digest verified.

The first four-client attempt failed because its browser test counted inline
participant-name decorations as source text. The assertion now excludes those
decorations. Two following complete runs passed both native UI tests and the
coordinator; the last includes nonoverlapping native participant labels. Evidence: `build/playground-mcp-20261028/`.

Publication and App Store delivery are recorded separately. Build 115 is now VALID / IN_BETA_TESTING / WAITING_FOR_REVIEW; its [signed-delivery receipt](app-store/release-1.1.3-build115.json) identifies the exact source and checks.
The bridge uses existing Shared-client behavior; native Atlas and IDE changes
are not retroactively declared part of 114.

## Public delivery

Published at **2026-10-28T21:42:23Z**, website source `adbc23e`. The
[public page](https://crabrix.com/playground/mcp/) and versioned archive were
read back. The archive SHA-256 is
`9894e4d99f07eac13497669e850e60b9762b739cbd292789e84d71a5401350ee`.
The exact downloaded executable passed official SDK stdio → production encrypted
relay → browser source/selection → actual local `mcp-public=42` stdout → owner
closure. There were no browser page errors. No npm-registry publication is claimed.
[Machine-readable delivery and qualification](playground-mcp-qualification-2026-10-28.json).

A pre-activation deployment gate caught macOS AppleDouble metadata in the first
uploaded website archive. The live container had not switched. Validated metadata
files were removed, the image rebuilt, and the expected 402 trace assets checked
before activation. Account storage and rollback were retained.

The subsequent guide-only website release `8bbd6d0` retains the identical MCP
0.1.0 tarball and protocol. Public responsive/download checks passed again,
including the new Atlas guide gallery. App 1.1.3 (115) includes the qualified
native label and offline Atlas changes; the separate desktop bridge is not an
iOS downloaded executable. Semantic IDE prototype work is not in this build.
