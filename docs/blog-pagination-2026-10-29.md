# Blog pagination and Rust registry release — 29 October 2026

The 32 Rust blog articles now use 12 cards per archive page: `/blog/`,
`/blog/page/2/` and `/blog/page/3/`. Article URLs, order, illustrations,
related links and full article access remain the same. The shared archive is a
Server Component and adds no client dependency, state, observer or infinite scroll.
Previous/Next and all numbered pages use real links. The current page has
`aria-current`, unavailable directions are not focusable, and active controls
have at least 44 px touch targets. The blog grid fits screens down to 320 px.

Every archive has its own canonical and OpenGraph URL, distinct title/description,
one H1, breadcrumbs and an ItemList containing only its visible articles. The
ItemList count describes the complete 32-article collection and positions continue
across pages. The XML sitemap includes both additional archives (808 unique public
URLs total); it continues to list every article and all lesson previews. The
first-page alias `/blog/page/1/` redirects permanently to `/blog/`; invalid or
out-of-range IDs return real HTTP 404 with noindex rather than an empty archive.

The implementation follows [Google's pagination guidance](https://developers.google.com/search/docs/specialty/ecommerce/pagination-and-incremental-page-loading)
and [Schema.org's paginated ItemList count](https://schema.org/numberOfItems).
No claim of successful indexing, rich results or rankings is made by these checks.

`crabrix` 0.3.0 is now published on crates.io. [Registry receipt](sdk/2026-10-29/crates.json)
records its public owner, immutable archive checksum, source commit and successful
fresh CLI/library consumers. docs.rs serves the typed Client API. The site MCP
cards, guide, capability description and SDK article now link the real package
and API documentation and give Cargo registry installation commands. Node.js 22+
remains explicit. The SDK article contains 2,051 prose words and its existing
three original illustrations. The npm/Go releases and selected native app build
are unchanged.

## Verification

TypeScript, all 38 site tests and the production Next build passed. Local browser
QA passed 32 width/theme cases (320, 390, 820 and 1440 px in light/dark), checking
all archive cards and the updated equal-size SDK cards. All articles were reached
exactly once in order across the archive, with matching structured-data entries.
A JavaScript-disabled browser navigated forward/back, reloaded a direct URL and
used browser history successfully. Seven invalid page IDs returned 404; the
first-page alias returned 308. The native capability selection remains build 120.

Production deployment and final public checks are recorded in the companion
`blog-pagination-2026-10-29.json` after activation of the verified candidate.
