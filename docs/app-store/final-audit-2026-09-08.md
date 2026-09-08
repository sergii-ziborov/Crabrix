# Crabrix pre-review audit — 8 September 2026

## Current status

**Build 1.0 (5) submitted to Apple: Waiting for Review.** All 398 fast
and 21 real compiler tests pass (419 total). Apple rejected build 4's loose
WASI static library resources; build 5 packages the same compiler data in a
bundled ZIP and passed upload validation. App Store Connect confirmed Waiting
for Review on 8 September 2026 after selecting build 5 and submitting the draft.
Release after approval remains manual. The Notes field was corrupted by automated
keyboard input, then restored: all 3882 characters match `review-notes.txt` after
server reload and navigation away and back. The description was also verified
unchanged. No fresh physical-device test was performed in this final pass.

## Initial decision for build 3

**Not ready to submit the inspected build 1.0 (3).** App Store Connect showed
**No Builds** in TestFlight during this audit and the version had no attached
build. The App Group UserDefaults reason was missing from both archived privacy
manifests. It is corrected in source; the existing archive has not been modified.
A fresh distribution archive and upload are required before selecting a build.

This is an engineering review against the publicly available Apple rules, not an
Apple approval. A passing local test suite does not establish acceptance under
the programming-environment exception.

## Findings

1. **Missing privacy reason — fixed in source, rebuild required.**
   `CrabrixShared/SharedImportQueue.swift` reads and writes
   `UserDefaults(suiteName: "group.com.sergiiziborov.Crabrix")` in the host and
   Share Extension. Both build-3 manifests declared only `CA92.1`. Apple defines
   `1C8F.1` for defaults shared inside an App Group. The app now declares both
   reasons; the extension declares `1C8F.1`. Both XML plists validate, and both rebuilt Simulator bundles contain `1C8F.1`.
2. **No available uploaded build — unresolved external state.**
   The authenticated Crabrix version page displayed the upload prompt instead
   of a selected build. TestFlight displayed **No Builds**. This does not prove
   that no upload was attempted; it does establish that no usable build was
   visible. Do not equate completing metadata with uploading the application.
3. **The universal source-editability claim is not fully enforced.**
   `CrateSourceBrowser.Entry.isProgrammingSource` recognises `.rs`, TOML and
   Cargo configuration. `sourceAccessIssue` also recognises explicit manifest
   entry points. Rust source reached through `include!("generated.txt")` or
   a nonstandard module path can fall outside that set. An oversized such file
   can pass the source audit, remain in the compiler's registry overlay, and
   be omitted by `vendorableFiles`. This is a source-inspection finding, not a
   newly executed end-to-end exploit. It was already listed as deferred in
   `docs/RELEASE-READINESS.md`; calling all source completely editable in review
   notes is stronger than the implementation proves. Address this edge before
   treating guideline 2.5.2 / DPLA 3.3.2 as fully covered.
4. **Store copy overstates offline durability — description corrected and saved.**
   The saved description ends the network caveat with “everything after that
   does not.” Cached dependencies can be purged unless pinned. Prefer:
   “The compiler, lessons and local projects work offline. Cached dependencies
   rebuild while iOS retains them; Pin for Offline preserves verified package
   archives after cache eviction.” The description also says unsupported crates
   are always detected before failure; code-generation gaps can still fail
   during compilation. Both points were corrected in the App Store Connect
   description (3975 characters), and Save returned to disabled. The local
   `docs/app-store/listing.md` description matches the saved text.
5. **Live privacy text needs small factual corrections.**
   The policy says there is no access to photos, but Profile uses the system
   PhotosPicker for an optional local avatar. No broad photo-library permission
   is requested, but the selected image is read and stored locally. Describe
   that distinction. The “complete list” of network requests omits the crates.io
   search/owner API (`crates.io/api/v1/...`); include user-requested package
   discovery and metadata as well as source downloads. Optional support email
   is already described, including the environment toggle and retention.
6. **Old evidence is not a current source-to-archive identity.**
   The archive hash matches `release-evidence/1.0/3/checksums.json`, but the
   recorded source commit predates the Report a problem change and build-number
   bump. Later support changes also exist in the working source. The README
   still referenced build 2 and beta Xcode; it has been updated. Record the real
   source commit and hashes when producing the new archive.

## Verified directly

