# Public Atlas guidance and crawl efficiency — 6 November 2026

This release retains all 833 canonical sitemap URLs, all 771 Academy lessons,
existing articles, themes and registration requirements. It expands the existing
Algorithms course rather than creating shallow copies or removing lesson pages.

Every one of the 200 mental-model / recognition pairs previously began with the
same 80 public explanation words: fixture details and generic output formatting
consumed the preview before its actual teaching stage. The bounded excerpts now
lead with the mental model, method-selection argument or challenge contract.
All 600 public stage bodies are distinct. The existing 30% total / 60% explanation
caps, server-side full-text gate and protected media/starter routes remain.
The full app course snapshot and signed packs are unchanged.

Twenty original method guides add 2,483 public words about choosing a method,
preconditions, counterexamples, representation and Rust pitfalls. A method index
links to the existing unit anchors. Each of the 600 steps links to its two sibling
stages and the corresponding method guide: 1,800 additional internal links without
changing canonical URLs. Recorded modification dates agree between metadata and
the sitemap. Reference reading points to Rust's own collection/slice documentation
and MIT's original algorithm-design lecture notes.

Historical crawler logs show excessive requests to Next.js `_rsc` cache-busting
variants. Automatic prefetch is now disabled in shared header/footer navigation,
the Academy indexes, lesson links and the HTML sitemap. Ordinary anchors and
client-side navigation still work. The revised course load in a real browser
makes zero automatic RSC requests; an intentional lesson click makes one and
opens the correct lesson. No robots exclusion, HTML noindex or redirect is applied
to `_rsc` query variants. This avoids confusing real HTML with a Flight payload.
A normal HTML request with that parameter retains its clean canonical and stays
indexable. `/favicon.ico`, previously a confirmed 404, permanently redirects to
the existing crab logo.

The search-visibility investigation is deliberately separated from these fixes.
Google's inspected formerly visible lesson remained indexed, fetched successfully
on 31 October with its self-canonical accepted. The manual-action and security
reports showed no issues; Crawl Stats showed no host availability issues. The
coverage report available during inspection predates the exposure drop. The stale
www robots warning predates it as well; Google accepted a request to refresh that
check. These observations do not prove all pages are indexed, and neither the
technical audit nor the content improvements establish Google's exact ranking
reason or a recovered search position. Private GSC exports and access logs are not
included in this repository.

`site/scripts/audit-public-seo.mjs` checks the complete canonical sitemap over
HTTP, metadata uniqueness, structured-data syntax, image dimensions, public stage
introductions, internal fragments and full-lesson/media/starter access boundaries.
Run `npm run audit:seo -- https://crabrix.com /tmp/seo-receipt.json` from `site`.
It also checks that an ordinary `_rsc` HTML URL is not accidentally noindexed.

Publication and verification

Hostwatch built the final `c75df3b` source with webpack, published its registry
manifest, and verified the independent web deployment at 22:23 UTC on 5 November
(6 November in the workspace timezone). The serving image is `0e23a563005f…`;
the previous `8e2dbd8f3cf7…` image is retained for rollback. A consistent on-host
account backup completed before cutover. The account/cache mounts and sibling MCP
container identity remained identical. The existing account session still opens
complete lessons. The temporary candidate and QA tunnel were removed afterwards.

151 tests, TypeScript and production builds passed. The server candidate passed
all 833 canonical pages, as did the subsequent public audit: 771 gated previews,
600 stage-specific introductions and 1,809 internal fragment references, with no
reported issue. Twenty published course layout cases cover four widths and all
five themes; sixteen full-lesson cases cover the same widths and four explicit
themes. No horizontal page overflow was observed. Repeated method-index clicks
replace the URL fragment correctly, with headings visible below the sticky header.
Navigation from a method into a lesson and between its stages works. The published
course load made zero speculative RSC requests, and the browser reported no errors.
All 19 linked CSS/JavaScript assets from eight representative published pages
returned 200; the legacy favicon request now redirects to the existing PNG logo.
These are technical checks, not a measured field Core Web Vitals or ranking gain.

[HTTP audit](published.json), [release receipt](release.json),
[course layouts](course-layout.json), [full-lesson layouts](lesson-layout.json),
[prefetch observation](prefetch.json), [linked assets](assets.json),
[published guide](published-method-guide.png).

No app, npm, remote MCP, account schema, DNS or nginx modification belongs to this
release. No search-traffic recovery or completed Google reprocessing is claimed.
