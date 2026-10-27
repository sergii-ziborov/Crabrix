# Crabrix website deployment

## Academy corrections — 27 October 2026

The live service uses `localhost/crabrix-web-site:academy-corrections-20261027`,
pinning course source `97564ab44b4d9b53824f59354bc1d6bc7fa7e4f0`. All 742 lesson
objects and 182 unique images match authoring. Changes include 600 Atlas steps,
eight Rust lessons, two replacement diagrams and Rust/TOML/SQL highlighting.
Sixteen site tests, TypeScript and production build passed. Authenticated browser
checks covered phone, tablet and desktop in light/dark themes. A consistent
account backup preceded cutover; the previous service is retained as
`crabrix-web-site-before-academy-corrections-20261027`.
[Publication evidence and scope](academy-corrections-2026-10-27.md).

## Measured Rust performance guide — 27 October 2026

The current service uses `localhost/crabrix-web-site:rust-performance-20261027`
from source `3a909b040ff5ed1ccc35f0b9ed9235c82bb0d921`. The new article has
2,012 paragraph words, three original ImageGen images and two infographics.
It includes tested owned/borrowed log classifiers, Debug/Release comparisons,
benchmark boundaries, optimizer barriers and saved raw desktop observations.
All 26 previous article objects remain unchanged. The catalog contains
27 articles, 56 original public blog images and 787 canonical sitemap URLs.

Eight semantic tests passed in both development and Release profiles, alongside
15 site tests, TypeScript checking and the production build. One development
and three Release benchmark processes ran sequentially on an Apple M4; their
raw samples and scope are preserved. No measured allocation count or qualified
iPhone timing is claimed. Browser verification covered 390, 820 and 1440-pixel
widths in light/dark themes, with all images decoded and no page overflow.

Nineteen candidate/production HTTP checks and 16 public HTTPS checks passed,
including article metadata, both sitemaps, nine original/WebP image digests,
guest lesson gating and private-media denial. A public mobile browser check
also passed. This is a focused publication check, not a new crawl of every page.
A consistent account backup preceded cutover; the account mount and resource
limits are retained. The old service is stopped as
`crabrix-web-site-before-rust-performance-20261027` for rollback. DNS, Nginx
and the app binary are unchanged.

[Publication evidence](site-release-2026-10-27-article.json),
[images and prompts](blog-assets-2026-10-27.json),
[raw observations](benchmarks/measured-performance-2026-10-27/README.md).

## Async cancellation guide — 26 October 2026

The current service uses `localhost/crabrix-web-site:async-cancellation-20261026`
from source `05fdaafc5ef886c482d1e9e8f12b07bf65d61dc6`. The new article has
2,095 paragraph words and three original ImageGen images, including two
infographics. It covers Tokio deadlines, queue ownership, task cancellation,
partial I/O, shutdown and retry contracts. All 25 preceding articles are
unchanged. The catalog now contains 26 articles and 53 public blog images;
XML and HTML sitemaps include the article, with 786 canonical XML URLs.

Eight native Rust contract tests, 14 site tests, TypeScript checking and the
production build passed. Browser checks covered 390, 820 and 1440-pixel widths
in light and dark themes, with all three images decoded and no page overflow.
Nineteen candidate and production checks passed; 16 public HTTPS checks verified
the new article metadata, both sitemap representations, all nine original/WebP
image digests, guest lesson gating and private-media denial. This is a focused
release check, not a new crawl of every existing page.

A consistent account backup completed before cutover. The persistent account
mount, resource limits and backup schedule are retained. The preceding service
is stopped as `crabrix-web-site-before-async-cancellation-20261026` for rollback.
DNS, Nginx and the app binary were not changed.

[Publication evidence](site-release-2026-10-26-article.json),
[images and exact prompts](blog-assets-2026-10-26.json),
[reproducible example](examples/async-cancellation/README.md).

## Brand and shared navigation — 25 October 2026

The service now uses `localhost/crabrix-web-site:brand-navigation-20261025`.
The header and favicon share the native orange CrabrixMark image, replacing
the platform emoji. Main navigation highlights the current section on all
pages, including nested lessons and articles. Light-mode secondary buttons
and Rust syntax colors now retain readable contrast.

