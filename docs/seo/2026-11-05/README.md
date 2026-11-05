# Academy and website SEO — 5 November 2026

The baseline public crawl checked all 833 unique canonical sitemap URLs: 771
lesson previews, seven course pages, 39 articles and 16 product/archive/index
pages. All returned 200 with one matching canonical, one H1 and one description.
Titles and descriptions were unique, JSON-LD parsed, image alt attributes were
present and internal fragments resolved. Another 71 linked targets had no broken
response; legacy MCP links redirected to /ai/ and account access redirected to
sign-in. This is a direct technical audit, not a claim about Google rankings,
index counts or field Core Web Vitals. [Baseline receipt](baseline.json).

Confirmed improvements in this revision:

- Recorded last-modified dates for the expanded Academy, licenses and privacy
  now match their actual editorial revisions. Blog publication/update dates use
  the same rule in OpenGraph, BlogPosting and sitemap, including backfills.
  Archive dates derive from their listed articles, never the build clock.
- The Serde and async cancellation articles link to their actual qualified local
  Academy examples, with reciprocal public related-reading links from those
  five lessons. Their updated platform guidance distinguishes real local Serde
  traits / Tokio rt+sync from the articles' broader derive/timer/macro graphs.
  Legacy setup links use the canonical /ai/ destination. Go SDK copy explicitly
  describes connecting a Go program to a Rust Playground.
- Ten older article illustrations lacked intrinsic width/height. Their actual
  dimensions are now provided. The 771 lesson infographics also supply their
  exact PNG dimensions, reserving space without changing layout or images.
- One browser screenshot had JPEG bytes under a .png name. The canonical .jpg
  is byte-identical; the old URL redirects permanently. Existing WebP variants
  remain byte-identical, and picture delivery handles PNG/JPEG originals.
- Robots exclusions, login noindex, canonical hosts, existing pagination,
  lesson previews and full-text/media account checks remain. No user-agent
  bypass exposes protected lessons to crawlers. No app binary, npm package,
  remote MCP component or App Review selection is changed by the SEO work.

149 site tests include actual PNG/JPEG dimensions, reciprocal link targets,
publication dates, private starter serialization and the existing access tests.
The production build succeeds. Delivery and post-publication readback are recorded
separately once the exact source is built and the configured web target is updated.

The review follows Google's primary guidance on
[sitemaps](https://developers.google.com/search/docs/crawling-indexing/sitemaps/overview),
[canonical URLs](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls),
[image delivery](https://developers.google.com/search/docs/appearance/google-images)
and [registration/paywall markup](https://developers.google.com/search/docs/appearance/structured-data/paywalled-content).

Publication and final verification

The configured Hostwatch source builder built commit 343aef5 as image
8e2dbd8f3cf7…; registry publication and the independent web deployment both
finished successfully. The isolated candidate first passed all 833 URLs and
normal sign-in/full-lesson navigation. A consistent account backup preceded
cutover. The existing production account session still opens full lessons;
account/cache mounts, limits and the sibling remote MCP container are unchanged.
The prior image remains available for the configured rollback. No DNS, nginx,
app binary, npm package or App Review change was made.

The public post-publication crawl passed all 833 canonical URLs, 70 additional
internal destinations and 129 unique image/social-image URLs. No duplicate
metadata, missing intrinsic image dimensions, invalid JSON-LD or broken internal
fragment was found. HTTP, www, slash normalization and the old image URL return
permanent redirects. Nonexistent routes remain 404/noindex, auth pages noindex,
and Googlebot/Twitterbot receive the same bounded lesson preview as other guests.
Guest starter/media/raw-corpus gates remain 307/401/404 respectively.

Sixteen published full-lesson cases cover widths 390/768/1024/1440 across Light,
Dark, Amber Circuit and Cyberpunk; the related article also passed phone, tablet
and desktop widths. No horizontal page overflow was observed. Both directions
of article/lesson navigation work, and the lesson's starter opens in a separate
Playground tab. Intrinsic dimensions reserve image space; this audit does not
claim a measured field CLS or Core Web Vitals improvement.

In the existing authorized Search Console session, sc-domain:crabrix.com already
has one https://crabrix.com/sitemap.xml entry, status Успешно, submitted 29 October,
last processed 4 November, with 809 discovered pages. That count is Google's
previous sitemap discovery, not a count of indexed pages or the current 833 URLs.
No duplicate submission was created. The index coverage report remained blank
after navigation and reload, so index counts, coverage reasons and field Core Web
Vitals were not verified and no revalidation success is claimed.

[Final HTTP results](published.json), [deployment receipt](release.json),
[theme/viewport cases](layout.json), [article cases](article-layout.json),
[published Academy screenshot](published-academy.png).