- Stable Xcode 26.6 (17F113) is installed. The inspected archive reports that
  Xcode build and iOS SDK 26.5, version 1.0 (3), minimum iOS 18.0 for app and
  extension. The globally selected Xcode was beta; tests explicitly used stable.
- Archive executable SHA-256:
  `ce42b4f6d12dd82027f2b98c0e7cb370b3830b88f3a9e7c8575a490d7634f542`.
- The archived executable does not link GameKit. FoundationModels is weak-linked.
- The source App Store icon is 1024 × 1024 with no alpha channel.
- Current prices verified in App Store Connect: United States $9.99, Ukraine
  manual override $4.99. Pricing was not changed.
- Pricing and Availability: 175 countries/regions, public distribution, Apple
  Silicon Mac availability off, Vision Pro off, tax category App Store software.
- Saved App Store version: English (U.S.), description, promo, keywords, support
  and marketing URLs, review contact including phone, detailed review notes;
  sign-in requirement off; Game Center off; manual release selected.
- In the confirmed Chrome profile `sergii.ziborov@gmail.com`, App Privacy was
  published as **Data Not Collected**, with `https://crabrix.com/privacy`.
- Eight iPhone and six iPad 13-inch screenshots were visible in App Store Connect. Locally the eight
  iPhone files are 1320 × 2868 and the six iPad files are 2064 × 2752.
- Public HTTPS pages `/`, `/about`, `/technology`, `/support`, `/privacy`, `/terms`
  were fetched successfully. Home and support render in the browser. The support
  form prepares a mail draft; no test message was sent.
- Existing build-3 area evidence records 72.9% iPhone, 30.0% initial iPad and
  66.2% widest measured iPad editor arrangement, below the DPLA 80% condition.
  These are historical measurements, not a new all-device/orientation check.

## Fresh automated verification

- Fast suite: **391 tests, 0 failures**, Release, iOS 26.5 iPhone simulator.
  Result: `/tmp/crabrix-final-fast-retry-20260908.xcresult`.
- The initial plain Release test invocation failed at test-module import, before
  executing tests. The existing suite uses `@testable import`, so the successful
  run explicitly set `ENABLE_TESTABILITY=YES` and `ONLY_ACTIVE_ARCH=YES`.
  These are testing overrides, not distribution settings.
- Full bundled-compiler suite: **21 tests executed; 20 passed and one Stop
  test failed with two assertions**. Result:
  `/tmp/crabrix-final-compiler-20260908.xcresult`. All guided showcase checks,
  package linking, Vendor & Edit, offline-pin rehydration, memory limits,
  visual examples and view-model drain checks passed.
- The Stop test requested cancellation after a fixed three-second sleep, after
  the optimised check had already succeeded. Changed the delay to 100 ms to
  match the existing view-model gate. Its targeted rerun **passed in 0.154 s**:
  `/tmp/crabrix-final-stop-20260908.xcresult`. The production Stop implementation
  is unchanged. The original full run remains a failed run; it is not relabelled.
- Machine-readable per-test outcomes are in
  `release-evidence/pre-review-2026-09-08/tests.json`. These results cover source
  tests in a Simulator, not an App Store-distributed build.
- `plutil -lint` passes for both corrected privacy manifests; `git diff --check`
  passes.

## Not verified in this session

- Physical-device runtime, thermals, airplane-mode behaviour, and the Mail
  handoff/cancel flow. Prior device testing is owner-attested; it is not a fresh
  test of the rebuilt candidate.
- Full age-rating questionnaire and business agreement/banking status. The
  displayed rating is 4+; the first questionnaire page showed No for parental
  controls, age assurance, unrestricted web access, UGC, social media, messaging
  and advertising. Content rights are declared Yes; the developer is marked
  as a trader. Categories are Developer Tools and Education. These were checked
  in the confirmed Chrome profile `sergii.ziborov@gmail.com`.
- Distribution export/upload validation, App Store processing, or review approval.
- Complete canonical solutions for all 200 algorithm patterns or a full Rust/Cargo
  compatibility proof. The compiler suite has bounded coverage.

## Apple references checked

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):
  2.1 completeness, 2.3 accurate metadata, 2.5.2 educational executable code,
  5.1 privacy.
- [Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/):
  3.3.2 programming-environment conditions, including view/edit and 80% area.
- [Required API reason definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons):
  `CA92.1` versus `1C8F.1`.

