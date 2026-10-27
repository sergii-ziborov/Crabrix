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
