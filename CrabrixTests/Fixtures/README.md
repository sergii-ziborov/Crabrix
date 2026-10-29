# Browser build fixture

`BrowserReactProject.json` is an editable browser project prepared from the public
npm registry: React 19.2.0, React DOM 19.2.0, Scheduler 0.27.0, clsx 2.1.1, Zustand 5.0.8, TanStack React Query/Query Core 5.90.5 and Zod 4.1.12.
It contains only the imported original source modules, package manifests and their
upstream LICENSE files. Their original licenses apply; no test double replaces
these libraries. `crabrix-web.lock.json` records the exact archive URLs and SRI
hashes. The test starts with an absent archive cache and no package preparation.
The WebKit test clicks the actual React counter, verifies CSS and rejects a
network fetch. No library is bundled into the production app as a starter.

The dashboard compiles 133 modules from eight npm packages; it validates local data,
queries an in-memory list, and updates shared state when its counter is clicked.

`BrowserReactTypes.json` is a delta over that original fixture, prepared from the
same original npm packages plus `@types/react` 19.2.2, `@types/react-dom` 19.2.2
and csstype 3.1.3. It retains their original declaration sources and licenses,
exact archive URLs/SRI, own runtime-package declarations and updated manifests.
The combined editable snapshot contains 613 files / 3,750,639 UTF-8 bytes. Its
11 prepared package roots include declaration-only packages; the runtime bundle
still uses the same eight packages and 133 modules. Native qualification invokes
the real checker with an absent package archive cache, then introduces a real
Zod-inferred assignment error. This fixture also exercises DefinitelyTyped's
single legacy tar root without widening the archive's path permissions.