## Next submission steps

Resolve the source-editability edge and align the saved metadata/privacy copy.
Build a new candidate containing the manifest correction, using a fresh build
number if build 3 has already been uploaded. Record its source/hash identity,
exercise the short physical-device path, upload and wait for Apple processing,
select the processed build, then review the remaining App Store declarations.

## Submission outcome

The owner authorised submission only if the checks were clear. No submission
was made: TestFlight still showed No Builds in the explicitly confirmed Chrome
profile, and the source-editability edge plus the rebuilt-archive requirement
remain unresolved. The corrected store description was saved successfully.


## Build 4 follow-up (8 September 2026)

The owner explicitly authorized fixing the blockers, archiving, uploading and submitting.

- Source commit `20408d0`: all UTF-8 files are now required to fit the complete editable overlay, regardless of extension or macro-selected include path. Non-UTF-8 known programming files fail closed. Non-source binary assets remain in the registry tree. This conservative rule can reject a crate with oversized documentation; no text is silently omitted. Three regression tests cover macro-selected nonstandard source, oversized nonstandard source, and text file-count overflow.
- Source app and extension include the App Group UserDefaults reason `1C8F.1`; verified in the new archive.
- Version 1.0 build 4 archived successfully using stable Xcode 26.6 (17F113), iPhoneOS 26.5 SDK, deployment target 18.0.
- Fresh Release Simulator verification: **394 fast tests passed; all 21 bundled compiler gates passed**, including real downloaded and patched crates, offline-pin rehydration, repeated runs and cancellation. Results: `release-evidence/1.0/4/tests.json`.
- Archive identity and hashes: `release-evidence/1.0/4/archive.json`. Testability overrides were used only for testing, not archiving.
- Upload attempted with stable and beta Xcode export tools; both returned `Failed to Use Accounts`. Export-only returned `No Accounts / No signing certificate iOS Distribution found`. The visible Xcode beta account can show its Developer team but the distribution session cannot access App Store Connect. Owner asked to refresh sign-in. No IPA uploaded and no review submission confirmed.
- Physical iPhone currently unavailable in devicectl; no new physical-device test claimed.
- Lovable factual copy patch `953082ca88ac5560ff4a1645c6b3106313cdfb0f` published as deployment `bb03143f-1d8b-49a5-9243-8b894edfdc35`; new privacy text verified at crabrix.lovable.app. The custom domain still serves the legacy Cloudflare Worker; its update is being handled separately.

- Legacy custom-domain Worker updated successfully: version `c647eacd-2a01-4072-9c5f-b41ddb9dcb67`. Only the three changed static files uploaded; new privacy wording verified at https://crabrix.com/privacy.


## Build 5 and actual Apple upload validation

- Xcode Organizer used the existing account successfully; the earlier failure was in CLI account access. No account removal or credential changes were needed.
- Apple rejected build 4 with `Invalid bundle structure` for 21 loose `.rlib`/`.a` WASI library resources. This was upload validation, not an App Review rejection.
- Commits `18d9519` and `5a35a1a` package the sysroot in a signed bundled ZIP resource and extract it on the compiler queue, verifying SHA-256 and manifest completeness. Cache eviction (full or partial) and interrupted preparation recover from the bundled resource without network. Stop during preparation is remembered.
- `scripts/package_toolchain.py` is used both by bootstrap and Xcode's resource preparation. No loose static libraries remain in the new app. The ZIP's 43 files are byte-identical to pinned source inputs. Review notes explicitly disclose the packaging and local extraction.
- Final archive `build/Crabrix-1.0-5-final.xcarchive`, source `5a35a1a`, stable Xcode 26.6/17F113, iPhoneOS 26.5, minimum iOS 18. Signature verification passes.
- Fresh tests of the final code: 398 fast tests and all 21 real compiler gates pass. Four installer regressions cover first extraction, full cache eviction, partial eviction, corrupt archive and interrupted installation.
- Organizer visibly confirmed **App upload complete: Crabrix 1.0 (5) uploaded**.
- Factual website corrections are live at both crabrix.com and crabrix.lovable.app.
- Metadata automation limitation: keyboard typing dropped characters in Notes; native paste repeatedly returned clipboard-read timeout and AX setValue did not persist. The damaged value was identified and the owner was given the exact replacement file for a manual paste. No review submission will be made with damaged notes.
