# App Store and legal audit — 10 October 2026

## Selected release

App `6809502653`, version 1.1, selects build **44** (`e9c73e7e-534d-4792-96cf-578812a441a3`). Xcode Cloud Build and Archive succeeded from source `2a5dd98aa03762dfca6e7d55c941850db4a3f950`. Apple reports VALID, APP_STORE_ELIGIBLE and Internal QA IN_BETA_TESTING. Review submission `a953a91f-bda4-4e8c-8cb8-8adb114c9832` and the version report WAITING_FOR_REVIEW. Release is MANUAL. The previous build-43 submission was canceled only after build 44 was valid.

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
| Review notes | [Build-44 instructions](review-notes.txt); API readback matched |
| Reviewer login | Not required for the native app; separate website accounts are described |
| US customer price | USD 9.99, unchanged |
| Availability | All 175 territory records available; new territories enabled |
| Release option | Manual, unchanged |
| What's New | First public version; this field is not exposed for editing |

The ten iPhone, seven iPad and two Duo screenshots are COMPLETE, in verified order, with source-file MD5s matching the repository. One iPad Projects asset differed from the local verified image and was replaced. Other uploads also reconciled ordering. See [upload evidence](asset-upload-2026-10-10-build44.json). The evidence explicitly distinguishes retained verified captures from the pending fresh build-44 Simulator recapture. Editor and Duo source logic did not change in build 44.

In the authenticated Chrome session, Asset Library showed the two existing Search Results and Product Page Header creatives as Waiting for Review. App Information confirmed content rights and the Apple Standard License Agreement. These are existing submitted creatives; no featuring nomination, advertising campaign, press email or unsolicited communication was submitted.

## Privacy and applicable disclosures

The authenticated App Privacy page was inspected and showed a published **Data Not Collected** declaration. The native app has no website account service, analytics SDK or advertising service. Projects, avatars and learning progress remain on device unless the user chooses sharing. Optional Game Center uses Apple's service and its scoped player identifier; the app has no Crabrix leaderboard or profile server. The website's separate username/password account is described in Privacy and Terms and is not presented as native app registration.

The questionnaire was retained because this release changes documents and notices, not the native data flow. Both privacy links were updated through the API and read back. The public Privacy Choices section describes local data controls, optional Game Center controls and separate website account controls. Apple policy consulted: [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/) and [Game Center scoped identifiers](https://developer.apple.com/documentation/gamekit/protecting-the-player-s-privacy-using-scoped-identifiers).

App Information showed the existing 4+ age rating, necessary content rights and declared trader status. API export-compliance data and build metadata report no non-exempt encryption. The app has no in-app purchases or subscriptions, so purchase-server notifications and subscription-specific fields are not applicable. App Accessibility declarations have not been published: no unsupported VoiceOver, 200% text or other accessibility claim was added without its required feature QA. Personal reviewer/trader contact details are retained in Apple and excluded from this public audit.

## Documents and licenses

Settings now includes full offline About, Privacy, Terms, Educational Content Rights and Application Source License, alongside the Apple Standard EULA link and open-source license reader. The website and GitHub use the same generated documents and content-license text. Third-party licenses remain unchanged and separately attributed. Native and website copies include the exact compiler primary-notice and 1,592-package vendor inventory archives verified against the signed toolchain release.

The Release app bundle was checked: all five legal documents and all 1,594 notice groups are readable and match the source bytes. License texts match pinned dependency sources. The same archives are served from https://crabrix.com/licenses/ with matching SHA-256 digests. The website account gate and existing Academy content remain active.

README legal links were updated in Crabrix, crabrix-courses, crabrix-runtime and crabrix-toolchain. GitHub Actions are disabled in all four repositories. Distribution was built in Xcode Cloud; no GitHub CI/CD or Cloudflare was used.

## Remaining device evidence

Release app compilation and the Debug arm64 build-for-testing passed. Execution of the six bundled-license tests and a complete fresh screenshot recapture are blocked by the Mac's CoreSimulator broker, which also stalls on simple device-list calls and with a separate device set. Targeted service restarts did not recover it. The owner has been asked to restart the Mac after other work completes. Existing devices, runtimes, branches and learner data were not deleted. Physical-device TestFlight QA and Apple's review decision remain pending. These pending checks are not claimed as completed.
