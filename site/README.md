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
deletion, backup restoration, all 742 lesson previews and the three new blog
articles. `scripts/test-account-flow.mjs` runs the browser account lifecycle
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

`content/posts.json` contains five articles. The three added on 10 October 2026
have 1,605, 1,555 and 1,601 prose words, official Rust source links, highlighted
Rust examples and two ImageGen images each. Each pair contains an infographic.
Final assets and hashes are recorded in `../docs/blog-assets-2026-10-10.json`;
the built-in ImageGen prompts are in `../docs/blog-image-prompts-2026-10-10.md`.
Product and legal copy remains in the top-level HTML files rendered through
`lib/legacy.ts`.

Current product screenshots in `public/screenshots/`, `screenshots/` and
`../docs/screenshots/` agree byte-for-byte where a shared filename exists.
Sixteen iPhone/iPad frames were refreshed after the real signed course updates
in manual Xcode Cloud run 54. The gallery and root README include the current
Borrowing lesson infographic and highlighted code. The verified SDK 27.1
iPad editor and two Duo portrait laptop captures remain; capture provenance
and Apple MD5 readback are in
`../docs/app-store/asset-upload-2026-10-11-build50.json`.
The iPad editor shows in-file search. Duo Code and Output retain their tested
fold layout. iPhone/iPad editor captures omit the Duo-only keyboard-dismiss
button from the Code/Terminal tab row. Native build 50 is selected for App Review; this website change does not alter its offline account-free behaviour.

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
