> Current status — 9 September 2026: Apple rejected **1.0 (6)** under
> guideline 2.1 pending additional information and a physical-device recording
> (review message provided by the owner). Build **1.0 (7)** is being prepared
> with three device QA fixes. No new review submission has been made.
> See [device QA fixes](device-qa-2026-09-09.md).
> The entries below are historical.

> Current status — 8 September 2026, 16:37: Build **1.0 (6)** resubmitted and
> **Waiting for Review**. Xcode Cloud build/archive succeeded using Xcode
> 26.6 (17F113), macOS 26.6.2 (25G83), source commit `0457171`.
> TestFlight binary state: **Validated**. Manual release remains selected.
> See [build 6 evidence](../../release-evidence/1.0/6/cloud-build.json).
> All updates below describe earlier stages.

> Latest update — 8 September 2026: Apple rejected build 1.0 (5) with
> ITMS-90111 (unsupported SDK or Xcode version). Build 6 is in preparation and
> has not been uploaded. Xcode Cloud setup awaits GitHub authentication and
> repository connection; Apple account authentication has completed.
> The earlier Waiting for Review observation below is historical.

> Earlier update — 8 September 2026: Build 1.0 (5) uploaded successfully through Xcode
> Organizer after build 4 failed bundle-structure validation. Final verification:
> 398 fast tests + 21 compiler gates passed. The new archive includes corrected
> privacy reasons and a bundled compressed WASI sysroot. Submitted to Apple on
> 8 September: **Waiting for Review**, with manual release after approval.
> Review Notes were restored and all 3882 characters verified after server reload;
> see [the current audit](final-audit-2026-09-08.md).
> The build 3 notes below are historical.

# Submission status — 1.0 (3)

Where the submission actually stands, written so that nothing here needs to be
taken on trust: every claim names the file, the command, or the person it came
from. Status is **BLOCKED on two items**, both of which need the owner and
neither of which is a code change.

Candidate: `1.0 (3)`, branch `release/1.0-app-store`, archive
`build/Crabrix-1.0-3.xcarchive`, evidence `release-evidence/1.0/3/`.

## The two blockers

### 1. No App Store artifact yet — needs an Xcode account session

`xcodebuild -exportArchive` with `method: app-store-connect` fails on this Mac:

```
error: exportArchive No Accounts
error: exportArchive No signing certificate "iOS Distribution" found
```

The distribution certificate is Apple-managed, so the export needs an
authenticated Xcode account; `~/Library/MobileDevice/Provisioning Profiles` is
also empty. The same export succeeded for build 2, so the assets exist at
Apple's end — what is missing is the session.

**Owner:** open Xcode → Settings → Accounts and confirm the Apple ID is signed
in, then either

```bash
xcodebuild -exportArchive -archivePath build/Crabrix-1.0-3.xcarchive \
  -exportOptionsPlist <options> -exportPath build/export3 -allowProvisioningUpdates
```

or, more reliably, Window → Organizer → the 1.0 (3) archive → Distribute App →
App Store Connect. Export produces the artifact; **uploading is a separate
decision and has not been made here.**

### 2. The App Review contact needs a phone number

Everything else on the version page is saved. App Store Connect requires a
phone number for the review contact, and it silently discards the entire App
Review Information block — contact, notes, and the sign-in checkbox — when the
field is empty. Fill it in and the notes below go in with it.

### 3. Report a problem has never run on the phone

The owner's device testing predates the feature, and the build containing it
could not be installed on 2026-09-06 — the iPhone was not reachable on the
network. Everything else in this candidate has either been on the device
(the editor rework was installed on 2026-09-05) or is unchanged from what was.

**Owner, about two minutes:** Settings → Help & problems → Report a problem;
type a line, watch the mail draft open with the right subject and body, switch
the environment toggle off and confirm the four detail lines disappear, press
Copy, then cancel the draft and confirm the app never claims anything was sent.

## What is closed