Thirteen tests, TypeScript checking and the production build passed. Browser
checks covered light/dark themes, route changes, 390px mobile and 820px tablet
widths without page overflow. Fifteen candidate checks passed before cutover;
public HTTPS checks verified the pages and the exact logo digest. The account
mount, limits and backup schedule are retained. A consistent account backup
completed before switching, and the previous container is stopped as
`crabrix-web-site-before-brand-navigation-20261025`. DNS and Nginx are unchanged.

[Publication evidence](site-release-2026-10-25-brand-navigation.json),
[light theme](screenshots/site-brand-light-2026-10-25.png).

## Earlier release 87 service verification — 25 October 2026

The live service was read back as `crabrix-web-site-1`, image
`localhost/crabrix-web-site:release87-20261025`, running and healthy. This
supersedes the guide-only image described below. It includes the guide
2048-package update and synchronized WABT notices. App build 88 changes Cargo
feature resolution and has no corresponding website layout or feature change;
the website continues to describe the shipped capabilities.
[Publication evidence](site-release-2026-10-25-build87.json).

## Detailed offline guide and compiler measurements — 25 October 2026

The manual release `localhost/crabrix-web-site:guide-20261025-r3` runs on the
existing loopback port 3212. The account mount, 512 MiB memory limit, 0.75 CPU,
256-process limit, no-new-privileges option and backup timer are preserved.
A consistent account backup completed before switching. The preceding server
remains stopped as `crabrix-web-site-before-guide-20261025` for rollback.

The illustrated guide now includes a first-project walkthrough, exact offline
pinning steps, package-state explanations, Check/Run and build-stage behavior,
web editing and snapshot refresh, code, troubleshooting and concrete limits.
Eight distinct real captures cover Projects, Rust code, WebKit output, courses,
examples, an example explanation with its infographic, Duo and iPad. A mistaken
My Projects caption over the examples gallery was removed. Rust raw strings
now use matching hash delimiters in website syntax highlighting.

Technology separates the measured experimental Tokio/Axum profiles from the
installed compiler. Three small Tokio cold runs took 29.78/27.88/28.54 seconds;
the 22-dependency Axum in-memory router took 126.29 seconds. The large Kameo
macro graph and 30-second large-project objective remain unqualified. No
compiler experiment is advertised as an App Store shipment.

Thirteen site tests, TypeScript and the production build passed. Candidate and
public HTTPS checks verified both changed pages, metadata, all eight source
image digests, actual raw-string markup, 785 sitemap entries, 50 blog images,
recorded page modification dates, account noindex and private media denial.
Browser verification confirmed all eight images loaded and no horizontal
overflow. The 742-lesson snapshot, 25 articles and account gate remain intact.
DNS, Nginx and GitHub Actions configuration are unchanged.

[Release evidence](site-release-2026-10-25-guide.json),
[browser proof](screenshots/site-guide-2026-10-25.png).

## Academy review, five Rust guides and complete sitemaps — 20 October 2026

The manual release is `localhost/crabrix-web-site:academy-blog-20261020-r4`
(image `9eb52549e119626e61189ff3eb83f3bf9dda2a588be14749fb8da631626aa69f`),
from `/srv/apps/crabrix-site/releases/20261020-academy-blog/site`.
It uses the existing loopback port 3212, account mount, resource limits and
security options. Consistent account backups completed before activation.
The pre-task production server is retained as
`crabrix-web-site-before-academy-blog-20261020` for rollback. Task-created
intermediate containers and images are removed after the final checks;
previous application sources, native screenshots and branches are preserved.

The five new articles have separate editorial dates of 16–20 October and
1,551–1,685 paragraph words each. They cover pattern matching, HashMap reports,
checked arithmetic, trait dispatch and buffered text input. Each has two
original built-in ImageGen images, including an analytical infographic,
highlighted code, official Rust sources, linked contents and related guides.
All ten earlier article objects are unchanged. All eleven complete new blog
programs compiled and ran. [Asset metadata](blog-assets-2026-10-20.json) and
[exact prompts](blog-image-prompts-2026-10-20.md) retain the selected originals.

