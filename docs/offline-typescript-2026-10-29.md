# Offline TypeScript and source-bound preflight — 29 October 2026

Signed **1.1.3 (118)** from `a187a4c9394ecaf2f17798008fd0d44f8edf1ddb`
is **VALID / IN_BETA_TESTING** and selected for App Review, **WAITING_FOR_REVIEW**,
with manual publication. [Delivery receipt](app-store/release-1.1.3-build118.json).
The public guide, exact original phone/iPad captures, original notices and
capability record are published. App Store 1.1.2 (103) remains separate until
Apple approves and the new version is released.

## Actual TypeScript diagnostics

The original TypeScript **5.9.3** compiler and **100** upstream ES/DOM declaration
libraries are bundled with the app. A disposable WebKit Worker calls the real
Compiler API over a read-only virtual filesystem. Project text is compiler
input: project JavaScript, Node/Bun, lifecycle scripts, plugins and shell commands
do not execute during Check. No server compiles or runs the project.

Check and terminal `npm run check` / `npm run typecheck` analyze TS/TSX/MTS/CTS.
Diagnostics retain their TS codes, UTF-16 source positions and current file.
Problems opens the corresponding source without replacing it. Browser errors
use web-specific help; optional model advice is explicit and does not lock Run.
Ordinary Run/Build remain independent browser transpilation/bundling operations.
A successful preview build does not establish that JavaScript ran successfully,
and a successful Run does not establish that TypeScript checking passed.

JSONC tsconfig, include/exclude, local paths, prepared/local extends and supported
compiler settings are parsed by TypeScript itself. Defaults are strict browser
ES2024/DOM, ESNext/Bundler and react-jsx; supported project settings may override
them. Project references, plugins, composite/incremental state, noCheck, external
standard-library replacement and non-browser module resolution are refused with
an explanation. They do not silently fall back to a successful syntax-only Check.

## Explicit type preparation

`npm install` / `npm ci` explicitly prepare the supported browser source graph.
Original declarations from runtime packages, declared root @types dependencies,
their normal dependency closure and original licenses are retained in editable
node_modules files with verified archive integrity. Type-only packages need no
JavaScript entry. Exactly one archive root is accepted: package/, or the exact
legacy unscoped root for an @types/name archive; mixed or unrelated roots fail.

Check and Run do not download missing types or packages. Missing declarations,
missing modules, configuration failures, type errors and runtime console errors
remain distinct. Install the declared types explicitly before going offline.
The prepared React dashboard uses 11 retained package roots / 613 files /
3,750,639 UTF-8 bytes; the runtime builder visits eight packages / 133 modules.
React, React DOM, Zustand, TanStack Query and Zod check using actual original
package declarations. An intentionally wrong Zod-inferred value produces TS2322.
These counts describe this fixture, not a universal framework guarantee.

## Limits and cancellation

The editable tree retains 2,048 files, 2 MiB UTF-8 per file and 16,000,000 bytes.
The checker transports at most 20 MiB JSON, returns at most 200 diagnostics in
2 MiB and caps each message at 4 KiB. Initialization and each request have separate
15-second deadlines. Stop, source changes, backgrounding and WebContent termination
cancel the operation and discard the Worker; subsequent Check can start cleanly.
JavaScript heap has no hard Wasm-style memory cap. The native app handles a
terminated WebContent process as a failed check, never as success.

## Current-source evidence

Files → Project preflight inspects the entry, target, edition, exact current
Cargo versions/features/fingerprints and limits outside the UI actor. It neither
compiles nor downloads. Check/Build/Run/Debug evidence binds source generation,
entry, opaque resources and the combined bundled compiler identity. The operation
kind and actual browser entry are recorded: npm --prefix web in a Rust project
cannot verify Rust Check. Older records with missing context stay unverified.
Only an actual successful checker result with the pinned TypeScript version
verifies type checking. Package preparation and preview construction do not.

Known profile requirements are checked early. A previous compiler failure stays
retryable rather than becoming a permanent platform verdict. Reviewed Cargo
feature suggestions preserve the original manifest in the editable project and
refuse stale/ABA or explicit custom-feature profiles. Full structured failure
classification remains open under COMPAT-01.

## Qualification and provenance

The receipt records source commit, exact runtime hashes, all final result bundles
and native/UI device identities. **184/184 passed, zero failures/skips:** 89 native cases and three UI routes on
each phone/iPad Simulator. [Receipt](offline-typescript-qualification-2026-10-29.json).
Qualification source is `3c084dbe0892f073224688053e6fa520517018a2`; delivery source `a187a4c9394ecaf2f17798008fd0d44f8edf1ddb`
adds corrected AI completion-prompt/terminal-help text and canonical website
notice generation/bootstrap validation. Cloud 117 stopped on stale website
notices before compilation; its logs are retained. Full local bootstrap passes
for the replacement source. Runtime resources and operation routing are unchanged. Signed compilation
and resource checks qualify that separate delivery. The matrix includes real WebKit checks,
explicit registry type preparation followed by cache removal/offline checking,
background/Stop recovery, source-bound evidence, Rust symbols/import Apply/Undo,
String/Vec/struct/Tokio Debug, browser runtime behavior and keyboard regressions.
Three UI routes run on each phone/iPad Simulator in Amber Circuit/Cyberpunk.
Original unedited captures and receipts accompany the release. No physical-device
speed, hard JS heap limit, native Node runtime or backend execution is claimed.

The TypeScript npm archive is pinned by SRI and SHA-256
10e108c9cf7d5f2879053dff18515fb405abf2ccef63eaaf017d9c571687a1d3.
Compiler/library bytes are unmodified; all original upstream license and
third-party notice texts ship in the offline catalog and notice archive.
Wrapper source: Vendor/CrabrixTypeScriptCore; verifier:
scripts/verify_typescript_core.py. The initial failed config-default/legacy-root
and optional-AI test runs remain in build/typescript-checker-20261029; final
source-bound results supersede their preliminary expectations.
