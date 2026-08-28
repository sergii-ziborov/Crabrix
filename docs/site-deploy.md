# Crabrix site

A single self-contained landing page. No build step, no dependencies, no JavaScript.

```
site/
  index.html          the whole page, styles inlined
  screenshots/*.png   captured from the simulator
```

## Deploy

Cloudflare Pages, from this directory:

```bash
npx wrangler pages deploy site --project-name crabrix
```

Or as a Worker with static assets, with a `wrangler.toml` pointing `assets.directory`
at `site/`.

## Refreshing the screenshots

The app accepts launch arguments so a given tab can be captured directly:

```bash
xcrun simctl launch <device> com.sergiiziborov.Crabrix -CrabrixTab learn
xcrun simctl launch <device> com.sergiiziborov.Crabrix -CrabrixTab projects -CrabrixLibrary
xcrun simctl io <device> screenshot site/screenshots/iphone-learn.png
```

Valid tabs are `projects`, `build`, `learn`, and `settings`. Adding `-CrabrixLibrary`
opens the project library.

## Email routing

`support@crabrix.com` is published on the site, in the app (Settings → About
Crabrix), and in the App Store listing, so it has to deliver. Cloudflare Email
Routing handles it on the `crabrix.com` zone:

| Rule | Destination |
| --- | --- |
| `support@crabrix.com` | the verified personal inbox |
| catch-all | the same inbox |

The catch-all is there so a message to any other address at the domain — a typo,
or an old address on a screenshot — is forwarded rather than bounced.

Routing added the records it needs to the zone: three `MX` entries pointing at
`route1/2/3.mx.cloudflare.net`, an SPF `TXT` at the apex, and a DKIM `TXT` at
`cf2024-1._domainkey`. They coexist with the Worker's custom-domain record,
because MX and TXT do not collide with the A/AAAA record serving the site.

Inspect or change it with the Email Routing API on the zone, or in the dashboard
under **Email → Email Routing**. Forwarding is receive-only: nothing sends mail
as `@crabrix.com`, which is why the DKIM record is present but unused.
