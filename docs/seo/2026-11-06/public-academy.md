# Complete public Academy — 6 November 2026

The owner approved full reading without registration. Complete explanations,
worked code, questions, answer reveals, algorithm playback, known lesson
illustrations and qualified Playground starters now use the same public content
path for ordinary browsers and crawlers. Existing URLs, lessons, themes and
navigation are preserved. Accounts and private exports remain authenticated.
The source corpus is not served as an arbitrary filesystem download.

Article markup identifies the visible lessons as free; stale registration copy
was removed from the Academy, guide, home/about, legal pages and account story.
The fixed editorial opening date updates lesson-page and sitemap modification
signals; build time is not substituted for editorial dates. The short-quotation
licence and permission requirement for complete redistribution are unchanged.

Twelve readings and six diagrams are synchronized from course source commit
`449c8a2ba724abbd2560f18cc31d29e49937866c`. Signed catalog 21 was activated only
after downloading and byte-checking the new release assets. See the
[curriculum depth review](../../academy-senior-review-2026-11-06.md).

## Verification before publication

- 151 site tests and TypeScript passed.
- The webpack build compiled, type-checked and generated all static pages locally.
  Standalone packaging then failed with ENOSPC on the Mac; this is not recorded
  as a successful deployable build. Failed temporary output and reproducible
  caches were removed, retaining receipts and tracked archives.
- The resulting regular local production server passed HTTP checks for all 833
  canonical sitemap pages, 771 full lessons, 600 algorithm steps and 1,209 internal
  fragments. Canonical, description/title uniqueness, JSON-LD, image dimensions,
  public media/starters, private export denial, noindex routes and unknown paths
  passed. No issues were recorded.
- Browser checks covered Testing and a real Atlas walkthrough in four themes at
  widths 390, 768, 1024 and 1440. No document overflow or broken image was observed.
  Answer reveal and moving playback to the final stdout `2` worked without login.

Publication uses the existing Hostwatch source/build, registry and deployment
steps, with the existing account volume, backup and rollback retained. At this
checkpoint it is **not yet deployed**: the server's 7 GiB source-workspace reserve
exceeds its free space. Only two superseded, unpublished Crabrix source trees
were discarded through the configured API. The Hostwatch chat has the capacity
issue as well as the separate shared-Nginx incident. No quota was reduced and no
unscoped image or volume prune was run.

Search Console exports and user analytics remain in ignored local investigation
artifacts. Availability, indexability and sitemap acceptance do not establish
ranking recovery or an exact cause for a loss of impressions. The existing
accepted sitemap must not be duplicated.
