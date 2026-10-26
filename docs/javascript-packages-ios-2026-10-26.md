# Offline JavaScript packages on iPhone — 26 October 2026

## Current app and this change

Crabrix already runs local HTML, CSS and browser JavaScript in an isolated
WebKit preview. It serves an immutable project snapshot, blocks external
network resources and reports web errors to Problems. Relative browser module
imports are a different capability from npm resolution or Node's APIs.

The file tree and open-file label now share type icons: JS/JSX, TS/TSX,
HTML, CSS, JSON, YAML, TOML, Markdown, SVG/images, package manifests and lock
files. The Rust entry, library, module and build-script icons are retained.
The optimized simulator app build passed. This icon change adds no JavaScript
runtime, package installation or shell-script execution.

`package.json` is currently editable JSON. Its scripts and dependency graph are
not executed. Import omits `node_modules`; a package without Rust or an HTML
entry can also fail current project discovery. TS/JSX highlighting is not
transpilation. These are actual integration tasks, not just missing command
aliases in the terminal.

## Runtime options checked

| Option | Evidence | What remains for Crabrix |
| --- | --- | --- |
| Bun | The current official README describes a Rust runtime using JavaScriptCore. Official distributions target Linux, macOS and Windows; the published package lists iOS as a future platform. | An iOS library port, runtime lifecycle, cancellation, filesystem/network boundaries and distribution qualification. A macOS arm64 executable cannot be used as an iOS library. |
| Node.js Mobile | Provides iPhone arm64 and simulator libraries. Its latest published core release is based on Node 18.20.4. | A maintained runtime baseline, controlled background execution, per-project file access, interruption and app lifecycle integration. Node 18 is EOL upstream. |
| Browser bundler | esbuild documents a browser WebAssembly API; Rolldown publishes `@rolldown/browser` with a browser export and describes a Rust JS/TS bundler. | Bundle pinned compiler assets, integrate local package/module resolution and verify operation in WebKit on iPhone. Neither has been qualified in Crabrix yet. |

Node.js Mobile's own FAQ documents unavailable process-spawning APIs and a
single runtime instance. Its iOS guide also documents that an ended runtime
cannot simply be restarted. Those constraints matter for repeated Run/Stop
in a learning IDE. Embedding the desktop Node API is itself a C++/V8/libuv
integration, not an npm installation command.

## Recommended next implementation

For frontend exercises, first implement a bounded local build pipeline:

1. Parse `package.json`: package metadata, scripts, dependencies,
   devDependencies, package type and browser/module entry information. Discover
   web package roots without selecting a nested dependency's Cargo manifest.
2. Resolve and prepare a limited, explicit npm dependency graph. Pin exact
   versions and integrity values, verify archives and keep package source
   visible. Reuse the download-progress interaction for ready, downloading,
   failed and dependent packages. New preparation needs a connection;
   completed preparation must support airplane-mode rebuilds.
3. Integrate a bundled JS/TS/JSX compiler/bundler with an immutable virtual
   project filesystem. Resolve browser package exports and relative/bare
   imports from the verified cache. Produce local HTML/CSS/JS assets for the
   existing preview. A Rust bundler is a promising candidate; actual device
   measurements should decide between it and a browser WebAssembly build.
4. Represent supported tasks explicitly. A `dev: vite` script requests a Vite
   toolchain; displaying `package.json` or opening index.html does not execute
   that script. Arbitrary shell commands, native addons, lifecycle hooks and
   server-only Node APIs need a real supported executor or a precise diagnostic.
5. Keep preparation and bundling off the SwiftUI main actor. Report stages and
   source diagnostics through the existing Output/Problems flow, with bounded
   memory and a Stop path. Preview resource policy remains separate from the
   bundler's own compiler assets.

Qualification should cover a plain JS package, a dependency imported by name,
a TS/JSX React exercise, malformed and conflicting manifests, an unavailable
Node builtin, package traversal/integrity errors, cancellation, repeated runs
and a completely offline rebuild after preparation. Source editing, keyboard
and Duo fold layout must retain their current behavior.

Full Node compatibility can be evaluated separately against a maintained
Node.js Mobile baseline. That is useful for educational `fs`/HTTP examples,
but must not be confused with the smaller frontend bundling capability.

## Distribution

The runtime/compiler must be part of the reviewed app; package source remains
viewable and editable in the educational workspace. Apple documents specific
conditions for educational code and WebKit/browser behavior. The actual
implementation and reviewer notes need to describe the supported execution
model accurately; approval is not implied by choosing Rust, Bun or Node.

## Primary sources

- [Bun README and platform list](https://github.com/oven-sh/bun/blob/main/README.md)
- [Bun's published platform support](https://www.npmjs.com/package/bun)
- [Node.js embedding API](https://nodejs.org/api/embedding.html)
- [Node.js Mobile releases](https://github.com/nodejs-mobile/nodejs-mobile/releases)
- [Node.js Mobile FAQ](https://github.com/nodejs-mobile/nodejs-mobile/blob/main/doc_mobile/FAQ.md)
- [Node.js Mobile iOS guide](https://nodejs-mobile.github.io/docs/guide/guide-ios/getting-started/)
- [Node.js release support](https://nodejs.org/en/about/previous-releases)
- [esbuild browser API](https://esbuild.github.io/api/#browser)
- [Rolldown browser package](https://github.com/rolldown/rolldown/blob/main/packages/browser/package.json)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
