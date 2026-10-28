import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.dirname(fileURLToPath(import.meta.url));
const repository = path.resolve(root, "../.."), version = JSON.parse(readFileSync(path.join(root, "package.json"))).version;
execFileSync(process.execPath, ["build.mjs"], { cwd: root, stdio: "inherit" });
const out = path.join(repository, "site/public/downloads"); mkdirSync(out, { recursive: true });
const name = `crabrix-playground-mcp-${version}`, archive = path.join(out, name + ".tgz");
execFileSync("pnpm", ["pack", "--out", archive], { cwd: root, stdio: "pipe" });
for (const [source, destination] of [["ThirdPartyNotices.txt", "NOTICES"], ["LICENSE", "LICENSE"]]) copyFileSync(path.join(root, source), path.join(out, name + "-" + destination + ".txt"));
const bytes = statSync(archive).size;
const manifest = { version, url: "/downloads/" + name + ".tgz", bytes, sizeLabel: Math.round(bytes / 1024) + " KiB", sha256: createHash("sha256").update(readFileSync(archive)).digest("hex"),
  noticesURL: "/downloads/" + name + "-NOTICES.txt", licenseURL: "/downloads/" + name + "-LICENSE.txt" };
writeFileSync(path.join(repository, "site/lib/mcp-download.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log(JSON.stringify(manifest));
