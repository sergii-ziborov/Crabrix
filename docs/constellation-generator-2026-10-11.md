# Constellation Generator update

## Published content

[Examples 1.0.4](https://github.com/sergii-ziborov/crabrix-courses/releases/tag/coursepack-v1.0.10) improves Constellation Generator with a repeatable 64 × 40 color canvas and a bordered 38 × 12 terminal sky. Restrained static halos, seeded diagonal haze and one short meteor trail add depth. The code uses a small `u32` generator, separate sequences for the two views, clipped pixel writes and bounded placement attempts. It needs only Rust's standard library.

The [source, guide and metadata](https://github.com/sergii-ziborov/crabrix-courses/tree/1bf3be9805f7291fef5b74ca8c734b400dde8cf5/courses/examples/library-projects/constellation-generator) describe the same algorithm. The [ImageGen prompt, artwork audit and actual program output](https://github.com/sergii-ziborov/crabrix-courses/tree/1bf3be9805f7291fef5b74ca8c734b400dde8cf5/artwork/examples) are preserved. The infographic identifies its decorative sky as a stylized preview; the separately rendered output image comes directly from the Rust program's JSON pixels.

- Archive: `examples-1.0.4.zip`, 72,387,192 bytes.
- SHA-256: `89bd11f2fa56a917d246a7bfa1ae3ac0836a91769cc6dfad90d9e12fb78e0a34`.
- Production key ID: `crabrix-course-2026-10`.
- Public signed catalog: sequence 11; all seven curriculum entries are unchanged from sequence 10.
- Compatible app: Crabrix 1.1, including the existing build 50.
- The other 45 example programs, guides, metadata and images are unchanged from Examples 1.0.3.

Use **Learn → Code Examples → Update**, reopen the guide, then **Open in Code** for a new editable copy. Updating a template does not overwrite an existing copy in My Projects. An already open guide retains its older snapshot until reopened.

## Source and packaging verification

Fourteen host tests passed: debug/release repeatability, changed-seed output, valid bounded canvas data, dense star placement termination, deterministic archive builds, signature/tamper rejection, catalog rollback checks, all 46 packaged guides and infographics, and lesson editorial checks. Schema validation covers eight packs and 742 lessons. The published descriptor and catalog match the locally verified signed bytes; the public archive serves its expected 72,387,192-byte range.

The immutable migration baseline deliberately reports four changes for Constellation Generator: concepts, detail, content digest and `src/main.rs`. The test suite requires exactly those differences and no other source changes. It does not rewrite the migration baseline or claim the upgraded program is identical to the old version.

## Native verification

Manual Xcode Cloud run **56**, `8dcaa071-22be-4c1d-8617-e64c8e82d015`, was started on commit `d75f94b54b482d97118d16d835b523d613ed47c4` with the `CrabrixCourseDeliveryGate` scheme. It completed **SUCCEEDED** on the iPhone 16 Pro Max simulator with iOS 27.0. The downloaded XCResult confirms **4 passed, 0 failed, 0 skipped**, including three executions through the bundled WASI Rust compiler (same seed twice, then a changed seed). This is native compiler/delivery verification, not a physical device UI check.

The four selected tests cover public signed catalog/course installation, resumed download, a production 1.0.2 → 1.0.4 Examples upgrade preserving an edited Constellation Generator project and decoding all 46 images, and execution of the new source using the app's bundled WASI Rust compiler. The compiler test requires a valid native 64 × 40 canvas, identical repeated output and different pixels after changing the seed.

This release changes course content, tests and documentation. GitHub Actions remain disabled; the Xcode Cloud workflow has no automatic branch, pull request, tag or schedule triggers.
