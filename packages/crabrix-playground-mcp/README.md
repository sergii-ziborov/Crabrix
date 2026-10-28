# Crabrix Playground MCP

Connect Claude Code, Claude Desktop or another local MCP host to a temporary
Crabrix Playground. Source edits and named selections appear in the phone, tablet
and web editors through the existing encrypted Shared protocol.

Requires Node.js 22+. Install the official versioned download:

```sh
npm install -g https://crabrix.com/downloads/crabrix-playground-mcp-0.1.0.tgz
claude mcp add --transport stdio crabrix -- crabrix-mcp
```

Alternatively extract the archive, then configure the host to execute
`node /absolute/path/package/dist/cli.mjs`. Use an absolute Node path if the
desktop host does not inherit your terminal PATH. The bundled executable needs
no runtime npm dependencies. This package is distributed by Crabrix; it is not
claimed to be published on the npm registry.

Open Share in Crabrix or https://crabrix.com/playground/ and create an editable
link. Give the full link, including its fragment, to Claude only when you intend
to grant its host/model source access. Ask it to connect and work on the room.
It appears as **Claude · MCP**. The bridge can also create a room and return its
private link. Default lifetime: 60 minutes; maximum: 24 hours.

Tools: `crabrix_connect`, `crabrix_create`, `crabrix_status`, `crabrix_read_file`,
`crabrix_apply_changes`, `crabrix_select`, `crabrix_disconnect`, `crabrix_end_room`.
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

This version reads/edits source and selections. Run and Debug remain explicit
local actions in Crabrix or the browser. There is no shell, local-filesystem,
credential, package-install, Git-push or server execution tool. Save a copy in
Crabrix before the room ends. View-only links cannot edit source.

Source: `packages/crabrix-playground-mcp/` in the Crabrix repository. From the repo,
install `site` and this package's development dependencies, then run
`pnpm check`, `pnpm test`, `pnpm build` in this directory. See `LICENSE` for the
official bridge permission and `ThirdPartyNotices.txt` for original component
licenses included in the download.