The XML sitemap includes 774 canonical URLs: 742 lessons, seven courses, 15
articles and ten general pages. It also lists 30 public blog images. A new
linked HTML sitemap provides access to every lesson and article. Dotted
Algorithm Atlas lesson IDs now use the framework's actual final URL without a
trailing slash; 600 unnecessary sitemap redirects and their canonical mismatch
are removed. Descriptions are unique, readable and free of Markdown delimiters.
Lesson metadata includes recorded editorial changes, course context and the
existing registration restriction; guest previews and private media protection
are retained. Robots references the XML sitemap and account routes stay noindex.

Ten lessons were corrected in the shared authored curriculum and three teaching
images were replaced. Website snapshot `e0f3ead2a98e4fb8e08118ce27632a15516adc70`
matches the signed Basics 1.0.6, Systems 1.0.5 and Interview 1.0.6 content
offered through native catalog sequence 13. See the
[Academy review](academy-review-2026-10-20.md) for the exact changes, native
verifier results and the compilation probe's limits.

Responsive WebP delivery copies preserve the original PNGs. All 30 full-size
copies total 5.57 MB versus 57.05 MB for the originals; 640px card copies total
1.50 MB. The browser uses `picture`, explicit dimensions, descriptive article
alt text and deferred secondary images. These are byte-size savings, not a
claimed performance-score measurement. [Delivery inventory](blog-image-delivery-2026-10-20.json)
records all 60 generated derivatives and their source hashes.

Eleven site tests, TypeScript checking and the production build passed. The
prepared artifact tree matched on Mac and Linux. Candidate and public checks
verified article text, metadata, dates, source/related links, original image
hashes and all 60 WebP variants. The public SEO audit covered all 774 final
URLs, including canonical/social metadata, unique titles/H1, structured data,
account noindex and restricted lesson access. Browser checks include actual
WebP selection, fully loaded covers, no horizontal overflow and no console
errors. DNS, Nginx and GitHub Actions configuration are unchanged; Actions
remain disabled in both repositories.

[Release and verification record](site-release-2026-10-20-academy-blog.json).

## Five original Rust guides — 18 October 2026

The manually published release is `localhost/crabrix-web-site:blog-20261018-r2`,
from `/srv/apps/crabrix-site/releases/20261018-blog/final-r2`. It serves the
existing loopback port 3212 and preserves the persistent account directory,
resource limits, security options and private Academy access checks. The
preceding server is retained as `crabrix-web-site-before-blog-20261018`.

The Blog now contains ten articles. Five new original guides cover iterators,
UTF-8 strings, test boundaries, Cargo features and enum state machines. Their
editorial dates are 12, 13, 15, 16 and 18 October, distributed between the previous
latest article on 10 October and this update. Each contains 2,122–2,151 paragraph
words, averaging 2,137 versus the previous average of 1,642.4. The previous five
articles retain their text and dates. Each new guide has two distinct built-in
ImageGen illustrations, including an explanatory infographic; two first-pass
diagrams were corrected before publication. Selected assets, prompts and hashes
are recorded in [the asset manifest](blog-assets-2026-10-18.json) and
[the exact prompt set](blog-image-prompts-2026-10-18.md).

Article pages include primary-source links, highlighted Rust, linked contents,
related guides, word counts in BlogPosting data, and explicit image dimensions.
The Blog index has ItemList data. Seven automated site tests, TypeScript checking
and the production build passed. Nine standalone Rust examples, a library unit
test, its doctest and both Cargo feature configurations compiled and ran with
Rust 1.99. The local and Linux candidate checks covered all 768 sitemap routes;
public HTTPS checks then verified the complete text of all five new guides,
metadata, dates, related/source links and all ten image hashes. The full public
SEO audit covered all 768 routes, account noindex, guest previews and private
media denial. Native screenshots and the 742-lesson curriculum were preserved.

A consistent restricted account backup completed before activation. Deployment
was manual on Hetzner; GitHub Actions remain disabled. See the
[release and verification record](site-release-2026-10-18-blog.json).

