# Product distinctiveness review — 1 October 2026

This is an internal check of the candidate app workflow. The Apple message available to the team repeats a 4.3(a) rejection for build 8 but identifies no comparator app or codebase. This document cannot establish why that decision was made or predict a new review outcome. Apple's current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) also require accurate screenshots and disclosure of product changes under 2.3, and fully viewable/editable educational code under the limited 2.5.2 exception.

## Actual user path

1. **Academy** shows seven signed courses, progress, native lesson views, and an Examples card. A fresh install asks before downloading the Projects CoursePack and shows its size. Existing learners get the signed transition pack locally.
2. **Examples** reads 46 Rust projects from the installed pack. Opening one creates a new durable project with its own ID and course-version provenance; all Rust source files are visible in the editor and editable in the copy. The package cannot install a compiler or validator plug-in.
3. **Projects** leads to My Projects and New Project. GitHub and Files/iCloud Drive import are in New Project. The editor and local Check/Run path are the main workspace. Build output and lesson hints are in Output.
4. **Settings** exposes Auto, Light, Dark, and the app-wide Cyberpunk appearance, plus optional device authentication. Cyberpunk changes semantic tokens, course accents, and editor syntax colours rather than swapping one isolated screen.

The app's differentiation is the combination of the complete Academy corpus, local Rust compiler and Cargo subset, editable course-to-project handoff, offline state, and maintained runtime. The bundle ID is unchanged. Runtime provenance and a new theme are facts about the implementation; neither alone proves that Apple will consider the app distinct. The compiler in the current app bundle is still the older pinned artifact, and the source-built Crabrix toolchain is not yet a release input.

## Before a submission

- Capture new screenshots from the candidate binary. Existing `07-library` material predates the Academy move; screenshots must show the download and open path that reviewers will actually see.
- Verify the public catalog, descriptor, archive, and all linked URLs are reachable during review; verify a fresh installation can reach Examples without a special reviewer-only path.
- Describe the Academy Examples workflow, on-device compiler, supported Cargo subset, and current runtime/toolchain identities precisely in release notes. Do not claim a several-fold whole-app speedup from a Check microbenchmark or claim broad heavy-crate support while backend probes fail.
- Keep the known compatibility failures and unfinished source-built toolchain in technical validation notes. A reviewer can use the same ordinary app controls as a customer.
