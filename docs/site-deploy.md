# Crabrix website deployment

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
