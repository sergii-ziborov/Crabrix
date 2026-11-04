# Browser Cargo and source tree qualification — 5 November 2026

Scope: website only. Native binaries, App Review, SDK registry packages and the
remote MCP service are outside this release. Code compiles and executes in the
participant's browser Worker, never on the website server.

## Source organization

The existing sidebar width is retained. Its heading exposes New folder, New file
and Find file. A folder is created with a first file, since the shared document
stores file paths rather than empty folders. Desktop drag moves files/folders
atomically to directories or Project root. Touch and keyboard retain Move in the
item menu. Legacy format-1 shared rooms still require Copy to local for destructive
structural changes; format-2 rooms preserve stable file identities and Recovery.
Pending drags and file dialogs check file identities, refusing path reuse by peers.

External files/folders are inspected in the existing Import → Review → Apply flow;
dropping does not edit source or run code. Dropping on a file targets its parent.
Private/build/vendor directories are skipped, traversal and binary content use the
existing import checks, and enumeration/download/decompression have bounds. Rust
mod/#[path] references are not rewritten; the interface asks for a fresh Check.

## Supported Cargo profile

Packages adds normal crates.io declarations, explicitly prepares the library source
graph and updates Cargo.lock with edit access. View-only preparation never writes
room source. Archives come directly from static.crates.io, with index metadata from
the Rust project's official GitHub index mirror. Each archive is SHA-256 checked
against its registry entry both when acquired and read from browser Cache storage.
The graph is reconstructed from validated archived manifests, not trusted cache
receipt dependency/feature fields. Source and compiled caches remain device-local;
rooms and ZIP exports contain only the project's shared text/manifest/lockfile.

Supported: normal registry library dependencies, aliases, additive default/optional
features and transitive libraries, one selected version per package name. Root
edition stays the editor's selected 2021/2024; dependencies use their own edition.
Limits: 16 crates; 4 MiB compressed / 8 MiB expanded per crate; 2 MiB per archive
file; 2,048 archive entries; 32 MiB total source; 64 MiB compiled libraries. Registry
requests time out after 30 seconds. Cargo compilation has a 120-second deadline.
Existing user program limits remain 64 MiB memory, 1 MiB output and 30 seconds.

Build scripts, host procedural macros, native linking, Git/path/workspace
requirements and target-specific normal dependency tables are explicitly refused.
This is a bounded browser library profile, not a complete Cargo replacement or a
promise that arbitrary versions/features compile. Archive links/special entries,
unsafe paths, malformed checksums, oversized expansion, unsupported MSRV and graph
conflicts are refused. Dependency internals are not debug-instrumented.

Check/Run/Debug never acquire missing crate archives. Source edits do not download,
compile or execute automatically. MCP's existing execution permission still selects
only manifest-free shared-std-v1. No existing grant was broadened to Cargo.

## Verification

135 site tests and TypeScript passed. New tests exercise version requirements,
optional/weak features, transitive resolution, locked/yanked/MSRV selection, graph
cycles/conflicts, source binding, corrupt cached archives, archive path/link/bomb
refusals, drag entry/breakpoint mapping, path reuse, bounded external enumeration,
private branches and cancellation.

Actual Chromium runs locally compiled itoa 1.0.15, base64 0.22.1, hex 0.4.3 and
itertools 0.14.0 with either. Assertions covered numeric formatting, Base64, hex
and iterator joining, followed by another successful Run with the open editor's
network disabled. This establishes repeat execution in an already loaded editor,
not offline loading of the complete website. A real Debug session stepped a root
using itoa, displayed the String "42", continued and exited successfully.

Real mouse drag moved a source file into a folder and a whole nested folder into
another directory. External drop opened review and changed source only after Apply.
Fifteen layout cases (390, 820 and 1440 pixels, all five themes; phone/tablet touch)
retained sidebar width, visible controls, 40-pixel touch buttons and no horizontal
page/form/modal overflow or browser page errors.

The production-mode local build additionally passed 12 shared/negative browser
checks: two independent clients edited code and transmitted selections, stable-ID
moves preserved the entry, a pending dialog refused peer path reuse, each browser
prepared its private sources, and an observer did not start a compiler or download
packages after another participant's preparation/Run. View-only preparation worked
without edits or execution; serde's build.rs was refused; cancellation kept source
unchanged; Run with unprepared sources failed without downloading a crate. This
caught and fixed an empty-operation error when Cargo.lock already matched. Escape
now returns keyboard focus from file/project menus to their triggers.

[Local shared/negative checks](browser-cargo-2026-11-05/local-shared.json),
[layout matrix](browser-cargo-2026-11-05/local-layout.json),
[tree controls and real drag/drop](browser-cargo-2026-11-05/local-tree.json).

Publication and live shared-room results are recorded separately in the delivery
receipt after the actual candidate and public checks.
