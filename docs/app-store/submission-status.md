> Current status — 10 October 2026: **1.1 (43)** was compiled, archived, and
> uploaded by Xcode Cloud from `9433d98`. App Store Connect processed it as
> `VALID` and `APP_STORE_ELIGIBLE`. Internal QA reports `IN_BETA_TESTING` and
> the en-US What to Test matched API readback. Version 1.1 selects build 43;
> it and submission `cd2c216d-cfad-48e1-a7b0-e6597aa45030` read back
> `WAITING_FOR_REVIEW`. Reviewer notes name build 43, and release remains
> manual. Signed CoursePack catalog sequence 9 delivers the updated lessons.
> Physical-device confirmation and Apple's review are pending. See the
> [build-43 manifest](../releases/1.1-build43.json).

> Earlier status — 10 October 2026: **1.1 (42)** was compiled, archived, and
> uploaded by Xcode Cloud from `f2a288c`. App Store Connect processed it as
> `VALID` and `APP_STORE_ELIGIBLE`. It is in TestFlight **Internal QA** with
> the updated en-US What to Test. The 1.1 version selects build 42; both the
> version and submission `4e534419-bb03-4deb-9f80-d5670469d4dd` read back
> `WAITING_FOR_REVIEW`. Reviewer notes match the saved build-42 text. Release
> remains manual. Rust Basics 1.0.3 is available as a signed lesson update,
> with a corrected Printing Values diagram and clearer inline Rust text.
> Physical-device confirmation and Apple's review are pending. See the
> [build-42 manifest](../releases/1.1-build42.json).

> Earlier status — 8 October 2026: **1.1 (36)** was built by Xcode Cloud
> run 36 from source commit `35ddb46` (locally labeled build 26). Cloud Build
> and Archive succeeded; App Store Connect processed the linked binary as
> `VALID` and `APP_STORE_ELIGIBLE`. It is attached to TestFlight **Internal QA**
> (`IN_BETA_TESTING`) and selected for the App Store 1.1 version. The en-US description, build-36
> Review Notes, and TestFlight What to Test matched API readback. Ten iPhone,
> seven iPad (new search first), and two iPhone Duo screenshots reached
> `COMPLETE` and appear in order. Version 1.1 and submission
> `c78c865e-156f-4f26-a0d1-4f6db860ddcd` now read back
> `WAITING_FOR_REVIEW`. Release remains manual. `whatsNew` was unavailable
> during editing (HTTP 409 `STATE_ERROR`). Physical-device TestFlight QA is
> still pending. See the [Cloud release manifest](../releases/1.1-build36.json),
> [local source manifest](../releases/1.1-build26.json), and
> [screenshot evidence](asset-upload-2026-10-08-build26.json).

> Earlier status — 8 October 2026: **1.1 (25)** is **VALID** and available in
> TestFlight Internal QA. Its signed archive and IPA passed Apple validation.
> The App Store 1.1 version now selects build 25; the en-US description and
> Review Notes were updated and read back. Seven iPad 13-inch screenshots from
> build 25 reached COMPLETE and appear in the requested order. They show the
> editor without the old right inspector. The ten iPhone 6.9-inch screenshots
> remain from build 24 because this edit did not change iPhone layout.
> The prior build 24 submission was canceled and is COMPLETE; App Store Connect
> currently reports DEVELOPER_REJECTED for the version. Build 25 is not yet
> resubmitted. iPhone Duo screenshots are pending. Release remains manual.
> See the [build 25 manifest](../releases/1.1-build25.json) and
> [iPad upload evidence](asset-upload-2026-10-08-build25.json).

> Earlier status — 8 October 2026: **1.1 (24)** was **Waiting for Review** in
> submission `d6c99b9d-65f1-4087-aa0b-6d0f1847b1b2`. The en-US product page
> now has a header image and a separate search-results image; both were uploaded
> to Asset Library, selected on the version page, and the page displayed 1 of 1
> for each placement. The new submission contains the version item; the API
> confirmed `WAITING_FOR_REVIEW` for both submission and version. Release is
> still manual. [Creative evidence](creative-upload-2026-10-08-build24.json).
>
> Earlier on 8 October, 1.1 (24) was waiting in submission
> `67fcdbd6-987a-4865-ae9e-1726e08331a2`. It was canceled to add the new
> creative assets; the API now reports that submission as `COMPLETE`. The
> [reply to Apple's earlier 4.3(a) rejection](rejection-response-1.1-build24.md)
> was sent in that earlier submission and remains in its message history.
> Build 24 remains available in TestFlight Internal QA. Approval will require
> a separate release action.
> The [build 24 manifest](../releases/1.1-build24.json) and
> [validation record](../VALIDATION.md) identify the build and test evidence.

> Earlier status — 7 October 2026: **1.1 (24)** was **VALID** and
> **IN_BETA_TESTING** in TestFlight Internal QA, but its App Review submission
> still showed **Unresolved Issues** from the earlier review of 1.0 (8).
> The refreshed en-US description, Review Notes, ten iPhone and seven iPad
> screenshots were saved and verified. The unchanged Settings frame was reused
> from prior release evidence after a blank Simulator capture was rejected.

> Earlier status — 5 October 2026: **1.1 (21)** is **VALID** and
> **IN_BETA_TESTING** in TestFlight Internal QA. The signed IPA, Apple
> validation, upload, saved What to Test, and tester-group membership were
> verified. [The build manifest](../releases/1.1-build21.json) and
> [validation record](../VALIDATION.md) identify the exact source and artifact.
> Physical-device tester results are pending. This build has **not** been
> submitted for App Review.

> Earlier status — 2 October 2026: **1.1 (12)** was archived and exported with
> stable Xcode 27.0 (27A266a). Apple validation and upload succeeded. App Store
> Connect processed it as **VALID** and **IN_BETA_TESTING** for Internal QA;
> its What to Test was saved and read back. The 1.1 English listing and all 14
> current screenshots were uploaded and verified. The App Store version has
> **not** been submitted for review. Physical-device tester results are pending.
> See [the build manifest](../releases/1.1-build12.json) and
> [screenshot evidence](asset-upload-2026-10-02-build12.json). The entries below
> describe earlier builds.

> Earlier 2 October status: **1.1 (11)** was VALID in Internal QA. Build 12
> replaces it as the current tester candidate.

> Earlier 2 October status: **1.1 (10)** was uploaded and processed as VALID
> for Internal QA. Build 11 replaces it as the current tester candidate; its
> signed, source-built toolchain and exact artifact mapping are recorded above.

> Current status — 9 September 2026: **1.0 (7)** uploaded at 12:37,
> **Validated** in App Store Connect, and added to the **Internal QA** group
> (one tester). What to Test was saved and verified after a server reload.
> Local Release validation: **414 fast tests + 24 real compiler gates passed**.
> Xcode Cloud Build and Archive both succeeded on stable Xcode 26.6 / macOS
> 26.6.2. Build 7 has **not** been resubmitted to App Review: the owner must
> repeat device QA and supply the recording/information requested for build 6
> under guideline 2.1. Manual release remains selected.
> See [device QA fixes](device-qa-2026-09-09.md) and
> [build 7 evidence](../../release-evidence/1.0/7/cloud-build.json).
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
