# Crabrix website

This directory contains the Next.js 16 website. The same shared header, footer,
spacing, and responsive layout render the product, legal, Blog, and Learn pages.
The build exports static HTML, so the Hetzner service only serves files with
Nginx. It is independent of the running GrantTap compose stack.

```bash
pnpm install --frozen-lockfile
pnpm build
```

The output is `site/out/`. `app/learn` exposes all seven courses and 742 lesson
pages from the pinned snapshot in `content/courses.json`. Refresh that snapshot
from a trusted checkout of the author's course repository with:

```bash
python3 scripts/sync-course-content.py /path/to/crabrix-courses
pnpm build
```

`app/blog` contains two articles. Product and legal copy in the checked-in
top-level HTML files is rendered through `lib/legacy.ts`; the Next layout supplies
their common navigation and spacing. Product captures are in `public/screenshots/`.
The iPad editor capture includes in-file search; the two Duo captures show Code
with its keyboard controls and a completed run in Output. Refresh the Store
captures from the same Release Simulator source before changing those files.

The site runs as its own Hetzner container. The current release serves a
locally built static export from Nginx using `compose.prebuilt.yaml`; source
builds use `compose.hetzner.yaml` and `hetzner/Dockerfile`. It binds only to
loopback on port 3212. Public access needs a Crabrix server
route and certificate; the current Lovable site and domain records are unchanged.

For a prebuilt release, build the static export locally, transfer `out/` with
`hetzner/nginx.conf`, `hetzner/Dockerfile.prebuilt`, and
`compose.prebuilt.yaml` to an isolated release directory on Hetzner, then run:

```bash
podman build -f hetzner/Dockerfile.prebuilt -t localhost/crabrix-web-site:b26 .
podman compose -f compose.prebuilt.yaml up -d
```

Set `CRABRIX_SITE_TAG` for a later image. The compose file binds only to
`127.0.0.1` and does not change the public domain route.
