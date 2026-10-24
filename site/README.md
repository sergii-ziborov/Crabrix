# Crabrix website

The Next.js 16 website uses a shared header, footer and responsive spacing for
product pages, Blog, Learn, registration and Account. It now runs as a **Node.js
server**, independently of GrantTap on Hetzner. Static export is no longer a
production deployment option because Academy access is checked on the server.

## Development and checks

Use Node.js 24. Copy `.env.example` to `.env.local` for localhost, then:

```sh
pnpm install --frozen-lockfile
pnpm dev
pnpm test
pnpm check
pnpm build
```

`pnpm test` covers credential/session handling, recovery rotation, account
deletion, backup restoration, all 742 lesson previews and the blog content requirements
(length, publication dates, unique prose and image assets). `scripts/test-account-flow.mjs` runs the browser account lifecycle
against a running site and deletes its isolated test account. It needs an
installed Chrome and the `PLAYWRIGHT_MODULE` path or a local Playwright install.
Set `QA_SITE_ORIGIN` for a candidate or live HTTPS check. `QA_CAPTURE=1` saves
registration captures without credentials or recovery codes.

## Content and synchronization

`content/courses.json` is the pinned 742-lesson curriculum from the course
repository, including all 142 Rust lessons and 600 Algorithm Atlas steps.
Refresh both lesson JSON and the 182 private media files with:

```sh
python3 scripts/sync-course-content.py /path/to/crabrix-courses
pnpm build
```

Lesson sources and images live under `content/`, never `public/`. Guests receive
approximately 30% of the lesson's visible word count and an invitation to create
a free account. Exercises, answers and the rest of the lesson are absent from
both guest HTML and React Server Component responses. `/learn-media/` checks
the same session. Authenticated responses use private/no-store caching.
Google receives the same previews as other logged-out visitors. Registration
content has matching JSON-LD markup; account pages are excluded from indexing.

This is website access control, not copy protection: the separate app course
repository and signed release archives remain public so existing native builds
can download and update their courses. Changing that delivery model requires
an app release and a separate migration.

`content/posts.json` contains 25 articles. The five added on 23 October occupy
previously unoccupied editorial dates of 11, 14, 21, 22 and 23 October. Two
practical guides cover generated Cargo source and memoization; three news
analyses cover Rust infrastructure, the announced Rust 1.100 i686 Windows
host-tool transition, and rustup 1.29.2. News event dates are stated separately
and precede the articles. Each has 2,307–2,363 paragraph words, exceeding the
previous longest article (2,151), three related guides, primary sources, and
two original built-in ImageGen images including an analytical infographic.
Five standalone Rust programs and nine Cargo build-script scenarios passed;
Windows cross-linking and toolchain-update commands were not executed on the
Mac. See `../docs/blog-assets-2026-10-23.json`,
`../docs/blog-code-verification-2026-10-23.json` and
`../docs/blog-image-prompts-2026-10-23.md`. All fifteen earlier article objects
are unchanged.

The five added on 20 October have
distinct editorial dates of 16–20 October and 1,551–1,685 paragraph words each.
They cover exhaustive matching, HashMap reports, checked arithmetic, trait
dispatch and buffered text input. Each has two original ImageGen assets,
including an analytical infographic, and primary documentation links. All
eleven complete Rust programs from these guides compiled and ran. Their
manifest and exact prompts are in `../docs/blog-assets-2026-10-20.json` and
`../docs/blog-image-prompts-2026-10-20.md`. The ten earlier article objects are
unchanged.

The five added on 18 October have
editorial publication dates of 12, 13, 15, 16 and 18 October, between the previous
last publication (10 October) and this update. They contain 2,122–2,151 paragraph
words each: a 2,137-word average versus the previous 1,642.4-word average. Each
article has a distinct ImageGen cover and explanatory infographic, primary Rust
source links, highlighted Rust examples and three related guides. Dates, word
counts, dimensions, captions and image hashes are in
`../docs/blog-assets-2026-10-18.json`; exact built-in generation and correction
prompts are in `../docs/blog-image-prompts-2026-10-18.md`. The original five
articles retain their text and publication dates.

Blog pages include canonical/social metadata, BlogPosting word counts,
BreadcrumbList data, an index ItemList, linked contents, inline code styling and
related article links. Image dimensions reserve layout space; the first article
image loads eagerly and later images load lazily. Shell and TOML blocks are
rendered as their own languages rather than Rust. New standalone examples, the
public-library unit test and doctest, and both local Cargo feature configurations
were compiled and run with Rust 1.99. Desktop-only commands are labeled.
`scripts/prepare-blog-images.py` produces responsive WebP delivery copies while
retaining every original generated PNG. `BlogImage` serves a 640px card or
full-size WebP through `picture`, with PNG fallback, explicit dimensions and
meaningful article alt text. The 40 full-size copies total 8.27 MB versus
77.48 MB for their PNG sources (89.3% less); card copies total 2.21 MB (97.1%
less). These are encoded-byte comparisons, not a claimed page-speed score.
See `../docs/blog-image-delivery-2026-10-23.json`. After adding images, run the
encoder with Python/Pillow before the normal site checks and build.
Product and legal copy remains in the top-level HTML files rendered through
`lib/legacy.ts`.

Current product screenshots in `public/screenshots/`, `screenshots/` and
`../docs/screenshots/` agree byte-for-byte where a shared filename exists.
Ten iPhone and six iPad frames were refreshed after the real signed course
updates in manual Xcode Cloud run 62. The iPad editor comes from the final
SDK 27.1 product in run 70 and shows search, Check and Run. Two fresh native
Duo laptop captures show the editor and actual multi-file program output.
Capture provenance, all 19 unique image hashes, and the main/Academy/Compiler
page placements are in
`../docs/app-store/asset-upload-2026-10-16-1.1.1.json`.
iPhone/iPad omit the Duo-only keyboard-dismiss control from the coding tab row.
The native app's offline reading and compilation do not require a website account.

