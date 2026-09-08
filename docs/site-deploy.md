# Crabrix site

Six self-contained pages. Each one carries its own styles, and the copy here is
the source of truth: the hosted site is built from these files rather than
edited in place.

```
site/
  index.html          the landing page, styles inlined
  about.html          what it is, how it works, what it cannot do
  technology.html     the pinned toolchain, the limits, the gaps
  privacy.html        what stays on device and what leaves it
  terms.html          licence terms for the app
  support.html        contact and the common questions
  leaderboard.html    a notice that 1.0 has no board
  404.html
  screenshots/*.png   captured from the simulator
```

## Deploy

The Lovable deployment serves these pages from a project that
imports each file's markup verbatim rather than re-typing it:

- project: https://lovable.dev/projects/a22788fb-a840-487d-8a0e-e2b741b50a40
- published: https://crabrix.lovable.app

Changing a page means editing it here, uploading it to that project, and asking
it to update the matching file in `src/pages/html/`, preserving its existing
image optimization, canonical metadata and presentation fixes. Compare visible
copy after normalizing HTML entities and whitespace; full-file byte equality is
not expected across the two renderers. Product and legal wording must match.

As verified on 8 September 2026, **crabrix.com serves Lovable** and is Active
and primary in Lovable. All six principal HTTPS pages were checked against the
canonical copy. `www.crabrix.com` still needs its separate DNS setup.

Cloudflare retains domain registration and authoritative DNS for now; the owner
plans to transfer registration later. Hosting has moved independently of that.
The old `crabrix-site` Worker is retained but inactive: both custom-domain
bindings were detached, no zone routes remain, workers.dev and preview URLs are
disabled, and there are no scheduled triggers. `wrangler.toml` also disables
public routing so a future deploy will not reclaim these domains.

Lovable promotional branding is disabled and absent from the rendered site.
Visitor analytics is still enabled at the platform level (`/~flock.js` observed);
turn off General → Publishing → Visitor analytics and republish before claiming
that the hosted website has no analytics. This does not change the native app's
no-analytics implementation. See `release-evidence/site-migration-2026-09-08/`.

## Refreshing the screenshots

The app accepts launch arguments so a given tab can be captured directly:

```bash
xcrun simctl launch <device> com.sergiiziborov.Crabrix -CrabrixTab learn
xcrun simctl launch <device> com.sergiiziborov.Crabrix -CrabrixTab projects -CrabrixLibrary
xcrun simctl io <device> screenshot site/screenshots/iphone-learn.png
```

Valid tabs are `projects`, `build`, `learn`, and `settings`. Adding `-CrabrixLibrary`
opens the project library.

## What the pages carry now

- **Light and dark**, following `prefers-color-scheme` with no toggle: the dark
  values are the default and a `@media (prefers-color-scheme: light)` block in
  each page's own `<style>` redefines the same variables.
- **A canonical link per page**, plus `robots.txt` and `sitemap.xml`.
- **No external font CDN or image host in the source pages.** Platform-injected
  visitor analytics is a separate hosting setting; see its current status above.
- The favicon is a **percent-encoded** SVG data URI. It must stay encoded: with
  raw `<` and `>` in the attribute, the parser closes `<link>` at the first `>`
  inside the SVG and the rest of it — a crab emoji and a stray `">` — renders in
  the corner of every page. That shipped for a while before anyone noticed.
- On Lovable only, the screenshots are additionally served as AVIF and WebP
  through `<picture>`, with the PNGs as the fallback: 4.4 MB of images becomes
  about 80 KB. The copies here keep the PNGs, because the smaller formats are
  generated on that side.

## Reaching support

There is no longer an address on the page. The support page carries a form and
the other pages carry a button; both decode the destination at click time and
open a draft in the visitor's own mail app. Nothing is posted anywhere and
nothing is stored — the site has no backend, which is what lets the privacy
page say the site calls no third party.

The destination is the developer's own inbox, held in one place in the app
(`CrabrixLinks.supportEmail`) and base64 in the pages' `data-mail` attributes.
Neither is a secret; both exist so the address is not published as plain text
for a harvester to lift.

`support@crabrix.com` on Cloudflare Email Routing still exists while the zone
does, and mail sent there still arrives. It is simply no longer the address the
product points at.

The catch-all is there so a message to any other address at the domain — a typo,
or an old address on a screenshot — is forwarded rather than bounced.

Routing added the records it needs to the zone: three `MX` entries pointing at
`route1/2/3.mx.cloudflare.net`, an SPF `TXT` at the apex, and a DKIM `TXT` at
`cf2024-1._domainkey`. They coexist with the Worker's custom-domain record,
because MX and TXT do not collide with the A/AAAA record serving the site.

Inspect or change it with the Email Routing API on the zone, or in the dashboard
under **Email → Email Routing**. Forwarding is receive-only: nothing sends mail
as `@crabrix.com`, which is why the DKIM record is present but unused.
