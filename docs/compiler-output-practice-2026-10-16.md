# Build failure routing and fitted practice

## Implementation

`CompilationResult.problemDiagnostics` presents build/setup/runtime failures
that lack rustc JSON as unlocated Problems entries. Raw rustc diagnostics
remain separate: Cargo errors cannot become source-edit or lesson-repair
reward evidence. User cancellation is not presented as a compiler error.
Warnings cannot hide an unlocated failure. The Problems badge uses the same
collection as its list.

Output no longer contains a status/Run card or compiler diagnostics. Program
stdout, visual output, runtime stderr, lesson hints and learning continuation
remain. The primary workspace Run/Stop control is retained.

The ordinary editor's toolchain strip identifies the current project. iPad's
primary Check/Run controls are restored beside search and project controls;
its narrower header keeps the controls while reducing brand/navigation width.
Duo's established keyboard and fold geometry are preserved.

Arrange Code uses a native reorder list with a fixed height and scrolling
disabled. The exercise fits a vertical layout or puts instructions/actions
beside code in compact landscape. Larger accessibility text has a single
page-scroll fallback; there is no separately scrolling reorder list.

## Reported project

The reported `weather-station` program uses only Rust's standard library.
Its unused plain `syn` dependency enabled unsupported host procedural-macro
features. Cargo.toml and Cargo.lock were repaired on the connected iPhone,
with the original project backed up first. A later device read verified both
Cargo files and confirmed that the Rust source was unchanged.

The exact sensor program passed a bundled WASI compiler run, printing
`average 21.8 C` and `driest  52%`. Existing explicit parser-only syn repair
remains available for projects that actually use syn.

## Verification

Manual Xcode Cloud run 61 and the local iPhone gate each passed all 12 native
checks, including the real weather-station compilation. Cloud passed those
native checks on iPhone 13 mini and iPad Pro 13-inch (M4). Its initial UI checks
exposed a fresh-install test assumption, an incorrect assertion about the
primary Run button, and the missing iPad commands. The test assumptions and
iPad controls were corrected. The final UI and archive results are recorded
in the release manifest; the initial combined run is not reported as passing.

All changes preserve build 60's Term Train, app-unlock, progress, Academy and
Duo fixes. The current compiler, package resolver, Problems/Output and arrange
implementation files are identical to the versions whose native checks ran
in 61. Later runtime changes are confined to the iPad header.

The final SDK 27.1 app product has the same runtime sources as archive 68.
Local native UI testing passed both methods on iPhone 13 mini. iPad passed
native reorder, the fitted portrait/landscape layouts, and the corrected
compiler/Output check. The latter waits for automatic diagnostic advice to
finish before switching views. Successful captures are saved under
[screenshots/workspace-qa-2026-10-16](screenshots/workspace-qa-2026-10-16/).
The phone kept its portrait orientation after the rotation request; the iPad
captures demonstrate the landscape layout.

Build 68 is VALID and in TestFlight Internal QA. The App Store version and
two custom product pages are WAITING_FOR_REVIEW. See the
[release manifest](releases/1.1.1-build68.json) for exact identities and scope.
