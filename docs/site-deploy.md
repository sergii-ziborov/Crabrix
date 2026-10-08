# Crabrix website deployment

## Current state

The public `crabrix.com` site still serves the existing Lovable deployment. The
new site in `site/` is a Next.js 16 static export. It has one shared navigation,
responsive spacing, Blog, all seven free Learn courses and 742 lesson pages,
and screenshots captured from the current app. It has passed a local build and
link check, but has not replaced the public site.

The prepared Hetzner service is independent of GrantTap. It listens on
`127.0.0.1:3212` by default and does not create a public route or alter domain
records. No public hosting switch is part of this repository change.

## Build locally

```bash
cd site
pnpm install --frozen-lockfile
pnpm check
pnpm build
```

The static site is written to `site/out/`. Next.js renders the existing product
and legal copy from the checked-in HTML documents while its shared layout
supplies the common header and footer. `site/content/courses.json` is a pinned
snapshot from the course repository; `site/README.md` explains how to refresh
it.

## Prepare the isolated Hetzner service

On the server, after checking out the desired commit into a separate Crabrix
directory:

```bash
cd site
docker compose -f compose.hetzner.yaml config
docker compose -f compose.hetzner.yaml build
docker compose -f compose.hetzner.yaml up -d
curl --fail http://127.0.0.1:3212/healthz
curl --fail http://127.0.0.1:3212/learn/
```

The server's existing GrantTap compose project and routes do not need changes.
A separate public HTTPS route for Crabrix can be added only when its destination
and domain routing have been agreed. Until then, Lovable remains the public
site.

## Screenshots

`python3 scripts/capture_release_screenshots.py /absolute/path/to/Crabrix.app`
refreshes the Release Simulator images in `docs/screenshots` and `site`.
`docs/screenshots/duo-laptop.png` was captured separately in Device Hub from
the iPhone Duo laptop posture. Inspect images before committing or publishing.
