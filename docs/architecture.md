# Architecture

Crabrix is one iOS app with a native project workspace, Academy, Cargo resolver, and an on-device WebAssembly execution path. The bundle ID remains `com.sergiiziborov.Crabrix`; the Share Extension uses the existing App Group.

```text
Learn UI -> AcademyContentStore -> InstalledCourseRepository -> verified CoursePack files
                                   ^
signed catalog -> download cache -> CourseInstaller (staging + active index)

Project workspace -> CompilerViewModel -> Cargo resolver -> bundled rustc.wasm
                                           |                  -> bundled wasip1 sysroot
                                           -> CrabrixRuntime -> fresh WASI Store -> program.wasm

durable ProjectStore <----------- copied course starter / user edits
durable progress store <--------- lesson and build evidence
```

## Course data

`CourseBootstrap` activates the seven 1.0.1 transition packs from this binary for existing learners without network access. A clean installation activates Basics and offers the remaining catalog for download. `CourseInstaller` verifies an archive before changing the active index. `InstalledCourseRepository` checks the installed tree and converts versioned JSON DTOs to the existing lesson models. The main Learn list and lesson renderer use that repository. `CourseSession` retains an immutable repository snapshot while a lesson is open; its content version and token are carried into the compiler lesson context. Starter source is copied to a new durable `ProjectID` with course provenance and a template hash.

The transition baseline remains in the binary to preserve offline access across skipped upgrades. Public signed releases can supply later versions. Quick Practice, Code Recall, Term Train, and weak-topic navigation build session snapshots from the installed repository. The compiler receives the same verified `CourseSession` snapshot for a lesson Run. Atlas mastery records a verified repository challenge and backfills prior completed IDs when packs activate. Atlas term cards remain in the course pack but do not enter the Rust Term Train deck. Legacy Swift catalogs still support parity fixtures, some progress counters, and achievement definitions; removing them from the production target requires those remaining paths to move. See [course delivery](course-delivery.md).

## Runtime boundary

The application pins the public fork at `6f9e307c9c3069560d1a00a277dce51964309bdc`. The app's `RustcRuntime` creates a fresh WasmKit `Store` for each invocation and sets fuel, cancellation, deadline, and resource limits. Separate cached engines reserve virtual address space for compiler and student-program linear memories so allowed growth can commit pages without copying existing contents; software bounds checks and per-guest memory limits remain in force. Compiler sysroot, source, and registry inputs use read-only host preopens, while output and temporary paths remain writable. The compiler and the student's program have separate numeric policies, including hard WASI stdout/stderr write budgets. The program guest has no network import. Cache and workspace identities remain separate from course attempt identity.

## Release boundaries

The compiler/runtime/sysroot are fixed app build inputs. A CoursePack can contain editable Rust source and data-only checks, not a compiler or executable extension. User projects, notes, progress, and attempts live outside the purgeable course download cache. A signed catalog outage does not invalidate installed course files.