## SEO, product pages and current screenshots — 16 October 2026

The public service runs `localhost/crabrix-web-site:seo-111-20261016-r2`
(image `69d84aa07b9f2e8847c2f61959715c22d74e3245f6d9a53008def225dfa5086f`).
The existing `crabrix-web-site-1` service is healthy on loopback port 3212.
Its account data mount, resource limits and security options are preserved.
The preceding account-gated container remains stopped for rollback.

The full public HTTPS audit passed for all 763 sitemap pages: unique titles,
one H1, canonical/social metadata, JSON-LD, account noindex, guest previews
and private media denial. All public screenshot aliases matched local hashes.
The final image-only revision replaced the iPad editor with the SDK 27.1
capture showing search, Check and Run; its public hash was checked again.
Ten iPhone and six other iPad images show the updated Academy, and two fresh
Duo laptop images show the editor and real multi-file output. Repository,
site and App Store copies share the same sources. DNS and Nginx were unchanged.
GitHub Actions remain disabled; publication was manual.

[Live deployment evidence](site-release-2026-10-16-seo.json),
[SEO and App Store presentation](seo-2026-10-16.md),
[assets and placements](app-store/asset-upload-2026-10-16-1.1.1.json).

## Native Academy screenshot refresh and build 50 — 11 October 2026

The public service runs `localhost/crabrix-web-site:build50-20261011` from
`/srv/apps/crabrix-site/releases/20261011-build50/site` (image digest
`1bfff364d961a60bcd5a0ce0266d4143186e0825a187aa40f3467c6151dcec12`).
`crabrix-web-site-1` is healthy on the existing loopback port 3212. Sixteen
new iPhone/iPad photos from manual Cloud run 54 show the signed Academy
updates and downloaded examples. The gallery includes the Borrowing lesson
with highlighted Rust and its infographic. The verified SDK 27.1 iPad editor
and two portrait Duo laptop frames remain; the fresh QA frame exclusions are
recorded in the native audit. All 21 public screenshot aliases match the
repository SHA-256 digests, both on candidate port 3213 and public HTTPS.

The local Next.js build and TypeScript stage passed. Candidate/public checks
passed for ten routes, the roughly 30% guest lesson preview, login invitation,
account-to-login redirect, private media denial (401/private no-store), and
raw course JSON denial (404). The seven-course/742-lesson snapshot, Blog,
account schema and synchronized legal pages are preserved. A consistent
restricted account backup completed before switching; the original account
data mount and daily backup timer remain. Resource limits and security options
are preserved. The previous account-gated server is stopped as
`crabrix-web-site-before-build50-20261011` for rollback. The Nginx route,
certificate and DNS were unchanged. GitHub Actions remain disabled.

[Deployment evidence](site-release-2026-10-11-build50.json),
[native build 50](releases/1.1-build50.json),
[Apple screenshot hashes](app-store/asset-upload-2026-10-11-build50.json).

## Synchronized legal pages and native release 44 — 10 October 2026

The public service runs `localhost/crabrix-web-site:legal-20261010-r1` from
`/srv/apps/crabrix-site/releases/20261010-legal-r1/site` (image digest
`f6f232609a9bdf0d5dd80a46275931dbd8c1166b6c936a2e886f7cfeff0f8b32`).
The Podman container `crabrix-web-site-1` is healthy on the same loopback port
3212. Memory, CPU, process limits, no-new-privileges, account data mount and
restart policy are preserved. The previous account-gated server is stopped as
`crabrix-web-site-before-legal-20261010` for rollback. A consistent restricted
SQLite backup was saved before switching; the daily backup timer remains active.

About, Privacy and Terms share generated offline copies with native build 44.
The new `/licenses/` page serves the source/content terms, original component
texts and exact signed-release notice ZIPs. Candidate and public HTTPS checks
passed. The Privacy Choices anchor, account redirect and denial of the raw
course JSON were checked. The Academy content snapshot, account schema and
existing screenshot files are unchanged. New Simulator recaptures are pending
CoreSimulator recovery; this deployment does not claim those pending images.
DNS, certificate, Nginx routing and Cloudflare were not changed or used.