| Gate | State | Where to check |
| --- | --- | --- |
| Support feature and a privacy policy that matches it | done | `site/privacy.html` "Optional support correspondence"; `ProblemReportTests` |
| App Privacy answers reasoned rather than assumed | done, owner to confirm | `docs/app-store/listing.md` → App Privacy answers |
| Metadata within limits and not overclaiming | done | table below; `listing.md` |
| Production toolchain | done | Xcode 26.6 (17F113), Swift 6.3.3 — archive and 390-test suite both |
| Programming-environment evidence | done | `release-evidence/1.0/3/programming-environment/area-measurement.json` |
| Screenshots match the shipping interface | done | `docs/app-store/screenshots/`, recaptured from this tree |
| Provenance from source to artifact | partial | `release-evidence/1.0/3/checksums.json` — the IPA hash waits on blocker 1 |
| The URLs App Store Connect points at | done | all six pages answer 200, checked against the live site |
| App Store Connect record | done | app created: `Crabrix: Rust Compiler`, Apple ID 6809502653 |
| Price and availability | done | $9.99 base USD, 175 storefronts, manual release after approval |
| Metadata, screenshots, age rating, App Privacy | done | entered and saved; privacy published as Data Not Collected |
| App Review contact | blocked | Apple requires a phone number; the whole block refuses to save without it |
| App Store Connect payment setup | owner-done | Paid Apps Agreement, bank account, W-8BEN and the DSA declaration were all already active |

### Metadata lengths, counted rather than estimated

| Field | Characters | Bytes | Limit |
| --- | ---: | ---: | ---: |
| Name | 22 | 22 | 30 |
| Subtitle | 28 | 28 | 30 |
| Promotional text | 164 | 164 | 170 |
| Keywords | 96 | 96 | 100 |
| Description | 3805 | 3855 | 4000 |
| What's New | 551 | 551 | 4000 |
| Review notes | 3968 | **3986** | 4000 |

Review notes sit 14 bytes under the cap. Adding a sentence in App Store Connect
will overflow it — edit `listing.md` and re-count instead of typing into the
field.

## The site was two weeks behind

`crabrix.com/privacy` was still serving the 28 August text, and
`crabrix.com/technology` — the Marketing URL in the listing — answered **404**,
because the Worker had not been deployed since those pages were written.
Deployed on 6 September with the owner's go-ahead; `/`, `/technology`,
`/support`, `/privacy`, `/terms` and `/about` all answer 200, the policy shows
6 September, and the support page carries the in-app reporting route. Re-check
after any further site edit: nothing deploys the site automatically, it is
`npx wrangler deploy` by hand.

## Claims that were corrected on the way here

- "Your code never leaves your device" → it is never uploaded to compile it, and
  leaves only on an export or an attachment the person makes. Fixed in the
  listing, the launch material and the privacy policy.
- "142 lessons and 200 patterns, checked by the compiler itself" → practised
  against the real compiler. There is no canonical proof over all 200 patterns
  and the promo text must not imply one.
- "SHA-256 checksums verified before anything is written to disk" → before any
  source is extracted or trusted. An archive has to exist before it can be
  hashed.
- Review notes said Crabrix "does not browse" third-party content while the app
  has a crates.io search. Now: no marketplace or storefront, and the one
  browsing surface is a search used to name a package to add.
- The privacy policy said there was "no personal data processing to describe"
  and "no data retention schedule". A support email is both. It now says what is
  received, why, how long it is kept and how to have it deleted — **owner to
  confirm that retention sentence describes what will actually be done.**
- `area-measurement.json` recorded an iPad rectangle from one state and a
  percentage derived from another, against a commit two candidates old. Both
  devices were re-measured from this build, and each percentage is now computed
  from the rectangle printed beside it.
- Build number raised to 3: this binary is not the one the 1.0 (2) archive
  holds. If App Store Connect already lists a build 3, raise it again.

## Not blockers, deliberately

Re-testing all 200 algorithm patterns by hand, a canonical-solution corpus, a
signed git tag, a five-device matrix, an Apple consultation, and a full Cargo
differential suite. Useful engineering, none of it a condition Apple sets on
this submission.
