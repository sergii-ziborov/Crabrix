# Standalone Crabrix SDK and MCP — 29 October 2026

The independent public project is [crabrix-sdk](https://github.com/sergii-ziborov/crabrix-sdk).
[npm crabrix 0.3.0](https://www.npmjs.com/package/crabrix) is published under
sergii-ziborov and installed successfully from the registry. The versioned
[GitHub release](https://github.com/sergii-ziborov/crabrix-sdk/releases/tag/v0.3.0)
contains the identical npm archive. [Registry identity](sdk/2026-10-29/npm.json)
records SHA-256, registry SHA-512, size and maintainer. No credential is stored
in a source tree, tarball, website, receipt or permanent npm configuration.

The npm name was unallocated before publication. This is a working library and
MCP server, not a placeholder/name reservation. ESM, CommonJS and self-contained
TypeScript declarations expose create/connect/status/snapshot/read/apply/select,
explicit edit/view sharing and permission-gated runtime calls. The CLI supplies
fourteen MCP tools. Version 0.2.0 of the prior `crabrix-playground-mcp` remains
available and its immutable website archive is unchanged.

Rust and Go provide typed library APIs and MCP launchers. Both embed the exact
same JavaScript core and **require Node.js 22+**, without a global npm install.
They do not claim independent native cryptography or native Rust execution.
The Go module tag `go/crabrix/v0.3.0` resolves through public Go tooling; the
executable installed from that version reports 0.3.0. The Rust crate builds,
passes tests/doctests/clippy, and is published as
[`crabrix` 0.3.0 on crates.io](https://crates.io/crates/crabrix). The public registry
archive matches the prepared crate byte for byte (SHA-256 in the
[publication receipt](sdk/2026-10-29/crates.json)). The CLI installed from the
registry reports 0.3.0; a fresh registry-dependent Rust application initialized
its real embedded stdio transport successfully. The site now documents
`cargo add crabrix@0.3.0` and the optional Cargo-installed MCP executable.

SDK source and documentation use MIT, selected after the user's request for a
public integrable SDK and discussion of that license. Artwork/screenshots have
separate asset terms; app, compiler distributions and Academy licensing remain.
The real Crabrix crab and three existing app/browser captures appear in the
GitHub, npm and Rust/Go READMEs. Original bundled dependency licenses are retained.

## Verification

- 22 JavaScript checks, including encrypted relay, conditional edits, a lost
  acknowledgement, view/creator authority, Unicode selections, runtime signatures,
  protocol framing, real stdio and ESM/CommonJS imports.
- Strict independent ESM and CommonJS TypeScript consumers without Yjs/MCP type
  dependencies; registry-installed CLI version readback and exact archive hashes.
- Rust unit tests, doctest and clippy with warnings denied; Go race checks and vet.
- GitHub CI passed on Linux, macOS and Windows for SDK/core/binding checks.
- A real four-participant production room: JavaScript owner, Rust reviewer, Go
  reviewer and a browser. Edits and named selections reached the same document,
  Unicode survived, and a stale revision was refused. The room was ended.
- An official MCP client exercised the production browser compiler: explicit
  preparation and permission, Build without main execution, Run stdout,
  concrete/String/Vec Debug locals, Step and owned Stop. Plaintext source did not
  appear in captured HTTP POST bodies. This is not a physical-device benchmark
  or a new live Claude-provider/model session.

[Qualification](sdk/2026-10-29/qualification.json) · [Common core hashes](sdk/2026-10-29/protocol-core.json).

The app and selected 1.1.3 build 120 are unchanged. Runtime wire/profile and
client-local approval rules remain compatible; the new SDK adds source-library
and handoff APIs. Joining/editing never starts another client. The relay stores
bounded temporary ciphertext in RAM and never compiles source. One-hour default,
24-hour maximum, four participants, 16 files/64 KiB each/128 KiB total remain.
No account project, repository history, package hosting or GitHub replacement
was added. Names are labels; compare runtime controller/client fingerprints.

## Website and articles

The MCP page now describes a standalone library and all three language APIs,
with source links, precise Node requirements, installation and optional app use.
The guide links the APIs and agent handoff. Existing card layouts, navigation,
themes, app screenshots and access guards are retained. SDK code, source links
and license metadata use the existing server-rendered components.

Two original practical articles are dated 29 October: a shared Rust interview
workshop (2100 prose words) and SDK integration (2051 prose words), each with
three original generated illustrations. Both include an infographic and the
orange crab, internal course/article links and primary technical sources.
[Article/media record](blog/sdk-2026-10-29/articles.json) · [Prompts and assets](blog/sdk-2026-10-29/images.json).
PNG originals and responsive 640/full WebP variants are included. Go highlighting
was added without changing source bytes; existing JSON/TypeScript/shell article
blocks now use the established themed highlighter. New Rust example assertions
ran on desktop Rust 1.99; no claim of physical-iPhone speed is made.

Site TypeScript, all 36 site tests, production build and 30 responsive/theme
browser cases passed. Updated pages have one H1/canonical, working images and
links, matching article word counts/JSON-LD and no page overflow. MCP setup and
SDK cards retain equal widths/heights. The sitemap now contains 806 canonical
URLs, including both articles. Published to the existing Hetzner site at 2026-10-29T15:54:29Z with the previous container retained for rollback and a fresh account backup. The account mount and selected app build were preserved. All 806 sitemap pages passed the public metadata crawl; another 71 linked targets resolved without errors. No duplicate titles/descriptions, broken internal fragments, missing image alt text or invalid JSON-LD were found. All 30 responsive/theme cases also passed against production. [Deployment receipt](sdk/2026-10-29/site-deployment.json).

## Registry and archive follow-up

The crates.io release is now confirmed and the blog has three linked archive
pages with 12 articles per page. The sitemap grows from the initial 806 URLs
to 808, retaining every article and lesson. All 38 site tests and 32 local
responsive/theme cases passed, including no-JavaScript pagination and real
404/308 responses. See [pagination and SEO details](blog-pagination-2026-10-29.md)
and [crates.io proof](sdk/2026-10-29/crates.json).
