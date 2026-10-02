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

On 2 October, the 1.1 site copy and current screenshots were synchronized into
the Lovable project at commit `de69e539aabc192db81440b07b7a004933ba2d51`.
Its `npm run build` preview succeeded and deployment
`fa24ceb3-c046-4b43-a4a0-aee98de3de2b` published to the existing project.
Fresh public HTTPS requests returned 200 for the home, technology, privacy and
support pages on `crabrix.com`. The returned pages showed Academy Examples,
toolchain `crabrix-rust-2026-10-02.1` and the course-hosting privacy copy;
four Academy, Examples, Cyberpunk and iPad screenshot assets also returned
200. That deployment predates the build 12 course-selection and editor changes.
The updated site copy and screenshots are in `site/`; Lovable has not published
them because the project ran out of credits. See the
[build 12 manifest](releases/1.1-build12.json) for the app artifact.

One hosted support FAQ still says “Crabrix 1.0” in a sentence about accounts;
the canonical source page here uses the version-neutral wording. A follow-up
Lovable edit was blocked when the project ran out of credits. This is a copy
discrepancy, not a change in account behavior. The inactive Cloudflare Worker
must not be deployed to bypass Lovable.

**crabrix.com serves Lovable** and is Active and primary in Lovable. The four
principal pages named above were fetched after the 2 October deployment;
the earlier six-page comparison was on 8 September. `www.crabrix.com` still
needs its separate DNS setup.

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

Capture the full iPhone and iPad set from the Release Simulator app. The script
creates and deletes only its own temporary simulators, records fresh install and
existing learner states, and copies the finished images to this site's source:

```bash
python3 scripts/capture_release_screenshots.py \
  /absolute/path/to/Release-iphonesimulator/Crabrix.app
```

The required templates are an iPhone 17 Pro Max named `Crabrix Shots 6.9` and an
iPad Pro 13-inch named `Crabrix Dev iPad`. Inspect each generated frame before
uploading it. The remaining launch arguments select Projects, Learn, Settings,
an installed course, a lesson, or Academy Examples.

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
nothing is stored by a contact-form backend. Page requests and the platform's
visitor analytics still reach its hosting infrastructure, as described above.

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
