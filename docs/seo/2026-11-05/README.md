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
