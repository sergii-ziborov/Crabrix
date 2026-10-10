# Simulator recovery retry — 11 October 2026

The retry created an isolated clone of `Echo Shots 6.9` and booted iOS 26.5.
CoreSimulator subsequently restarted and logged that the booted clone was in
an unexpected state, then shut it down. The first test attempt exited 70
because Xcode could not discover its destination; no tests executed.

A second boot succeeded. Xcode 27.1 RC stalled during destination discovery
and reported `invalidDigitCount(94232)` for an installed runtime's build
version. Direct installation into the temporary clone also timed out. The
stalled local test process was stopped. The Mac was not rebooted, and existing
devices, app data and runtimes were retained.

`CrabrixLegalGate` selects only the six existing `BundledLicenseTests`, covering
the five offline legal documents and every document in all 1594 compiler notice
groups. A separate manual Xcode Cloud test workflow uses this scheme. Its
result is recorded in [the Cloud test report](legal-cloud-tests-2026-10-11.json).
All six tests passed on iPhone 16 Pro Max / iOS 27.0 in manual Cloud run 45
(`a5c6106e-3aa4-4087-9eef-b0b0e4ab29f5`), source `5144333`. Reading every
inventoried notice took 27 seconds. Distribution remains on the
existing manual workflow; GitHub Actions remain disabled.

Native app source and bundled resources are unchanged from the source of
App Review build 44 (`2a5dd98`).

The capture retry produced four fresh iPhone frames: Academy, editor, Projects
and My Courses. The next `simctl terminate` stalled in `stat` inside
`SimRuntime.initWithBundle`, before sending the app termination request.
The owned capture runner was stopped. These four drafts are preserved in
`screenshots/build44-partial/iphone-6.9/`; the complete previous public set
remains synchronized. The other six iPhone, seven iPad and two Duo images
remain pending. Duo cloning also timed out without returning a device ID.

The first temporary QA clone was removed. Shutdown of the capture clone
`6AD53FB8-1F68-484F-BCAF-40816535EED6` timed out; it remains named
`Crabrix RC screenshots iphone-6.9` for cleanup after CoreSimulator recovers.

## Cloud and later local recovery

The manual screenshot/legal reader runs 46 and 47 passed on iPhone, iPad and
Duo. Run 49 exercised Update all from the signed transition courses to the
current public course catalog, installed the separate 46-example pack, and
opened all five legal readers on Duo. See `native-cloud-qa-2026-10-11.json`.

Run 48 exposed an ambiguous UI-test selector: it could choose the underlying
"Download 46 Code Examples" button instead of the confirmation displaying
bytes. The test selector was narrowed to the byte-count confirmation in
`b292bfe`; native app source was not changed. RC photo jobs 52 and 53 were
rejected by the Cloud destination validator before running any tests. The
phone/iPad photo workflow was returned to its previously working SDK/runtime
27.0 configuration for retry 54. Distribution remains pinned to SDK 27.1.

The extra public XCUIScreen API probe in run 51 passed, but its internal Duo
frames were black and its application frames used the exterior screen. None
were substituted for the verified laptop captures. Local `simctl list` later
succeeded. A new isolated clone, `Crabrix Release50 Duo captures`, booted.
Device Hub from Xcode 27.1 RC exposed Closed/Partially Open/Open controls;
the clone was switched to Partially Open through the native UI. The older
Device Hub did not expose these controls.

Build 50 was installed through TestFlight by the owner and its version was
verified through CoreDevice. The Mac's remote-screen service still times out,
so this is version evidence, not a completed physical interaction pass.

## Completed follow-up

Run 54 succeeded on iPhone and iPad after the test confirmation selector fix.
All installed courses and Code Examples were updated through the UI; five
offline legal documents opened on each destination. Sixteen of its frames are
published; the SDK 27.0 iPad editor frame overlapped system tabs and was
excluded in favor of the verified SDK 27.1 editor image.

Cloud run 51 Test Products supplied a genuine build-50 SDK 27.1 Simulator
app. It was installed on the isolated Duo clone; a local test-without-building
passed and retained twelve attachments. The internal screen is active but
remains landscape when XCTest changes orientation. An actual native compiler
run completed with stdout `crab`. Device Hub rotation needs owner assistance
because native automation times out. The two existing verified portrait laptop
marketing frames remain. CoreDevice physical screenshot capture returned 4016
with no assertable trusted-connectivity or loaded-service states.
