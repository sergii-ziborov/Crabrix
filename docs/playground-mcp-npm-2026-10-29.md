# Playground MCP 0.1.1 — npm delivery

The public package is [crabrix-playground-mcp@0.1.1](https://www.npmjs.com/package/crabrix-playground-mcp/v/0.1.1).
It is maintained by the authenticated npm account `sergii-ziborov`.
The user's supplied credential was read from a local file and passed through a
private temporary npm configuration. It is not part of the package, repository,
website or qualification receipts. The temporary configuration was removed.

```sh
npm install -g crabrix-playground-mcp@0.1.1
claude mcp add --transport stdio crabrix -- crabrix-mcp
```

Desktop MCP configuration can use `npx -y crabrix-playground-mcp@0.1.1`.
Node.js 22+ is required. First installation needs network access; the bundled
bridge has no runtime package dependencies or install hooks. Shared rooms need
network transport. Rust compilation and execution remain local to the app/browser.

## Exact distribution

- npm tarball and versioned website archive are byte-identical: 235149 bytes.
- SHA-256: `883ec089d808fa91ec26fffab18b7ba4232d95e3d74fc3d88e99a38c009b4d5b`.
- Registry SHA-512 integrity was checked against the downloaded bytes.
- The immutable 0.1.0 archive is retained unchanged.
- 0.1.1 changes version metadata and installation documentation; its Shared
  room implementation and eight-tool protocol are unchanged from qualified 0.1.0.

## Verification

The package passed TypeScript checks and all three package tests. A separate
empty install directory downloaded 0.1.1 from npm with installation scripts
disabled. Its executable reported 0.1.1. The **registry-installed executable**
then passed the official MCP SDK stdio probe against the production encrypted
relay and actual browser editor: source changes, named selection, actual
browser-local `mcp-public=42` stdout, and creator-only room closure. No browser
page errors occurred. This does not claim a live Claude model-provider call.

The previous [MCP ↔ browser ↔ two native Simulator app matrix](playground-mcp-qualification-2026-10-28.json)
remains evidence for the unchanged room protocol. New package/install receipts:
`build/playground-mcp-20261029/{npm-publish-attempt,registry-verification,public-result}.json`.

The website setup grid now stretches all four cards to the same height and
width at desktop/tablet sizes. A single mobile column retains natural content
height. Six responsive/theme cases verify geometry, no page overflow, one brand,
the pinned install/configuration text and exact downloadable archive.

Discovery, diagnostics and explicitly permitted local execution through MCP
remain separate open work in the [full plan audit](roadmap/audit-2026-10-29.md).
