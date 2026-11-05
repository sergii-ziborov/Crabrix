# Website documentation and product capture refresh — 5 November 2026

## Scope

Refresh the home page, Guide, Connect AI, About and Technology documentation for
the current browser Playground and the Crabrix 1.1.5 build 128 source baseline.
This is a website publication, not an App Store availability announcement.
Application code, SDK packages, App Review selections and account schemas are
unchanged. Previously published articles remain historical records.

## Capture provenance

Twenty-two new original PNGs are published under `/screenshots/2026-11-05/`.
`site/lib/screenshot-catalog.json` records their native dimensions and capture
surface. Compatibility paths used by existing articles and repository READMEs
receive the same bytes. No image is stretched, drawn over or represented as a
physical-device photograph.

- Ten iPhone learning/editor/settings captures come from the current screenshot
  XCTest. Six iPad learning/editor captures come from the same source version.
- Native screenshots use isolated Simulators and the current signed public
  course corpus acquired through the application. The iPad fixture copies those
  exact public course files from the isolated iPhone Simulator; no lesson text,
  user identity or course progress was fabricated or copied from a real device.
- A fresh iPhone multi-file Run prints `hello from two Rust files` through the
  bundled local compiler. A fresh iPad Debug frame shows the actual String,
  Vec and concrete structure values at a checkpoint.
- Browser Cargo capture prepares `itoa =1.0.15`, moves source into `src/`, and
  performs a real local Run: `Hello from Crabrix: 42`, exit 0. The Debug capture
  shows `Ferris 🦀`, `[1, 2, 42]` and a concrete local `Crab` structure.
- The browser and iPhone shared-selection captures use a named, scripted
  `Demo agent · Crabrix SDK` participant from the released 0.5.0 core. Source and
  UTF-16 selection actually reach the editors. This is an SDK demonstration,
  not a claim that a particular AI model generated the program. Editing does
  not start a compiler. The synthetic rooms were explicitly ended afterwards.
- Native captures identify a source/Simulator build, not a newly uploaded
  TestFlight build. Optimized automated fixtures use the existing
  `CRABRIX_LEGACY_FIXTURES` condition; no native source was modified.

The two Duo inner-display images retain their earlier valid qualification
captures and are labeled accordingly in the galleries and Guide. New inner
display captures were black and were rejected. The Mac was locked, so the
native UI tool could not switch Simulator posture. No simulated resize of a
phone capture was substituted. Earlier specialty captures such as Algorithm
Atlas playback remain where the illustrated controls are still applicable.

## Description corrections

- Guide date and documented baseline: 5 November, 1.1.5 build 128. Website and
  SDK release versions are distinct from installed App Store versions.
- Technology distinguishes native npm/web previews, browser Cargo, native
  libtest/rustfmt/Git, local source Debug, and shared execution permissions.
- Removed obsolete claims that native tests and Git commits/push are absent.
- Browser Cargo requires explicit source preparation, has a bounded library
  profile, and does not widen the manifest-free MCP execution profile. Manual
  browser Cargo results stay local; supported shared job previews never start
  execution on observing participants.
- The capability document records SDK 0.5.0 and its optional remote MCP
  exception: that opted-in service decrypts the chosen room in server memory;
  neither the relay nor remote MCP compiles or executes projects.
- Homepage, About, Technology and AI descriptions, image alt text, modified
  dates and internal Guide links are aligned. Lesson access rules are retained.

## Validation before deployment

- Site suite: 135 passed, zero failed. Production Next build and TypeScript pass.
- Native iPhone screenshot XCTest and aggregate-locals Debug XCTest pass.
- Optimized iPad aggregate-locals Debug XCTest passes. Earlier slow iPad
  screenshot/Debug attempts timed out; those are not reported as passing.
- Browser Cargo/Debug/shared-selection captures verify actual visible output
  and locals, with no captured page errors. Temporary SDK rooms report ended.
- Browser layout: 60 configurations (home, Guide, AI and Technology; 390/820/1440
  CSS pixels; all five themes), no horizontal overflow or duplicate H1. All 12
  gallery images, three enlargement dialogs, navigation and Escape were checked.
  Browser error log is empty.
- HTTP checks: 119 refresh checks plus 13 existing regression checks pass locally,
  including image hashes/dimensions/aliases, canonical and OpenGraph, Guide
  anchors, 816 unique sitemap URLs, SDK archive hash and guest lesson gating.
- Hashes and dimensions of promoted assets are retained in the capture manifest
  beside this record. Deployment and public readback results are recorded in
  `docs/site-deploy.md` after cutover.

Raw test logs, xcresults, candidate build contexts and capture harnesses remain
in the ignored `build/site-refresh-20261105/` directory. Room keys and private
links are excluded from public documentation and deployment assets.


## Publication

The website was switched to `docs-shots-7044c9c` at 2026-11-05T00:05:03Z.
The public HTTPS readback passed all 119 refresh and 13 regression checks.
Its image bytes match the capture manifest. The live browser confirmed current
images on phone/tablet/desktop layouts, with no overflow or console errors.
The account backup and unchanged persistent mount were verified; the independent
remote MCP container was not restarted. The previous website is retained for
rollback. See `docs/site-release-2026-11-05-captures.json` for serving identity.
