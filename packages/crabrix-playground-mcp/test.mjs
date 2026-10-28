import { build } from "esbuild";
import { spawnSync } from "node:child_process";
import { readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.dirname(fileURLToPath(import.meta.url));
const rebuilt = spawnSync(process.execPath, ["build.mjs"], { cwd: root, stdio: "inherit" });
if (rebuilt.status !== 0) process.exit(rebuilt.status ?? 1);
const files = (await readdir(path.join(root, "test"))).filter(name => name.endsWith(".test.ts"));
const outdir = path.resolve(root, "../../build/playground-mcp-20261028/tests");
await build({ absWorkingDir: root, entryPoints: files.map(name => "test/" + name), outdir, outExtension: { ".js": ".mjs" }, bundle: true, platform: "node", format: "esm", target: "node22",
  banner: { js: 'import { createRequire as __crabrixCreateRequire } from "node:module"; const require = __crabrixCreateRequire(import.meta.url);' } });
const run = spawnSync(process.execPath, ["--test", ...files.map(name => path.join(outdir, name.replace(/\.ts$/, ".mjs")))], { stdio: "inherit" });
process.exitCode = run.status ?? 1;
