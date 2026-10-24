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

Local variants use separate ignored folders: `ArtifactO2/` retains a verified
Binaryen transform with its parent digest and transform provenance;
`ArtifactFat/` retains a separately built full-LTO compiler. The original
`Artifact/` is preserved. The measured helper uses the full compiler digest as
the artifact-cache namespace, and each cold Tokio case also gets a fresh empty
dependency-artifact root.

`CRABRIX_RUN_COMPILER_TRANSFORMED=1` explicitly enables the O2 smoke and cold
Tokio gates. `CRABRIX_COMPILER_CANDIDATE_ARTIFACT=ArtifactFat` selects the
full-LTO variant for the ordinary candidate gates. Only these named test
folders are accepted, and missing or mismatched data fails rather than falling
back to the production compiler.