Public browser evidence: [Licenses](screenshots/site-licenses-live-2026-10-10.png).


## Free Academy accounts and three Rust articles — 10 October 2026

The public service now runs the standalone Next.js server, image
`localhost/crabrix-web-site:accounts-blog-20261010-r3` (image digest
`76f82569b002f003cadcca282410c862ceb4d6765394f8eeebe92193eb038ee8`),
from `/srv/apps/crabrix-site/releases/20261010-accounts-blog-r3/site`.
`crabrix-web-site-1` is healthy and binds the existing loopback port 3212.
The preceding server version is stopped as
`crabrix-web-site-before-spacing-20261010` and retains the account access gate.
The prior static container is stopped as
`crabrix-web-site-before-accounts-blog-20261010`. Its static lessons do not
enforce registration; restoring that container would remove the new access gate.

The course snapshot pins `e8345cd0b01e31fbb4fc62073524c32edf279da8`:
seven courses, 742 lessons and 182 private media files. Guest lesson HTML and
RSC contain only a preview of approximately 30%; complete explanations,
exercises, answer reveals and media require a server-checked session.
Registration is free and uses a username, password and one-time recovery code.
Native app CoursePack delivery and build 43 remain unchanged.

Three new articles contain 1,605, 1,555 and 1,601 prose words respectively.
Each has two distinct ImageGen images, including one infographic. The public
article pages, all six image SHA-256 digests, and the Duo laptop, Duo Output and
iPad editor screenshot digests matched the local files. Existing articles remain.
Image prompts and asset hashes are recorded in
[blog-image-prompts-2026-10-10.md](blog-image-prompts-2026-10-10.md) and
[blog-assets-2026-10-10.json](blog-assets-2026-10-10.json).

Five automated tests, TypeScript checking and the production build passed.
The complete browser account lifecycle passed locally, against a Linux candidate
on loopback 3213, and against public HTTPS after switching. These checks include
guest HTML/RSC withholding, media denial, registration, secure cookie flags,
full lesson access, export, logout, login, recovery and deletion. The first
candidate exposed an artifact packaging error: Node's copy operation rewrote
pnpm's relative dependency links to Mac paths. The preparation script now preserves
those links; all 28 traced links were checked before the successful Linux run.
The final mobile review corrected a CSS specificity conflict that removed
the registration callout's horizontal padding. The Linux candidate and public
mobile view were checked for 24px inner padding and no horizontal overflow.

Account data is mounted separately at `/srv/apps/crabrix-site/accounts`.
The daily backup timer is active; the first consistent SQLite backup completed
with exit status 0 and restricted file permissions. Restore tests confirmed that
deleted accounts stay deleted. These backups share the production host.
Nginx now writes separate Crabrix logs with daily rotation and 14-day retention.
Its route, certificate and DNS records were unchanged. Terms and Privacy describe
the website account separately from the native app. See
[site-accounts.md](site-accounts.md) for backup and restore instructions.

Public browser captures: [Blog](screenshots/site-blog-live-2026-10-10.png),
[mobile lesson preview](screenshots/site-lesson-preview-live-2026-10-10.png),
and [mobile registration](screenshots/site-registration-mobile.png).

## Lesson code highlighting and answer reveals — 10 October 2026

The public container runs `localhost/crabrix-web-site:code-audit-20261010`
from `/srv/apps/crabrix-site/releases/20261010-code-audit/site`. The previous
container is stopped as `crabrix-web-site-before-code-audit-20261010` for
rollback. The Next.js export pins course source `aabd294` and generated 763
pages, including 742 lessons. Inline Rust snippets and larger source examples
have distinct colors; Atlas challenge explanations no longer disclose answers
before the reveal. A candidate served the updated lessons on loopback port
3213 before switching port 3212. Public HTTPS returned the Variables,
rustdoc, and Atlas sample lessons with code token classes and infographics.
The site service, Nginx route, and DNS were otherwise unchanged.

## Complete Academy infographics — 10 October 2026

