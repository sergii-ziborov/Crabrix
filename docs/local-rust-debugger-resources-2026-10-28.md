# Included resources and compact breakpoint taps — 28 October 2026

## Report and fixes

The built-in Rust + Web project failed before compilation with “Debug leaves
compile-time source introspection to normal Run”. The shared instrumenter treated
`include_str!` and `include_bytes!` as unsupported source-position macros. These
resource macros now retain their original HTML, CSS, JavaScript and text bytes.
Both the browser Worker and the app's bundled parser use this fix.

Including an instrumented Rust file as data needs extra care. Literal relative
paths and `/work/` paths now point to an untouched text sidecar when necessary.
Sidecars cannot overwrite project files, are deduplicated and have a preparation
budget. The editable source is never changed. Raw strings, Rust path escapes and
multiline source line coordinates are covered. Computed resource paths remain an
explicit unsupported Debug form; executable `include!` and `column!` retain the
existing normal-Run fallback. Build scripts stay outside source instrumentation.

The phone UI test also exposed a separate problem: a transparent 28-point Files
swipe overlay intercepted taps in the breakpoint gutter before Debug started.
Removing that redundant overlay restores taps. The existing parent edge-swipe
gesture still opens Files. Editor, Duo, dock and keyboard geometry are unchanged.

## Verification

- Eight native host tests passed with the actual offline compiler, including the
  exact Rust + Web generator, breakpoint reason at `src/main.rs:7`, generated
  HTML/CSS/JS byte equality with Run, original Rust source-as-data, aggregate
  values, Tokio current-thread async polling and Stop recovery.
- Twenty-three real browser compiler normal-versus-Debug semantic comparisons
  passed, plus two explicit safe fallbacks. Three new comparisons exercise
  included web content, original Rust source bytes and multiline raw paths.
- Thirty-four site tests, type checking and the production build passed.
- The final native UI flow passed on both iPhone and iPad Simulators: set the
  breakpoint before Debug, Continue to line 7, Step over, finish, and click the
  generated page's JavaScript counter. The phone test also opens Files with the
  existing edge swipe. A separate real typing test passed on the phone.
- Actual Chromium UI probes passed on the packaged local site and public HTTPS
  site. They inspected a real local value, hit a breakpoint, stepped, preserved
  editable source and matched normal Run output. Network access was blocked
  after toolchain acquisition for subsequent compilation and execution.

The initial phone UI attempts failed to set the breakpoint; those failures led
to the overlay fix and are retained in the local results. The final runs above
include the stronger single-tap assertion. Simulator results do not constitute
physical iPhone timing or physical Universal Link qualification.

The browser's existing text-only file policy and package boundaries are
unchanged. Native tests use the actual HTML/CSS/JS project; browser tests use
allowed `.txt` resource files containing that content. No backend execution,
new entitlement, package download during Run or remote compiler was added.

Machine-readable results and deployment identity are in
`docs/local-rust-debugger-resources-2026-10-28.json`. Raw logs, xcresults and
screenshots are under ignored `build/debugger-resources-20261028/`.


## Delivery

The website fix is published on Hetzner and passed the public HTTPS browser
probe. App **1.1.3 (110)** completed Xcode Cloud Build and Archive successfully.
The signed App Store package is verified, Apple processing is VALID, TestFlight
Internal QA is IN_BETA_TESTING, and the selected build 110 submission is
WAITING_FOR_REVIEW with manual publication. Store metadata, reviewer notes and
beta instructions were updated and read back; all 19 inherited screenshots are
complete. See `docs/app-store/release-1.1.3-build110.json`.
