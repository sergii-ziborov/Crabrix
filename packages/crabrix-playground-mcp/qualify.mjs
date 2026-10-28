import { build } from "esbuild";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.dirname(fileURLToPath(import.meta.url));
await build({ absWorkingDir: root, entryPoints: ["test/local-probe.ts", "test/cross-client-probe.ts", "test/public-probe.ts"], outdir: "../../build/playground-mcp-20261028/probes", outExtension: { ".js": ".mjs" }, bundle: true, platform: "node", target: "node22", format: "esm",
  banner: { js: 'import { createRequire as __crabrixCreateRequire } from "node:module"; const require = __crabrixCreateRequire(import.meta.url);' } });
