# Live Crabrix MCP qualification — 29 October 2026

Two independent coding-agent contexts used the official MCP stdio client against
the real Crabrix relay. An implementation agent created readings.rs; an independent
reviewer added 13 behavioral assertions. Two real browser tabs joined the room.
The browser edited source and both agents read that change. An old expectedRevision
was refused without overwriting main.rs, whole-emoji selection worked and a
half-surrogate selection was refused. Source comments were treated as untrusted
input, including an intentionally adversarial comment in this disposable fixture.

Only one browser prepared its verified compiler. A Run without permission was
refused. After comparing the full controller and device fingerprints, an explicit
grant allowed Build/Run/Debug on that client only. Build completed with empty
stdout; Run completed with exit code 0 and all 13 assertions. Debug showed a
concrete Report with a String label and Vec fields. The ungranted reviewer could
not read, Step, Continue or Stop the owner's paused Debug job. The owner verified
it was still paused, inspected actual locals and continued successfully.

The second browser stayed compiler-unprepared and ungranted, while its real UI
showed the reported shared output and explicitly stated no code ran on that client.
After Revoke, another start was denied. These are two logical browser clients on
one computer, not physical-device timings or a provider-GUI certification.

The audit found a real CLI parsing defect: option-like participant names caused
help/version text and terminated the MCP handshake. Regression tests failed on
0.3.0, then passed on 0.3.1. The reviewer actually reconnected to the same room as
`--help`, made a new exact-revision edit and selected it. Both the older owner
client and the browser received it. Rust/Go bindings received the same fixed
bridge, builds now synchronize their exact bytes and tests enforce consistency.
Rust/Go launchers also refuse extra CLI arguments. Core execution permission and
relay security rules were not broadened.

The room was explicitly ended by its original creator, and status confirmed
Disconnected. Task-owned MCP transports and sockets were stopped. Only sanitized
qualification data and a screenshot without a private room URL are committed.
[Qualification](sdk/2026-10-29/qualification-0.3.1.json) ·
[Exact embedded-core hashes](sdk/2026-10-29/protocol-core-0.3.1.json).

Local validation: 27 JavaScript tests, 4 Rust tests plus a doctest and clippy with
warnings denied, 4 Go race tests and vet. The full Rust fixture also ran with
desktop rustc. `docs/examples/mcp-two-agents/` contains that sanitized fixture.

The new article has 2,559 prose words, three original ImageGen illustrations
(including a permissions infographic) and one actual browser capture. Illustrations
are explicitly conceptual; the screenshot demonstrates the observer output.
[Article record](blog/mcp-real-agents-2026-10-29/article.json) ·
[Prompts, original images and hashes](blog/mcp-real-agents-2026-10-29/images.json).

The final npm consumer check also reproduced duplicate Yjs loading, distinct
constructors and incompatible private TypeScript identities when mixing module
formats. Release 0.3.2 unifies public library/factory runtime and declaration
identity; fresh-process runtime and strict cross-mode TypeScript tests pass.
The live source/Run/Debug flow used the original 0.3.0 owner and a 0.3.1 reviewer
for startup-fix interoperability. Runtime permission code is unchanged in 0.3.2.

Release 0.3.2 is available on npm, crates.io and the tagged Go module, with a
GitHub release. Registry archives match the locally qualified bytes. Fresh
public installs of all three launchers completed actual MCP handshakes; a fresh
npm consumer passed mixed runtime and strict cross-mode TypeScript checks.
Linux/macOS/Windows CI passed. [Publication receipt](sdk/2026-10-29/publication-0.3.2.json).
