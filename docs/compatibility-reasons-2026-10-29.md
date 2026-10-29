# Structured local compatibility reasons — 29 October 2026

This app-code follow-up is qualified on phone/iPad Simulator and prepared for the
next app build. It is **not contained in signed build 120 on App Review**.
Interview 1.1.0 is a separate compatible content update and needs no new binary.

`LocalExecutionReason` supplies stable codes and a category at the source of
inspection, not by searching diagnostic text or a crate name. Package status
retains the original explanation. Project preflight carries that code, the
exact package/path subject, affected operations and a manual next step. Existing
Check/Build/Run/Debug evidence remains source/resource/compiler bound. Inspection
never runs a compiler, installs packages or edits a manifest.

Covered static sources include native-link metadata, host procedural macros,
proc-macro features, non-rlib targets, missing library targets, separate build
dependency graphs, source access, file/manifest validation, workspace selection,
minimum rust-version, library entries and fixed-target Cargo overrides.
Unprepared/unresolved graphs have preparation reasons. A previous compiler
attempt is its own retryable category even if its message contains CUDA, native
library or proc_macro; it is not reclassified as a platform restriction. Unknown
legacy requirements remain explicitly unspecified. Build-script review is an
explicit producer-assigned code, not an assumption about every review status.

The existing preflight scroll sheet shows the code, subject and next step.
`cargo tree` includes stable reason markers. Editor, terminal input, keyboard,
file drawer and four dock tabs retain their layouts; no new main workspace panel
or automatic source adaptation was introduced. The phone/iPad UI route returns
to unchanged source after inspecting the report and verifies all four tabs.

Validation: 39 native checks plus one UI flow on each device type passed in
CrabrixInterviewGate. The native suite includes signed course installation and
12 actual bundled-compiler examples; it is not 39 newly added tests. Five new
reason tests verify stale-graph exclusion, exact subjects, translated/unknown
messages, compiler-failure separation and terminal codes independent of names.
Twenty course-tool tests, 35 website tests and website TypeScript/build passed.

Remaining work stays explicit: full runtime allocation/timeout/trap causality,
compiler/procedural-macro candidates and physical-device performance qualification
are separate. A structured previous-attempt category does not claim the root
cause of every compiler failure is known. No platform support or speed claim
was expanded by this classification change.
