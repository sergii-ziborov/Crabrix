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
stages and the corresponding method guide: 1,800 useful internal paths without
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

Release checks and the exact serving image are recorded in the final delivery
receipt after the configured Hostwatch build, registry publication and deployment.
The retained previous image is the rollback target. No app, npm, remote MCP,
account schema, DNS or nginx modification belongs to this release.
