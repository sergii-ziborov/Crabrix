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

`CourseBootstrap` activates the seven 1.0.1 transition packs from this binary for existing learners without network access. A clean installation activates no courses and offers seven courses plus the separate Code Examples pack from the signed catalog for individual download. `CourseInstaller` verifies an archive before changing the active index. `InstalledCourseRepository` checks the installed tree and converts versioned JSON DTOs to the existing lesson models. The Learn course library, open Code Examples path, and lesson renderer use that repository. Every example is available immediately after its pack is installed; its read-first detail shows an overview and source preview, without lesson answers or progression. `CourseSession` retains an immutable repository snapshot while a lesson is open; its content version and token are carried into the compiler lesson context. Starter or example source and its README are copied to a new durable `ProjectID` with course provenance and a template hash.

The transition baseline remains in the binary to preserve offline access across skipped upgrades. Public signed releases can supply later versions. Quick Practice, Code Recall, Term Train, and weak-topic navigation build session snapshots from the installed repository. The compiler receives the same verified `CourseSession` snapshot for a lesson Run. Atlas mastery records a verified repository challenge and backfills prior completed IDs when packs activate. Atlas term cards remain in the course pack but do not enter the Rust Term Train deck. The old Swift catalogs compile only in Debug or a test build with `CRABRIX_LEGACY_FIXTURES`; production Release uses the installed repository. The historical exporter materializes its exact source commit from Git. Decoding aggregate progress from the old app uses the immutable baseline count of 142 Rust lessons, never the latest network catalog. See [course delivery](course-delivery.md).

## Runtime boundary

The development application pins the public fork at `d996f0d11dff54734b5670d58062e22c6e01f949`. The app's `RustcRuntime` creates a fresh WasmKit `Store` for each invocation and sets fuel, cancellation, deadline, and resource limits. The execution thread samples the external cancellation/deadline probe once per 64 fuel regions, starting at the first charge; host calls and bulk memory/table operations remain directly guarded. Separate cached engines reserve virtual address space for compiler and student-program linear memories so allowed growth can commit pages without copying existing contents; software bounds checks and per-guest memory limits remain in force. Compiler sysroot, source, and registry inputs use read-only host preopens, while output and temporary paths remain writable. The compiler and the student's program have separate numeric policies, including hard WASI stdout/stderr write budgets. The program guest has no network import. Cache and workspace identities remain separate from course attempt identity.

## Release boundaries

The compiler/runtime/sysroot are fixed app build inputs. A CoursePack can contain editable Rust source and data-only checks, not a compiler or executable extension. User projects, notes, progress, and attempts live outside the purgeable course download cache. A signed catalog outage does not invalidate installed course files.
