# App unlock and Term Train connector fixes

## Source

The change is based on `681313e` (the verified 1.1.1 build 52 source) and preserves its output, rating, Game Center, Academy and Duo changes. Implementation commits: `27c415b` and `e8137bf` on `codex/term-train-connector-lock`.

## Term Train

The connector previously used each button's center anchor, drawing over its text. Anchors now belong to the inner eight-point dots. Bezier control points adapt to the horizontal gap, keeping the curve between its endpoints. The overlay remains noninteractive and the existing matched/wrong-pair styles are retained.

## Optional app protection

A system-cancelled authentication request previously consumed the foreground's automatic prompt. A fresh LocalAuthentication context can now retry once after the app is active, whether cancellation arrives before or after reactivation. A queued prompt that loses activation no longer consumes the next unlock. A manual tap supersedes a queued automatic prompt.

The controller continues to accept success while Face ID's own sheet briefly makes the scene inactive. Backgrounding invalidates the attempt before invalidating its context; a late success cannot unlock the app or clear a newer attempt. Explicit user cancellation does not automatically reopen the prompt. The retry limit prevents an automatic prompt loop.

## Verification

The focused manual Xcode Cloud scheme is `CrabrixInteractionGate`. It selects nine authentication state tests and two connector geometry tests on an iPhone and an iPad. The authentication context is injected in tests to reproduce callback ordering, interruption, cancellation and stale success deterministically; production uses LAContext with device-owner authentication. These tests do not constitute a physical Face ID check.

Latest full gate: run 59, `d1f3547e-f8d5-4e4a-a09e-26186aacd809`, source `e8137bf`, using the known working iOS 27.0 test environment. It completed **SUCCEEDED**. The downloaded XCResult confirms **11 unique tests, 22 successful executions across both devices, 0 failures and 0 skips**. Each test passed on iPhone 16 Pro Max and iPad Pro 13-inch (M4). The earlier iOS 27.1 runs 57 and 58 were rejected by Xcode Cloud's simulator destination configuration before running the tests; the advertised iPhone 16 Pro Max destination was not supported by its default runtime.

GitHub Actions are disabled. The dedicated Xcode Cloud workflow has only manual triggers and no distribution action. No DNS or hosting configuration changes are involved.

## TestFlight delivery

Manual release run **60**, `edb4fc76-8a61-4b59-93aa-fc25d9540788`, successfully archived source `85b43fe3ebf7791ac7aa1fcdce0d715a1e2320cf` with the configured iOS 27.1 SDK. Its app runtime files are identical to the passing regression source. App Store Connect build `9224e9a7-dadf-440b-b66d-2a5ad049b0af`, **1.1.1 (60)**, is **VALID** and **IN_BETA_TESTING**. Membership in **Internal QA** and the saved English What to Test notes were verified. [Release evidence](releases/1.1.1-build60.json). The local app and share-extension build settings are synchronized to 60; Xcode Cloud assigned 60 to the archived app. Physical Face ID confirmation remains a device test.
