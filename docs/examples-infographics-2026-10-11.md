# Complete Examples infographic release

## Published content

Examples 1.0.3 contains 46 distinct infographics with accessible descriptions and captions. The four existing images are preserved; 42 new images were produced with the built-in ImageGen tool and reviewed against the example sources. The prompt specifications, correction prompts, image hashes, dimensions and source hashes are in [`crabrix-courses/artwork/examples`](https://github.com/sergii-ziborov/crabrix-courses/tree/dd0d671d8a6ce87f72accd001bfb3dd47ec011b8/artwork/examples).

All Rust sources and Cargo manifests are unchanged. Two README descriptions were corrected: Game of Life's horizontal wrapping uses the width; both fixed Word Chain samples fail for the reasons stated in the revised guide.

- Release: [coursepack-v1.0.9](https://github.com/sergii-ziborov/crabrix-courses/releases/tag/coursepack-v1.0.9).
- Archive: `examples-1.0.3.zip`, 72,432,250 bytes.
- Archive SHA-256: `acdf44d425ed9b06351a0305f30cef41642e30761caa551fb7a6fbeb632b3284`.
- Production signature key ID: `crabrix-course-2026-10`.
- Public catalog: sequence 10; the seven curriculum entries are identical to sequence 9.
- App compatibility: Crabrix 1.1, `coursepack-v1` and `examples-gallery-v1`.

Existing learners can use **Learn → Code Examples → Update** or Update in My Courses. An already open guide retains its old snapshot; reopening it displays the updated guide. Copies in My Projects are independent of the installed pack.

## Verification

The course schema, archive hashes, production signatures, 46 unique PNGs and preservation of all example Rust/Cargo files passed verification. Eleven editorial and packaging tests passed. All 46 Rust projects compiled and ran with host Rust; this is a source check, not a device UI test.

The native update gate is `CourseDeliveryGateTests/testPublicExamplesUpgradeKeepsEditedProjectAndLoadsEveryInfographic()`. It installs production 1.0.2, edits and persists an example, refreshes the public catalog, installs the new pack, decodes all 46 images, compares stable example IDs and Rust files, and reopens the edited project to verify its files, durable identity and original version provenance.

Manual Xcode Cloud run **55**, `c638375b-1422-4992-9918-1bd5337bf964`, completed **SUCCEEDED** on source commit `27e27ca6adb85641416f05d526183e22f636c2b1`. The iPhone 16 Pro Max simulator with iOS 27.0 passed all three selected tests: the Examples upgrade gate, public signed catalog/course installation, and resumed archive download. The downloaded XCResult summary confirms **3 passed, 0 failed, 0 skipped**. This verifies native delivery and image decoding, not physical device UI or new Duo screenshots.

## Website and review

The Next.js homepage and both app/course READMEs describe the complete illustrated gallery. The Hetzner deployment passed route, guest-preview and protected-media checks; all 21 existing screenshot hashes match. Production image: `b9153c081d02973ffdd87ebf81ac8638b9c55b4be92a9b20ec6c9cf2541a1cf5`.

The release changes course content, tests and documentation. It does not change app runtime or interface source. Apple version 1.1 remains associated with build 50 and was `WAITING_FOR_REVIEW` when checked. GitHub Actions remain disabled. Native verification runs only in the manually started Xcode Cloud workflow.
