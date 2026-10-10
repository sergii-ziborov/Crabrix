# Crabrix website deployment

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

## Build locally

```bash
cd site
pnpm install --frozen-lockfile
pnpm check
pnpm build
```

The static export is written to `site/out/`. Product and legal copy comes from
the checked-in HTML documents, with common navigation supplied by the Next
layout. `site/content/courses.json` is a pinned snapshot from the course
repository; `site/README.md` explains how to refresh it.

## Deploy the isolated Hetzner service

For a prebuilt release, transfer `site/out/` with `hetzner/nginx.conf`,
`hetzner/Dockerfile.prebuilt`, and `compose.prebuilt.yaml` to an isolated release
directory on Hetzner. Build and start the container there:

```bash
podman build -f hetzner/Dockerfile.prebuilt -t localhost/crabrix-web-site:b36 .
CRABRIX_SITE_TAG=b36 podman compose -f compose.prebuilt.yaml up -d
curl --fail http://127.0.0.1:3212/healthz
curl --fail https://crabrix.com/learn/
```

Choose a new image tag for each later release. The container stays bound to
loopback; Nginx owns the public route. The GrantTap compose project is separate.

## Refresh screenshots

`python3 scripts/capture_release_screenshots.py /absolute/path/to/Crabrix.app`
updates Release Simulator captures in `docs/screenshots` and `site`.
`docs/screenshots/duo-laptop.png` was captured separately in Device Hub from
the iPhone Duo laptop posture. Review the captures before publishing.
