import { build } from "esbuild";
import { mkdir, readFile, writeFile, chmod } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
const root = path.dirname(fileURLToPath(import.meta.url));
const result = await build({ absWorkingDir: root, entryPoints: ["src/cli.ts"], outfile: "dist/cli.mjs", bundle: true, platform: "node", target: "node22", format: "esm", metafile: true,
  // A few SDK dependencies still use CJS builtins. createRequire resolves only
  // bundled dependencies/builtins, never project-controlled module paths.
  banner: { js: 'import { createRequire as __crabrixCreateRequire } from "node:module"; const require = __crabrixCreateRequire(import.meta.url);' } });
await chmod(path.join(root, "dist/cli.mjs"), 0o755);
const packages = new Map();
for (const input of Object.keys(result.metafile.inputs)) {
  if (!input.includes("node_modules")) continue;
  let directory = path.dirname(path.resolve(root, input));
  while (directory !== path.dirname(directory)) {
    try {
      const info = JSON.parse(await readFile(path.join(directory, "package.json"), "utf8"));
      if (info.name && info.version) { packages.set(info.name + "@" + info.version, { directory, info }); break; }
    } catch {}
    directory = path.dirname(directory);
  }
}
const notices = ["Crabrix Playground MCP — third-party components\nOriginal component licenses apply independently of the Crabrix bridge license.\n"];
for (const [name, { directory, info }] of [...packages].sort(([a], [b]) => a.localeCompare(b))) {
  let license;
  for (const file of ["LICENSE", "LICENSE.txt", "LICENSE.md", "license", "license.md"]) { try { license = await readFile(path.join(directory, file), "utf8"); break; } catch {} }
  if (!license) throw new Error("Missing license text: " + name);
  notices.push(`\n${"=".repeat(72)}\n${name} · ${info.license ?? "see original text"}\n${license}`);
  for (const file of ["NOTICE", "NOTICE.txt", "NOTICE.md"]) { try { notices.push(await readFile(path.join(directory, file), "utf8")); } catch {} }
}
await mkdir(path.join(root, "dist"), { recursive: true });
await writeFile(path.join(root, "ThirdPartyNotices.txt"), notices.join("\n"));
await writeFile(path.join(root, "dist/components.json"), JSON.stringify([...packages].map(([name, { info }]) => ({ name, license: info.license })), null, 2) + "\n");
const sources = {};
for (const file of ["src/cli.ts", "src/server.ts", "src/room.ts", "package.json", "LICENSE", "../../site/lib/playground-collab.ts", "../../site/lib/playground-presence.ts", "../../site/lib/playground-document.ts", "../../site/lib/playground-crypto.ts", "../../site/lib/playground-session.ts"]) {
  sources[file.startsWith("../../") ? file.slice(6) : "packages/crabrix-playground-mcp/" + file] = createHash("sha256").update(await readFile(path.resolve(root, file))).digest("hex");
}
await writeFile(path.join(root, "dist/source-manifest.json"), JSON.stringify({ version: JSON.parse(await readFile(path.join(root, "package.json"), "utf8")).version, sourceSHA256: sources }, null, 2) + "\n");