The public container runs `localhost/crabrix-web-site:all-infographics-20261010`
from `/srv/apps/crabrix-site/releases/20261010-all-infographics/site` and the
course snapshot pins source `9414133`. Every one of the 742 lesson pages has an
infographic. The release uses 182 distinct image files: 40 shared Atlas
diagrams and 142 Rust lesson images. The previous site container is stopped
as `crabrix-web-site-before-infographics-20261010` for rollback.

The Next.js export generated all 742 lesson pages. A candidate served Learn,
two formerly unillustrated lessons, and their images on loopback port 3213
before the switch. Public HTTPS then returned the same pages and exact image
hashes. The new container is healthy. Signed CoursePack catalog sequence 8
delivers the same illustrations to installed app builds. DNS and Nginx were
unchanged.

## Inline lesson code and Printing Values diagram — 10 October 2026

The public container runs `localhost/crabrix-web-site:inline-code-20261010`.
It serves the Next.js export pinned to course source `407cdc2`. Rust snippets
in Variables and Printing Values are marked as inline code, and the light-theme
code style has a readable foreground and background. The Printing Values
diagram now maps `name = "Ferris"` to `{name}` and `builds = 4` to `{builds}`;
the illustrated first output line matches the lesson's Rust example.

The candidate on `127.0.0.1:3213` served both lessons and the new PNG before
the switch. Public HTTPS returned 200 for the home page, Learn, both lessons,
and the PNG; the served PNG SHA-256 matched the local export. The previous
container is stopped as `crabrix-web-site-before-inline-20261010` for rollback.
DNS and Nginx were unchanged.

## Build 40 Learn screenshots — 10 October 2026

The public container now runs `localhost/crabrix-web-site:review40-shots-20261010`.
It inherits the prior `atlas-20261009b` image and replaces only four Learn and
My Courses PNGs: iPhone and iPad for each view. The prior container is stopped
as `crabrix-web-site-before-shots40-20261010` for rollback. The candidate
served `/healthz`, `/learn/`, and all four exact screenshot hashes on loopback
port 3213 before the switch. Afterward, public HTTPS returned 200 for the
home page, Learn, Blog, and a Basics lesson; the four served screenshot hashes
matched the checked-in `site/public/screenshots/` files. The local Next.js
export passed `pnpm check` and `pnpm build`. DNS and Nginx were unchanged.

## Complete Rust lesson refresh — 9 October 2026

The public container is `crabrix-web-site-1`, running image
`localhost/crabrix-web-site:rust-20261009` from
`/srv/apps/crabrix-site/releases/20261009-rust-full/site`. The previous
`learn-20261009` container is stopped as `crabrix-web-site-learn-backup`;
the earlier `b36` backup is also retained. Nginx and DNS were not changed.

The site snapshot pins course source commit `0951e4a018eb64b8f30d7fa639fe9cf8e818be37`.
All 142 Rust lessons across Basics, Ownership, Projects, Concurrency, Systems,
and Interview now have at least twice the original explanatory word count,
with an ImageGen diagram in at least every other lesson. The two blog articles
contain 1,841 and 1,783 words respectively (including headings and summaries)
and two generated images each, one an infographic. The Algorithm Atlas course
is included in the export but was not part of this Rust lesson rewrite.

The 763-page static export passed `pnpm check` and `pnpm build`. A candidate
container served `/healthz`, an interview lesson and its diagram, and a Systems
lesson from `127.0.0.1:3213` before the public switch. The live Learn, Basics,
Interview, image, and both Blog URLs then returned HTTP 200. For rollback,
stop `crabrix-web-site-1` and start `crabrix-web-site-learn-backup`; both bind
port `3212` and cannot run simultaneously.

## Learn and Blog refresh — 9 October 2026

That earlier public container ran image
`localhost/crabrix-web-site:learn-20261009` from
`/srv/apps/crabrix-site/releases/20261009-learn-v2/site`. The previous
`b36` container remains stopped as `crabrix-web-site-b36-backup` for rollback.
Nginx and DNS were not changed.

