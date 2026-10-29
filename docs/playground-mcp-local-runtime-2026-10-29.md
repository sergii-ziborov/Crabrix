# MCP 0.2 — explicit client-local execution

The 0.2 implementation is qualified locally; distribution is recorded separately
in the App Store, npm and website delivery receipts. Signed 119 does not contain
these additions. The published 1.1.2 editor remains source/selection compatible.

The official MCP SDK, a production browser build and two actual Simulator apps
exercised live edits and Unicode selections, local Check/Build/Run/Debug dispatch,
structured String/Vec/local-struct values, stepping, breakpoints and owned Stop.
Ordinary Run was also pressed in the native app and browser: the other clients
received reported output without invoking their compiler. The browser Worker
start count was checked. Both native UI flows retained the four original dock
tabs. See [the qualification receipt](playground-mcp-local-runtime-qualification-2026-10-29.json).
There are 36 Node checks and 36 native checks on each device type. The native
series includes real frozen/offline Tokio async polls, cancellation, String/Vec
locals and equality with ordinary Run. This is not a physical-iPhone benchmark
or a live Claude-provider session; SDK stdio and actual compilers were tested.

## Boundaries

Source edits, room membership or a participant's own Run never grant execution
on another client. MCP first discovers short-lived signed capabilities. The user
compares controller/device fingerprints and grants selected operations in Share
on ONE foreground client, for at most ten minutes. Revoke, disconnection,
backgrounding, room/project change and expiry release that permission. A source
change stops the owned job; a new start needs the exact current source revision.

Control frames bind room, target key, controller key, operation, source, grant,
job, nonce and expiry. P-256 signatures and edit-capability HMAC are verified
before authority checks. Replays cannot create a second job. View-only signature
verification cannot supply edit/control authority. Pending requests, queues,
receipts, result pages and presence messages are bounded. Lost acknowledgement
recovery exposes the matching controller's latest job rather than blindly
starting twice. A delayed compilation-stage event cannot unpause the debugger.

The initial `shared-std-v1` executor accepts manifest-free standard-library Rust
and local modules. It uses validated shared text, no resource files, an empty
Cargo plan and no host environment/stdin. Cargo/build/native requirements are
refused, not silently omitted or downloaded. Ordinary offline Cargo/Tokio,
TypeScript/npm browser projects and Rust + Web remain separate local modes.
Each shared job has a two-minute wall-clock budget, including pauses. Stop owns
its cancellation token and cannot stop a later ordinary compiler invocation.
Native and browser local Resume commit their state before waking the guest.

Own shared-source results are explicitly marked: they do not replace saved
full-project evidence or award learning progress. Old unit-test/reward cards are
cleared for the new shared job. Received output is a separate display object,
never a CompilationResult, debugger command, executable HTML or learning record.
Only actual local completions can publish a report; received reports never echo.
Native ordinary results are reported only for exactly matching shared inputs,
without private resources or dependencies. Other native project results remain
private.

Output previews fit the existing signed 768-byte presence payload and can be
truncated. Full owned streams are retained locally up to 64 KiB each and paged to
the permitted controller. Names and reported results are not hardware/build
attestations. Program text, diagnostics and locals remain untrusted data. The
relay stores only temporary ciphertext in RAM and never compiles or runs Rust.
No account, database or backup receives room source. MCP-host/provider retention
is separate and is disclosed in the bridge README and website guide.

The old 0.1.1 archive is immutable. The 0.2 archive includes all bundled original
source hashes, component licenses, a pinned install example and twelve tools.
