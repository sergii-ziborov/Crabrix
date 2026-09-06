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

### 2. Report a problem has never run on the phone

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
| App Store Connect fields | owner-only | not visible from this machine |

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