The release pins course source commit `40c14dcd555175694ec0a23c3a0c634d70fb178d`.
All 28 Rust Basics lessons have longer beginner explanations. The website
shows the code before the large diagram and removes generic deeper-reading
filler from those lessons. Both blog articles exceed 1,500 words and contain
two generated images, including one infographic each. The article content is
stored in `site/content/posts.json`.

The static export passed `pnpm check` and `pnpm build`. A candidate container
was checked on `127.0.0.1:3213` before the public switch. `podman compose up`
failed during recreation while the old container was still serving; the old
container was restarted immediately, then the already-created new container
was started after stopping the old one. Both the live `hello-rust` lesson and
the first article returned HTTP 200 with the new text and images. The public
`/healthz` returned 200 and the new container reported healthy after the
rename. For rollback, stop `crabrix-web-site-1` and start the stopped `b36`
backup; both bind the same loopback port, so they cannot run simultaneously.

## Production — 9 October 2026

The public [crabrix.com](https://crabrix.com/) site is the Next.js 16 static
export in `site/`. Its shared navigation and spacing cover the product pages,
Blog, and free Learn section. The export has 763 pages: seven courses and 742
individual lesson pages, plus the rest of the site. The current iPad editor and
iPhone Duo Code and Output screenshots are served from `site/public/screenshots/`.

The isolated `crabrix-web-site-1` container on the GrantTap Hetzner host serves
the export at `127.0.0.1:3212`. Nginx uses
[`site/hetzner/crabrix.com.nginx`](../site/hetzner/crabrix.com.nginx) for the
public HTTPS route. Its certificate is issued by Let's Encrypt and renewed by
Certbot's webroot authenticator; `certbot.timer` and the existing Nginx reload
hook are active. `certbot renew --dry-run --cert-name crabrix.com` succeeded.

The apex DNS A record points to `116.203.99.11` with a five-minute TTL. Only
that record changed from the former Lovable address `185.158.133.1`. DNS
remains unproxied; the existing MX, SPF, DKIM and other verification records
were left intact. The temporary DNS-01 TXT used for initial certificate issue
was removed after webroot renewal was verified. Resolver caches may briefly
retain the previous one-hour A record.

Public HTTPS returned 200 for the home page, Blog, Learn, an individual lesson,
and the refreshed iPad and Duo PNGs. The served screenshot SHA-256 digests
matched the checked-in files. The browser displayed the new menu, Learn and
Blog links, and the updated device gallery. The browser capture of the live
home page is [`docs/screenshots/crabrix-site-live-2026-10-09.png`](screenshots/crabrix-site-live-2026-10-09.png),
with a separate [live device gallery capture](screenshots/crabrix-site-gallery-live-2026-10-09.png).

## Build the current server release locally

Use Node.js 24:

```sh
cd site
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
node scripts/prepare-server-release.mjs ../build/site-server-release
```

The prepared directory contains the standalone Next server, framework assets,
public screenshots/blog images, private curriculum/media and operation scripts.
Do not deploy `site/out/`: its old static lessons do not enforce account access.
The previous deployment notes above describe historical static releases.

## Deploy the isolated server

Transfer the prepared artifact into a fresh release directory on Hetzner.
Build `hetzner/Dockerfile.prebuilt` with a new versioned tag. Mount the persistent
`/srv/apps/crabrix-site/accounts` directory at `/data`, owned by container UID
1000 and never included in a release artifact. The service binds only to
loopback 3212. Use a candidate on 3213 before switching and retain the old
container for rollback. GrantTap remains a separate service.

Test the complete browser account lifecycle, lesson HTML/RSC previews,
authenticated media and public screenshots. Production must set
`SITE_ORIGIN=https://crabrix.com` so Secure session cookies and origin checks
match the public site. Account backup and restore are described in
[site-accounts.md](site-accounts.md).

## Refresh screenshots

`python3 scripts/capture_release_screenshots.py /absolute/path/to/Crabrix.app`
updates Release Simulator captures in `docs/screenshots` and `site`.
`docs/screenshots/duo-laptop.png` was captured separately in Device Hub from
the iPhone Duo laptop posture. Review the captures before publishing.
