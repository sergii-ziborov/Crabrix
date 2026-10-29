import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const require = createRequire(path.join(root, "packages/crabrix-playground-mcp/package.json"));
const { build } = require("esbuild");
const output = path.join(root, "build/playground-native-runtime");
await mkdir(output, { recursive: true });
function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { cwd: root, stdio: "inherit" });
    child.once("error", reject);
    child.once("exit", code => code === 0 ? resolve() : reject(new Error(`Native runtime qualification exited ${code}`)));
  });
}
await run("bash", ["scripts/probes/playground/build-native-peer.sh"]);
const banner = { js: 'import { createRequire as __crabrixCreateRequire } from "node:module"; const require = __crabrixCreateRequire(import.meta.url);' };
for (const [source, name] of [["scripts/probes/playground/runtime-relay.ts", "relay"], ["packages/crabrix-playground-mcp/test/native-runtime-probe.ts", "probe"]]) {
  await build({ absWorkingDir: root, entryPoints: [source], outfile: path.join(output, name + ".mjs"), bundle: true, platform: "node", format: "esm", target: "node22", banner });
}
const relay = spawn(process.execPath, [path.join(output, "relay.mjs")], { cwd: root, stdio: ["ignore", "pipe", "inherit"] });
try {
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Loopback relay startup timed out")), 10_000);
    relay.once("error", error => { clearTimeout(timeout); reject(error); });
    relay.once("exit", () => { clearTimeout(timeout); reject(new Error("Loopback relay unavailable; port 3398 may already be in use")); });
    relay.stdout.once("data", bytes => { clearTimeout(timeout); bytes.toString().includes("runtime-relay-ready") ? resolve() : reject(new Error("Unexpected loopback relay response")); });
  });
  await run(process.execPath, [path.join(output, "probe.mjs")]);
} finally {
  if (relay.exitCode === null) relay.kill("SIGTERM");
  await Promise.race([new Promise(resolve => relay.once("exit", resolve)), new Promise(resolve => setTimeout(resolve, 2_000))]);
  if (relay.exitCode === null && relay.signalCode === null) relay.kill("SIGKILL");
}
