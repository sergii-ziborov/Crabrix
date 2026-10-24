# Test-only compiler candidate

The manual **Compiler performance candidate (manual)** Xcode Cloud workflow
builds a pinned, optimized WASI rustc into `Artifact/`. This folder is copied
only into the XCTest bundle. It never replaces the signed app compiler, sysroot
or release manifest. Candidate validation explicitly opts in with
`CRABRIX_RUN_COMPILER_CANDIDATE=1`; ordinary tests skip it.

The test saves the candidate compiler and provenance as retained XCTest
attachments before compiling representative programs with the app's signed
target sysroot. Download these from the Cloud result bundle for subsequent
physical iPhone comparison. Cloud timings do not establish the 30-second device
target, and compilation or sysroot failures must remain visible failures.
