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

## Published verification

Published 6 November, 08:24 UTC through Hostwatch on the newly migrated ARM64 server.
The first ARM64 build was interrupted by an operator agent restart before it
produced an image; the operator verified the missing image/processes and closed
that job as failed. A fresh preview and a new operation key produced the successful
build. No uncertain operation was replayed or reported as successful.

- Application source: `684343b` with course snapshot `449c8a2`.
- Serving image: `sha256:633adcdf8a2c42eb409f9e3071f21b564b6dbb5f5d566a95fe5bf3264bb98d9a`.
- The complete container candidate audit and the production audit both checked
  all 833 canonical pages, 771 public full lessons, 600 Atlas steps and 1,209
  internal fragments with no issues. Public media and known lesson starters work;
  private account exports remain authenticated.
- Account backup completed before deployment, and the existing account data mount
  was preserved. The MCP sibling image was unchanged by this website release.
- Published Testing was inspected in all four explicit themes at requested widths
  390, 768, 1024 and 1440; no horizontal document overflow or broken image was seen.
- The prior immutable image is retained for rollback. Only isolated QA state was
  used by the candidate container; no account database was attached to it.

The operator's migration resolved the old server's source-workspace reserve limit.
No quota was reduced and no unscoped image or volume prune was run.

Search Console exports and user analytics remain in ignored local investigation
artifacts. Availability, indexability and sitemap acceptance do not establish
ranking recovery or an exact cause for a loss of impressions. The existing
accepted sitemap must not be duplicated.

## Guide and recovery follow-up

A second website release was published on 6 November at 09:21 UTC from
`b176ab8ef685e701c348297dc81c1fff40f29412`. The source overlay updates the guide,
About/home copy, privacy documentation, signed course snapshot and two real
iPhone/iPad Flashcards screenshots. The active course source is
`f78fcbaf74d200ee5ad002499da5ea38237e750b`; catalog 22 clarifies Clone, Copy
and FnMut terms without rewriting the immutable migration fixture.

- Serving image: `sha256:cd2fda6661836d670da9664639580a1c5d39e1f4c094afe499124440c6dba8b6`.
- Isolated candidate and published HTTP audits each passed 833 canonical pages,
  771 public full lessons, 600 Atlas steps and 1,212 internal fragments.
- Published guide checked at 390 and 1024 pixels in Light, Dark, Amber Circuit
  and Cyberpunk: no document overflow or broken image was observed. Viewport
  and theme were restored after testing.
- Account backup completed before deployment; the account mount and both runtime
  cache mounts remain. The MCP sibling keeps its previous immutable image.
- The prior serving image remains available for rollback. The isolated QA
  container used no account mount and was removed after verification.
- Native iCloud delivery is distinct from website publication: automatic private
  copies remain optional and queued Apple sync is not presented as confirmed
  delivery. The guide states this and documents the independent Files fallback.
