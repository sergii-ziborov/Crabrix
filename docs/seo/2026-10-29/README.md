# Crabrix SEO audit — 29 October 2026

The public sitemap was fetched and every one of its 804 canonical URLs crawled
with four concurrent requests: 754 lesson previews, seven courses, 30 articles
and 13 product/index pages. All returned 200, had one matching canonical, one
H1, a description and a title. Titles and descriptions were unique; JSON-LD
parsed; no missing image alt attribute or broken local fragment was found.
Another 75 distinct linked targets outside the sitemap were checked, including
screenshots, notices, archives and authentication routes. None was broken.
[Recorded baseline](baseline.json). These are direct site checks, not Google
indexing/report data, and they do not establish rankings or Core Web Vitals.

Changes:

- Canonical destinations replace five redirecting content-link targets in the
  checked-in legacy HTML. Existing `/index.html` links now have a permanent
  redirect to the home page, alongside the previous `.html` redirects.
- Four articles changed on this date carry an explicit recorded modified date
  in their visible date line, OpenGraph, BlogPosting and sitemap. Original
  requested publication dates, code, paragraphs and images are retained.
- Six course search descriptions now explain their actual learning topics and
  access policy; the existing algorithm description remains. The Academy index
  adds a seven-course ItemList matching its visible course links and the detail
  pages' existing Course markup. The Academy sitemap modification date records
  this structured-data update. No ratings, fake instructors or new offers added.
- Normal pages rely on default index/follow behavior. Removing global positive
  index directives prevents them from appearing alongside Next's noindex on 404s.
- Public authentication pages stay noindex and are crawlable so crawlers can
  observe that directive. Authentication/account/API/health responses receive
  explicit noindex headers. Account authentication and all lesson/media guards
  remain; temporary rooms and relay paths retain crawler exclusions and private
  cache/referrer controls. No room is created or code executed by this audit.

The layout, CSS, native app, MCP package and App Review selection are unchanged.
React review: server components remain server-only; no hooks, client bundle,
fetch waterfall, new dependency or request-shared user state was introduced.
StructuredData keeps its existing safe JSON serialization. Responsive checks
cover the visible updated-date line and unchanged main page layouts.

Google Search Console for `sc-domain:crabrix.com` accepted the sitemap with
status **Успешно / Success**, 804 discovered pages and one submitted sitemap.
The submission and last-read dates are both 29 October. The existing Chrome
session was used; no credentials were read or stored. [Readback](search-console.json)
and the saved screenshot record Google's actual result. Discovery is distinct
from indexing. The deferred automation was paused when the user requested
immediate work. The inspected robots-blocked report lists 476 URLs (reported update: 23 October);
all ten visible samples are login/register return URLs. This is not evidence
that 476 lessons are blocked. Lesson login/register return links now use nofollow
and disable speculative prefetch. The full excluded-URL list was not exported,
and other Google statuses are not inferred from this category. After deployment,
Google accepted the validation request and displays **Started, 29 October 2026**.
The requested revalidation has not completed.

The indexing overview was last updated on 23 October: 918 indexed and 606
excluded URLs across four categories. These are all processed URL variants,
not the newly submitted sitemap's counts. Ten samples from the 124 redirecting
URLs were read back: all redirect permanently to a working canonical page.
The five crawled/not-indexed examples comprise two variants of the permutations
lesson, the XML sitemap itself, and two old HTTP www URLs. The lesson currently
returns 200 and its slash variant redirects to the same canonical. Sitemap XML
does not need to appear as a search result. No new content or indexing guarantee
was invented to explain Google's historical classification.

The apex domain is the published canonical host. The unused `www` hostname has
no DNS result in this audit. Google retains its HTTPS home page as one historical
duplicate and two HTTP URLs in the crawled/not-indexed examples. Cloudflare's
dashboard requires a separate sign-in; the user was asked to complete it before
any DNS or certificate change. The canonical apex remains available.

The production release is `localhost/crabrix-web-site:seo-d401c4d`, digest
`cbbb7eaad45310c7324bc9a62539d9fc45410b5fe240d368e6f66b83227f522e`.
It was published at 11:11:51 UTC and is healthy. The account volume is preserved,
the account backup completed, and the preceding container remains available for
rollback. All 804 canonical URLs returned 200 after publication, with unique
titles/descriptions, matching canonicals, valid JSON-LD and no broken local
fragments. The public 24-case responsive/theme matrix and eight private/service
noindex checks passed. TypeScript, all 35 site tests and the production build
passed before deployment. [Delivery receipt](delivery.json).

Primary guidance checked:

- https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap
- https://developers.google.com/search/docs/crawling-indexing/robots/intro
- https://developers.google.com/search/docs/appearance/structured-data/article
- https://developers.google.com/search/docs/appearance/structured-data/course
- https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls

Local qualification, public readback and release identity are recorded in the
final delivery receipt. Source audit logs and screenshots are retained under
`build/seo-audit-20261029/`.
