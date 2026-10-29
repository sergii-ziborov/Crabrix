# Local TypeScript checker

This wrapper uses the original **TypeScript 5.9.3** npm compiler and all 100
standard declaration entry files. The archive is fixed by SHA-512 in `stage.py`
and SHA-256 `10e108c9cf7d5f2879053dff18515fb405abf2ccef63eaaf017d9c571687a1d3`.
The original compiler and declarations are not patched. Wrapper code is
AI-assisted. Runtime assets live in `Crabrix/Resources/TypeScriptCore`.

Reproduce in a new output directory:

```sh
python3 Vendor/CrabrixTypeScriptCore/stage.py --archive /path/typescript-5.9.3.tgz --output /path/new-assets
python3 scripts/verify_typescript_core.py
```

`stage.py` never invokes npm install hooks or executes project code. It packages
the complete upstream license/third-party notices into the offline app catalog.
Fresh staging produces a candidate manifest that blocks Release builds until
qualification is complete. The checked-in runtime passed the 184-case native/UI
phone/iPad Simulator gate and is qualified for release. Do not remove a candidate
gate to work around a failed test. See docs/offline-typescript-2026-10-29.md.

`host.js` starts a disposable Worker from the pinned compiler and `worker.js`.
Project files arrive as JSON data. The real Compiler API creates a Program and
returns pre-emit diagnostics through a virtual filesystem. No project JS,
plugins, shell, Node/Bun process, network or host filesystem executes. Check
does not fetch types. Explicit npm preparation retains original declarations,
declared @types roots, their normal dependency closure and licenses. The bundler
and TypeScript module/type resolution remain separate operations.

Input is bounded by the 2,048-file / 2 MiB-per-file / 16,000,000-byte project
policy, plus a 20 MiB JSON transport cap. Output is limited to 200 diagnostics
and 2 MiB; messages are capped at 4 KiB. Native initialization and requests each
have a 15-second deadline; cancellation, backgrounding and termination discard
the worker. JavaScript heap does **not** have a hard Wasm-style memory cap.

The initial profile supports local TS/TSX, standard ES/DOM libraries, prepared
package types/conditional type exports, local modules and browser Bundler
resolution. TypeScript parses JSONC, includes/excludes, paths and prepared/local
extends. Strict defaults can be overridden by supported tsconfig settings.
Project-reference/build state, compiler plugins, `noCheck`, external standard
library replacement and non-browser module resolution are refused explicitly.
Ordinary Run/Build keep their independent transpilation/bundling behavior.

Real Chromium Worker probes preceded native integration. Native qualification
and exact source/resource identities are recorded separately; delivery status is
in docs/app-store/release-1.1.3-build118.json. No physical-device performance is
claimed by this profile.

Primary API reference:
https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API
Original source: https://github.com/microsoft/TypeScript/tree/v5.9.3
