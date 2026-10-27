# Browser package builds — 27 October 2026

## Implemented flow

An HTML browser project uses the bundled browser builder through Run and Check.
A package.json-only project opens for inspection and receives an actionable HTML
entry requirement. Rust/Cargo entries retain their existing compiler path.
Rust-generated module sites are postprocessed by the same offline browser builder;
binary assets already captured from the generator are retained within the same
preview budget.

The existing terminal exposes these operations:

| Command | Operation |
| --- | --- |
| `npm install` | Explicitly prepare the imported browser dependency graph |
| `npm ci` | Prepare from matching npm lockfile v2/v3 entries with SRI verification |
| `npm run dev`, `npm start`, `npm run start` | Build locally and open Web Preview |
| `npm run build`, `npm run check` | Build locally without opening Web Preview |
| `npm run` | Show declared scripts and the supported command mapping |

Use `cd web` for a nested browser app. Root-relative module/asset paths refer
to that browser app, and preparation retains neighboring projects' dependency
sources. These operations do not execute package
scripts, Vite, npm lifecycle hooks or arbitrary host processes. The terminal's
existing horizontal command chips, keyboard input, Hide/Show behavior and dock
layout are retained. The normal Run button automatically selects the browser
path for imported HTML/package projects; it never downloads browser dependencies.

## Offline source and integrity

The bundled Babel standalone 8.0.9 and node-semver 7.8.5 are trusted compiler
resources. Their public npm archives and SRI hashes are pinned in
`scripts/web-compiler-source-lock.json`, alongside the generated runtime digest.
`scripts/prepare_web_compiler.py` reproduces the runtime from those archives.
Project source is passed as text to a serial JavaScriptCore parser/transformer.
Project plugins and project programs are never evaluated in that compiler context.
Generated browser code runs only in the existing WebKit preview.

Explicit package preparation uses public npm HTTPS registry requests, checks
archive integrity and extracts bounded regular source files with the existing
safe archive reader. Redirects to another host, path traversal, source path
collisions and unbounded responses are rejected. Package identity must match its
archive manifest. Progress uses the existing package sheet and Output stages. Its final graph
also records dependencies on shared packages that were resolved earlier.

Only imported original modules, needed package manifests and license/notice texts
are retained as editable `node_modules` project files. This includes nested
package dependencies and lowercase license file names. Saved projects retain
these sources on reopening; unprepared host node_modules trees remain excluded
from ordinary imports. Browser Run/Check do not consult the package registry or
require the archive cache. Adding a previously unused import may require another
explicit preparation. Edits to already prepared source are retained for unchanged
package versions during install; ci intentionally restores the locked sources.

`crabrix-web.lock.json` records this selected browser graph and exact root
manifest. It does not pretend to be a complete host npm installation. npm ci
requires the original package-lock.json, matching root dependency declarations,
and resolved/integrity entries for the imported packages. Download/preparation
results are applied transactionally only while the captured project revision is
current. Failed, canceled or stale preparation cannot overwrite newer source.

## Capabilities and boundaries

Supported: browser package export conditions and subpaths, registry semver
ranges, ESM/CommonJS graphs, cycles, JavaScript, TypeScript syntax, JSX/TSX,
JSON, regular CSS imports and local text/SVG assets. NODE_ENV is production for
browser dependency transforms. An imported browser module may use ordinary
browser APIs, subject to the existing WebKit policy.

Not supplied: Node/Bun, server listeners, native addons, arbitrary package scripts,
build plugins, private/git/workspace dependency resolution, CSS Modules,
import.meta.glob, top-level await or full TypeScript type checking. Use one module
script entry and import other modules from it. npm package source preparation
retains UTF-8 source assets; binary package asset pipelines need a local static
export. Runtime locations can refer to the generated bundle; syntax diagnostics
retain the editable source file and location in Problems.

Existing limits remain: 2,048 editable project files, 2 MiB per source file,
16 MB source snapshot; 256 preview assets, 2 MiB per asset, 8 MiB preview total.
Package preparation has separate compressed/archive/temporary-source limits.
The existing preview CSP, external-network blocking and absent native/shell
bridge are unchanged. Compiler acceleration, the 2,048 Cargo-package ceiling,
signed Rust toolchain, runtime pin and editor/Duo geometry are unchanged.

## Verification

- Host JavaScript harness: 29 semantic checks using the actual pinned compiler
  resources, including export conditions, import/require distinctions, namespace
  reexports, production branches, JSON/raw assets, CSS imports, path errors,
  unsupported server/dynamic constructs and the full real-library fixture.
- Actual macOS JavaScriptCore prepared React/React DOM/Scheduler/clsx, then
  reproduced the preview from editable source with an absent archive cache.
- A larger real dashboard prepared **133 modules from eight npm packages**:
  React 19.2.0, React DOM 19.2.0, Scheduler 0.27.0, Zustand 5.0.8, TanStack
  React Query and Query Core 5.90.5, Zod 4.1.12 and clsx 2.1.1. A subsequent
  source-only build reproduced the snapshot. A separate frozen preparation
  used an npm v3 lock with the same real archive URLs and SRI pins.
- The combined native release gate passed **47 tests, zero failures**, including
  project imports, licenses, browser integration, terminal and keyboard checks.
- iOS Simulator tests execute the actual dashboard in WebKit, click its React
  counter, verify applied CSS, and confirm an external fetch is blocked.
  The model's Run and npm-build paths, saved-source reopening, lock drift,
  stale-result rejection, terminal dispatch and registry integrity/origins are
  covered by hosted tests.
- Existing Code-to-Terminal and repeated keyboard Hide/Show regression tests
  pass with the existing tab and command-bar geometry.
- Native and website license texts are synchronized. Privacy discloses explicit
  npm registry requests; source, answers and learning progress are not uploaded.

The result bundles and detailed logs are under
`build/browser-packages-20261027/`. The current dashboard fixture is
`CrabrixTests/Fixtures/BrowserReactProject.json`; its original dependency source
and license texts are preserved. The downloadable starter under
`docs/examples/offline-browser-dashboard/` contains only the app's own source
and dependency declarations, with its own MIT license.

These are Simulator/macOS checks. No physical-iPhone npm timing or universal
framework compatibility is claimed. The source-only dashboard screenshot is an
actual WebKit capture, not a mockup of the native editor controls.

## Review context

The implementation keeps downloaded project code visible and editable and runs
browser projects in WebKit. This is designed for the existing educational code
workflow. The [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
sections 2.5.2 and 2.5.6 describe the relevant educational-code and WebKit
requirements; actual approval remains Apple's decision. Reviewer notes must
explicitly describe the new package-preparation capability and command mapping.
