# Six missing editorial dates, filled on 4 November 2026

The existing blog had 33 posts and no articles for 30–31 October or 1–4 November.
The six new articles fill those slots, with actual publication explicitly dated
4 November in the visible article metadata, OpenGraph and BlogPosting JSON-LD.
The earlier date is an editorial slot, not an invented announcement date.

| Editorial date | Topic | Prose words | ImageGen originals |
| --- | --- | ---: | ---: |
| 30 October | Variadic-generics survey and stable tuple adapters | 2,090 | 3 |
| 31 October | GPU notification group, linker work and build boundaries | 2,092 | 3 |
| 1 November | Rust 1.99.1 and a C/Rust ABI smoke fixture | 2,028 | 3 |
| 2 November | Debugger maintenance, String, Vec and structs | 2,072 | 3 |
| 3 November | rustup 1.29.3 and manager recovery | 2,034 | 3 |
| 4 November | Crabrix 0.5.0, local MCP and direct remote MCP | 2,430 | 3 |

Counts include paragraph prose only, excluding code, headings, captions and links.
The 33 preceding post objects remain unchanged. The catalog now has 39 posts and
four archive pages. Sources are linked beside the relevant text; announcements
are distinguished from our original practical examples and recommendations.

The built-in ImageGen tool generated all 18 PNG originals using the Crabrix mark
as a reference. Each article has a cover, a conceptual infographic and a workshop
illustration. Exact prompts are in `image-prompts.json`; original paths, dimensions
and hashes are in `image-assets.json`. Delivery assets are under
`site/public/images/blog/november-2026/`, with full and 640px WebP versions.
All images were visually inspected. They are conceptual artwork, not fake product
screenshots, measurements or survey charts.

Five complete Rust/C-Rust fixtures passed on the recorded aarch64 macOS Rust
1.99.0 host. `verify-examples.py` extracts the displayed examples, formats and
compiles them, runs the assertions, and records exact hashes and output in
`example-verification.json`. The ABI fixture is a smoke test on this host,
not a reproduction of the reported x86_64 regression. No GPU, UEFI, Solaris or
physical-phone qualification is claimed.

For the agent article, the verified published crabrix 0.5.0 tarball joined the
production relay through local stdio and direct Streamable HTTP MCP clients.
Their edits converged; a stale remote update received REVISION_CONFLICT. A real
browser showed the source and named selection, completed local Run with Exit 0,
and paused Debug with Report, Unicode String and two Vec values. An ungranted
agent Run was refused with RUNTIME_GRANT_REQUIRED. The room was explicitly ended
and the browser showed it closed. These were protocol clients and a browser on
one Mac, not tests of every AI provider or two physical devices. The secret links
were removed from local research files; the public evidence contains none.

Website tests, TypeScript, build, responsive rendering, image decoding, canonical
and structured-data checks, primary-source and internal-link checks are recorded
with the delivery receipt. The site uses the existing Hetzner release process,
consistent account backup and retained rollback image/container. The native app,
selected App Review build, SDK packages, remote MCP service and DNS are outside
this publication change.

The JavaScript integration example also passed Node syntax checking and an actual create/read/apply/share round trip with the published `crabrix@0.5.0` tarball. An extra read-back assertion confirmed the patch, and the test creator ended its room in `finally`; no capability links were logged. See `javascript-example-verification.json`.