The current curriculum snapshot pins authored course commit
`e0f3ead2a98e4fb8e08118ce27632a15516adc70`. Ten corrections address UTF-8 units
and slicing, integer casts and overflow policy, missing sample bindings, a
deterministic HashMap example, Rust 2024 FFI declarations, buffered output
guarantees and borrowed versus owning trait objects. The same lesson
bytes and replacement diagrams are published as signed Basics 1.0.6, Systems
1.0.5 and Interview 1.0.6 packs in catalog sequence 13. See
`../docs/academy-review-2026-10-20.md` for the review and verification scope.
The recorded snapshot revision identifies the authored lesson changes.
`fac40d1a3781c7017b246cf62b04c20381d94e72` also commits the generated unit
digests already included in the snapshot and published pack. All course, unit
and lesson objects match that committed corpus exactly.

## Search metadata

The 23 October release pins Next.js 16.4.2 after the 16.4.0 build surfaced
the upstream October security advisories. The lockfile change is limited to
Next.js and its version-matched packages; sharp remains at the patched 0.35.5.
The post-update dependency audit reports zero known advisories. Account tests,
the full sitemap crawl, TypeScript and production build cover the patched
runtime. See the [official security update](https://nextjs.org/blog/nextjs-security-update-october-14-2026).

Public routes share canonical HTTPS addresses matching their final served URL,
individual
titles/descriptions, Open Graph and Twitter cards. BlogPosting, Course,
Article and BreadcrumbList data describe the actual visible content. Restricted
lesson markup identifies the account requirement; it does not expose the full
lesson to crawlers. Account routes stay noindex and outside the sitemap.
Ordinary pages end in a slash; dotted Atlas lesson IDs follow Next's
extension-like URL rule and omit it, avoiding a redirect from sitemap URLs.

The [HTML sitemap](https://crabrix.com/sitemap/) lists all seven courses, 742
lessons and 25 articles. `/sitemap.xml` contains 785 canonical URLs and 40 public
blog image URLs. Known editorial modification dates are retained for the ten
corrected lessons and three courses; build time does not invent modification
dates. Private lesson media and account routes are excluded. `sitemap.xml` at
the site root is a synchronized legacy snapshot; Next's metadata route serves
the production XML. `lib/lesson-seo.ts` supplies readable, unique descriptions
without Markdown backticks and recorded editorial change dates.

The latest live audit checked all 785 sitemap pages, unique titles, one H1 per
page, canonical/social metadata, structured data, previews and private media
denial. All ten new public image hashes matched the selected repository assets.
Twelve site tests, TypeScript checking and the production build passed.
See `../docs/site-release-2026-10-23-blog.json` and the earlier product-page
audit in `../docs/seo-2026-10-16.md`.

## Accounts and operation

Accounts use a username and password; no email or payment information is
required. Password hashes use scrypt (N=131072, r=8, p=1), unique salts and
constant-time comparison. Recovery codes and session tokens are randomly
generated and stored only as hashes. Production cookies are Secure, HttpOnly,
SameSite=Lax and expire after 30 days. Server Actions validate the origin and
persist short-lived rate limits. Account includes export, password change and
password-confirmed deletion. Terms acceptance records the policy version.

Configure `SITE_ORIGIN=https://crabrix.com` and
`AUTH_DB_PATH=/data/accounts.sqlite`. The persistent account directory is
`/srv/apps/crabrix-site/accounts`, owned by container UID 1000 with restricted
permissions. Never put it in a release archive or Git. Backups retain seven days;
deletion fingerprints retain at most eight days. Restore only with the site
stopped; the restore script reapplies deletions and revokes all sessions.
See `../docs/site-accounts.md` for operation and recovery.

## Production release

Build locally, then prepare a server artifact:

```sh
pnpm build
node scripts/prepare-server-release.mjs ../build/site-server-release
```

Transfer that prepared directory to an isolated Hetzner release directory.
`hetzner/Dockerfile.prebuilt` packages the standalone server, static framework
assets, public blog/screenshots and backup script. Source builds use
`hetzner/Dockerfile`. Both bind only to loopback through Podman. The public
Nginx route stays on port 3212 with the existing Certbot certificate. Test on
3213 before switching; retain the previous container for rollback. No GitHub
CI/CD is used. Deployment evidence is in `../docs/site-deploy.md`.

## Shared legal documents

The public [About](https://crabrix.com/about/), [Privacy](https://crabrix.com/privacy/),
[Terms](https://crabrix.com/terms/) and [Licenses](https://crabrix.com/licenses/)
pages share the same authored terms as the native app and GitHub. The original
HTML main bodies are canonical for About/Privacy/Terms. Application source
rights come from the repository LICENSE; educational rights come from
CONTENT-LICENSE.md, kept equal to crabrix-courses. Run
`python3 scripts/sync_legal_documents.py` at the app repository root after an
edit and `--check` before release. The export includes offline Swift resources,
GitHub-readable Markdown, website data, original third-party text files and
byte-identical toolchain notice archives. Third-party copyrights and licenses
are preserved. Account data is not part of any release artifact.

The October 24 catalog adds five distinct long-form articles (2,600–2,726 prose words), ten ImageGen originals and optimized WebP deliveries. `/guide/` documents real product captures, offline packages, build stages and local HTML/CSS/JavaScript preview boundaries. The application legal bundle and this site share the canonical About, Privacy, Terms and license source.
