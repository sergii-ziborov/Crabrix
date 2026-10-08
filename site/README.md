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

The site runs as its own Hetzner container from `compose.hetzner.yaml` and
`hetzner/Dockerfile`, following the separate-service pattern used by GrantTap.
It binds only to loopback on port 3212. Public access needs a Crabrix server
route and certificate; the current Lovable site and domain records are unchanged.
