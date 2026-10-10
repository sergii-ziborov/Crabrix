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

The current snapshot pins course source `9414133`: all 742 Academy lessons
have an infographic. Atlas reuses its pattern-specific diagrams across all
600 steps, and the 70 Rust lessons that lacked an illustration have individual
code-to-rule diagrams. Rust Basics 1.0.4 retains the corrected Printing Values
diagram and marks inline Rust expressions so they stand out in both light and
dark themes. Both Blog articles exceed
1,500 words and contain two generated images, including an infographic.

`content/posts.json` contains two articles of more than 1,500 words each and
the image references rendered by `app/blog`. Product and legal copy in the checked-in
top-level HTML files is rendered through `lib/legacy.ts`; the Next layout supplies
their common navigation and spacing. Product captures are in `public/screenshots/`.
The iPad editor capture includes in-file search. Current iPhone and iPad editor
captures omit Duo's keyboard-dismiss button from the Code/Terminal tab row; the
two Duo captures show Code with its keyboard controls and a completed run in
Output. Refresh the Store
captures from the same Release Simulator source before changing those files.

The site runs as its own Hetzner container. The current release serves a
locally built static export from Nginx using `compose.prebuilt.yaml`; source
builds use `compose.hetzner.yaml` and `hetzner/Dockerfile`. It binds only to
loopback on port 3212. The public `crabrix.com` HTTPS route is handled by
`hetzner/crabrix.com.nginx`; the certificate renews through Certbot webroot.
Deployment evidence and DNS details are in `../docs/site-deploy.md`.

For a prebuilt release, build the static export locally, transfer `out/` with
`hetzner/nginx.conf`, `hetzner/Dockerfile.prebuilt`, and
`compose.prebuilt.yaml` to an isolated release directory on Hetzner, then build
a versioned image:

```bash
podman build -f hetzner/Dockerfile.prebuilt -t localhost/crabrix-web-site:rust-20261009 .
```

Test a candidate on port 3213 before moving the public port 3212 to the new
container; keep the previous container stopped for rollback. The compose file
binds only to `127.0.0.1` and does not change the public domain route. The
observed switch and rollback target are recorded in `../docs/site-deploy.md`.
