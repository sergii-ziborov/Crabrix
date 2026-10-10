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
result will be recorded here after execution. Distribution remains on the
existing manual workflow; GitHub Actions remain disabled.

Native app source and bundled resources are unchanged from the source of
App Review build 44 (`2a5dd98`). Fresh iPhone, iPad and Duo screenshots remain
pending a stable Simulator session.
