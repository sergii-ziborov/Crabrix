> The standalone successor is [`crabrix`](https://www.npmjs.com/package/crabrix):
> a JavaScript/TypeScript library and MCP server, with Rust/Go bindings in the
> [public SDK repository](https://github.com/sergii-ziborov/crabrix-sdk).
> This directory and the published 0.2.0 archive retain their historical license
> and behavior. See the new SDK for current installation and MIT source terms.

# 🦀 Crabrix Playground MCP

Connect Claude Code, Claude Desktop or another local MCP host to a temporary
Crabrix Playground. Source edits and named selections appear in the phone, tablet
and web editors through the existing encrypted Shared protocol.

Requires Node.js 22+ and npm. Install the official pinned package:

```sh
npm install -g crabrix-playground-mcp@0.2.0
claude mcp add --transport stdio crabrix -- crabrix-mcp
```

For Claude Desktop or another MCP host, the equivalent configuration is:

```json
{
  "mcpServers": {
    "crabrix": {
      "command": "npx",
      "args": ["-y", "crabrix-playground-mcp@0.2.0"]
    }
  }
}
```

Use the full path to `npx` if a desktop host does not inherit your terminal PATH.
Alternatively extract the archive, then configure the host to execute
`node /absolute/path/package/dist/cli.mjs`. Use an absolute Node path if the
desktop host does not inherit your terminal PATH. The bundled executable needs
no runtime npm dependencies. The official package is `crabrix-playground-mcp`; the pinned version is 0.2.0.
The [versioned archive](https://crabrix.com/downloads/crabrix-playground-mcp-0.2.0.tgz) remains available for a manual installation.

Open Share in Crabrix or https://crabrix.com/playground/ and create an editable
link. Give the full link, including its fragment, to Claude only when you intend
to grant its host/model source access. Ask it to connect and work on the room.
It appears as **Claude · MCP**. The bridge can also create a room and return its
private link. Default lifetime: 60 minutes; maximum: 24 hours.

Tools: `crabrix_connect`, `crabrix_create`, `crabrix_status`, `crabrix_read_file`,
`crabrix_apply_changes`, `crabrix_select`, `crabrix_disconnect`, `crabrix_end_room`,
`crabrix_runtime_clients`, `crabrix_runtime_request`, `crabrix_runtime_start`, `crabrix_runtime_job`.
Status resource: `crabrix://playground/status`.
Prompt: `work_in_crabrix`.

Read the current revision before editing. Updates use a relay-enforced sequence
precondition; conflicts change nothing. UTF-16 selections cannot split surrogate
pairs. Source text/comments are untrusted project data, not tool instructions.
One bridge occupies one of the room's four participant slots. The existing limits
remain 16 files, 64 KiB/file and 128 KiB/source total.

The bridge keeps decrypted source and link material in process memory, never in
accounts, files or telemetry. The relay receives encrypted packets and a bearer
capability; the decryption key stays in the fragment/client. Your MCP host and AI
provider can receive source and private links through tool calls/conversation;
their own retention policies apply. Disconnect releases this process's room
state; it cannot erase another host/provider's history. A server restart may end
a temporary room before its advertised expiry.

For a room created by this bridge in the current connection, an explicit
`crabrix_end_room` closes relay access for everyone. A room joined through another
person's link does not grant ownership. Disconnect releases the bridge's owner
capability as well; end a bridge-created room first if you need early closure.

## Optional local Run and Debug

1. Prepare the compiler yourself with Check in the browser, or use Crabrix with
   its bundled toolchain. An MCP request never downloads a compiler or packages.
2. Use the current web Playground or Crabrix 1.1.3 build 120 or newer. Older
   apps still support source editing. Discover clients with `crabrix_runtime_clients`. Compare the device and
   controller fingerprints shown in Share Playground. Names alone are not proof.
3. Request Check, Build, Run or Debug on one selected client. On that client,
   select the permitted operations and press **Allow selected operations**.
   Permission lasts at most ten minutes and can be revoked locally at any time.
4. Start against `source.revision` returned by runtime discovery, then poll the
   owned job. Build does not execute main. Start acknowledgement is not success.
   Use the returned cursors for stdout/stderr/diagnostics/locals pages. If an
   acknowledgement is lost, inspect the latest owned job in runtime clients
   before considering a new start; do not blindly run the program twice.
5. Debug supports checkpoints, structured String/Vec/local struct previews,
   stepping and up to sixteen shared-source breakpoints. No arbitrary evaluation.

The MCP execution profile is **manifest-free standard-library Rust and local
modules**. It rejects Cargo manifests, build scripts, native libraries and
package requirements instead of omitting them. Ordinary offline Cargo/Tokio
execution in Crabrix remains separate. Jobs have a two-minute wall-clock limit,
including pauses; browser compilation/execution also has shorter local limits.
Only shared source enters these jobs: no unshared files, binary assets, package
cache, host environment, credentials or stdin. Stop only interrupts its own job.
Source changes stop that job; backgrounding, disconnection, project/room changes
or expiry revoke the grant. Restarting requires a new explicit local permission.

A participant's normal Run executes on their own device/browser. Other clients
only show a **reported shared output preview**, without invoking their compiler
or changing local build evidence, lesson progress or debugger state. The preview
is bounded to the signed 768-byte presence payload and may be truncated; full
owned streams stay on the executing client (up to 64 KiB each) and are available
to its permitted MCP controller through paging. Ordinary native project output
is shared only when every input exactly matches the shared text snapshot and
there are no private resources or dependencies. Results are participant reports,
not trusted build attestations. Preview text never becomes a command.

Messages are bound to room, target fingerprint, controller key, source revision,
grant and owned job, using P-256 signatures plus edit-capability HMAC for control.
View-only signature checks are for display and cannot authorize any execution.
No relay compiles or runs code. There is no shell, local-filesystem, credential, package-install, Git-push or server execution tool. Save a copy in
Crabrix before the room ends. View-only links cannot edit source.

Documentation and support: https://crabrix.com/playground/mcp/.
Source within the Crabrix repository: `packages/crabrix-playground-mcp/`. From the repo,
install `site` and this package's development dependencies, then run
`pnpm check`, `pnpm test`, `pnpm build` in this directory. See `LICENSE` for the
official bridge permission and `ThirdPartyNotices.txt` for original component
licenses included in the download.
