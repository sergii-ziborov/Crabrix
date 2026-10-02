# Crabrix 1.1 App Store copy

This copy describes the 1.1 (11) tester build. The 1.1 version record and this
English copy were saved in App Store Connect on 2 October, and all 14 current
iPhone and iPad screenshots were uploaded and verified. The version has not
been resubmitted for App Review; physical-device testing remains with the
testers before submission. See [the upload evidence](asset-upload-2026-10-02.json).

## Promotional text

> From lesson to running Rust: the full Academy, 46 downloadable Examples, real Cargo projects, and local compilation on iPhone and iPad. No account required.

## Description

```text
Crabrix is a native Rust learning and coding workspace for iPhone and iPad.
Write a project, check real rustc diagnostics, repair the code, and run the
result in a bounded WebAssembly sandbox. Compilation happens on your device;
there is no cloud compiler or required account.

LEARN WITH THE FULL ACADEMY
Seven courses cover Rust fundamentals through systems and interview topics,
plus Algorithm Atlas: 742 lessons and steps, 200 algorithm challenges, source
projects, questions, explanations, and practice material. A new installation
starts with Basics; choose and download the other courses from the catalog.
Existing learners retain all seven transition courses offline after updating.
Lessons can open starter code as a separate editable project. Course downloads show their size,
are checked before installation, and leave your projects and progress in place
when you update or delete course material. Installed courses are readable
offline. The Projects course also supplies 46 downloadable Rust Examples in
Academy. Open one to create your own editable project; its source is visible
and the course copy stays unchanged. New course versions need a connection for
their first download.

BUILD YOUR OWN PROJECT
The project workspace has a native file tree, syntax-aware editor, Code and
Output views, and compiler diagnostics that point to source spans. My Projects
opens the project manager. New Project offers local templates and imports from
GitHub and Files/iCloud Drive. Check and Run use Crabrix's source-built Rust
compiler bundled with the app. Lesson hints appear in Output while you work.

CARGO IN THE PROJECT
Add supported crates.io dependencies to a project's Cargo.toml. Crabrix
resolves and builds them locally, verifies downloaded source, and can pin the
exact dependency graph for offline rebuilds. Dependencies that need unsupported
native linking, executable build scripts, or procedural macros may not build.
Reading an installed course stays available even when a crate is not ready.

MAKE IT YOURS
Choose Auto, Light, Dark, or a Cyberpunk appearance across the app. Optional
Face ID or device-passcode protection locks the workspace when you leave it.
Rating and achievements stay on the device; practice does not use Health or
Energy limits.

PRIVACY AND OFFLINE USE
Projects, notes, progress, and compiler output stay local unless you choose to
export or share them. Crabrix has no analytics SDK, advertising, or account.
Course updates, crates.io packages, and GitHub imports use network requests;
the hosts may keep ordinary access logs. After course material and required
dependencies are prepared, learning and compilation can work offline.

Crabrix currently targets wasm32-wasip1. It is a focused on-device Rust
environment, not a replacement for a desktop toolchain or debugger. One
purchase; no subscription or in-app purchase is required.
```

## Reviewer path

Use [review-notes.txt](review-notes.txt) with screenshots captured from the
exact release candidate. The historical 1.0 screenshots are not 1.1 evidence.

## What to test in TestFlight

Open Learn on a fresh install, download the Projects course after checking its
size, and open an Academy Example as a separate editable project. Check and Run
it, switch to Output, then choose another source file and confirm Code returns.
Try a supported Cargo dependency in a project, Stop a long compile, and confirm
the next Run works. Restart offline to check installed lessons and prepared
dependencies. On an existing installation, verify that progress and user
projects survive the transition. Check Cyberpunk across Learn, Projects, and
the editor, plus optional Face ID or passcode protection on a physical device.
