# App Store and legal audit — updated 11 October 2026

## Selected release

App `6809502653`, version 1.1, selects build **50** (`d9905a8f-1a74-495e-8570-53d853861eb5`). Manual Xcode Cloud Build and Archive succeeded from source `bd1fcab38468efa7671ed05165688a13293ffa1e` with Xcode 27.1 RC / SDK 27.1. Apple reports VALID, APP_STORE_ELIGIBLE and Internal QA IN_BETA_TESTING. Review submission `ab085ac9-cba1-420e-bd0d-0bc8dadc9b33` and the version report WAITING_FOR_REVIEW. Release is MANUAL. SDK 27.1 compiles the preserved Duo hinge code; the SDK 27.0 build 44 was withdrawn after build 50 became valid. Native Swift and bundled resource files remain identical to `2a5dd98`. [Apple readback](review50-2026-10-11.json).

## Product page

| Field | Verified value or evidence |
| --- | --- |
| Name | Crabrix: Rust Compiler |
| Subtitle | Cargo IDE, offline on-device |
| Primary category | Developer Tools |
| Secondary category | Education |
| Description | [Saved text](description-1.1.txt), 3,764 characters; API readback matched |
| Promotional text | [Saved text](promotional-text-1.1.txt), 167 characters; API readback matched |
| Keywords | rustc,crates,code,coding,developer,compile,editor,learn,programming,algorithms,interview,wasm,course |
| Support | https://crabrix.com/support/ |
| Marketing | https://crabrix.com/technology/ |
| Privacy | https://crabrix.com/privacy/ |
| Privacy Choices | https://crabrix.com/privacy/#privacy-choices |
| Review notes | [Build-50 instructions](review-notes.txt); API readback matched |
| Reviewer login | Not required for the native app; separate website accounts are described |
| US customer price | USD 9.99, unchanged |
| Availability | All 175 territory records available; new territories enabled |
| Release option | Manual, unchanged |
| What's New | First public version; this field is not exposed for editing |

The ten iPhone, seven iPad and two Duo screenshots are COMPLETE, in verified order, with source-file MD5s matching the repository. Manual Cloud run 54 updated the courses and separately downloaded Code Examples through the real UI, then captured all product and legal-reader routes. Sixteen new phone/iPad frames are published. The verified SDK 27.1 iPad editor and two Duo laptop images remain: the SDK 27.0 iPad editor overlapped its system tabs, and local Duo orientation control remains unavailable. See [upload evidence](asset-upload-2026-10-11-build50.json) and [native QA](native-cloud-qa-2026-10-11.json). Site, GitHub and product-page aliases use matching image bytes.

In the authenticated Chrome session, Asset Library showed the two existing Search Results and Product Page Header creatives as Waiting for Review. App Information confirmed content rights and the Apple Standard License Agreement. These are existing submitted creatives; no featuring nomination, advertising campaign, press email or unsolicited communication was submitted.

## Privacy and applicable disclosures

The authenticated App Privacy page was inspected and showed a published **Data Not Collected** declaration. The native app has no website account service, analytics SDK or advertising service. Projects, avatars and learning progress remain on device unless the user chooses sharing. Optional Game Center uses Apple's service and its scoped player identifier; the app has no Crabrix leaderboard or profile server. The website's separate username/password account is described in Privacy and Terms and is not presented as native app registration.

The questionnaire was retained because this release changes documents and notices, not the native data flow. Both privacy links were updated through the API and read back. The public Privacy Choices section describes local data controls, optional Game Center controls and separate website account controls. Apple policy consulted: [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) and [Game Center scoped identifiers](https://developer.apple.com/documentation/gamekit/protecting-the-player-s-privacy-using-scoped-identifiers).

App Information showed the existing 4+ age rating, necessary content rights and declared trader status. API export-compliance data and build metadata report no non-exempt encryption. The app has no in-app purchases or subscriptions, so purchase-server notifications and subscription-specific fields are not applicable. App Accessibility declarations have not been published: no unsupported VoiceOver, 200% text or other accessibility claim was added without its required feature QA. Personal reviewer/trader contact details are retained in Apple and excluded from this public audit.

## Documents and licenses

Settings now includes full offline About, Privacy, Terms, Educational Content Rights and Application Source License, alongside the Apple Standard EULA link and open-source license reader. The website and GitHub use the same generated documents and content-license text. Third-party licenses remain unchanged and separately attributed. Native and website copies include the exact compiler primary-notice and 1,592-package vendor inventory archives verified against the signed toolchain release.

The Release app bundle was checked: all five legal documents and all 1,594 notice groups are readable and match the source bytes. License texts match pinned dependency sources. The same archives are served from https://crabrix.com/licenses/ with matching SHA-256 digests. The website account gate and existing Academy content remain active.

README legal links were updated in Crabrix, crabrix-courses, crabrix-runtime and crabrix-toolchain. GitHub Actions are disabled in all four repositories. Distribution was built in Xcode Cloud; no GitHub CI/CD or Cloudflare was used.

## Native QA and remaining device evidence

All six bundled-license tests passed in manual Cloud run 45, including every document in all 1594 notice groups. All five legal readers and the signed content-update path passed on iPhone/iPad in run 54 and Duo in run 49. The current infographic and highlighted code were visually inspected in the new lesson frames. Local Duo screenshot smoke testing passed with the genuine build-50 SDK 27.1 Cloud app; the native compiler completed a real run and printed `crab`.

The owner installed TestFlight 50 and CoreDevice reports 1.1 (50). Remote screen capture returns error 4016 with no assertable trusted-connectivity/service states, so complete physical interaction is still pending. The retained Duo marketing images show the previously verified portrait laptop layout; fresh landscape QA captures are stored separately. This report does not claim all keyboard gestures or all 742 lesson explanations were manually verified. Existing learner data and installed runtimes were retained; the Mac was not rebooted. Apple's review decision is pending.
