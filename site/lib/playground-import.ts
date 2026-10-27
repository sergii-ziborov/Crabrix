import { PLAYGROUND_LIMITS, validatePlaygroundDocument, type PlaygroundDocument } from "./playground-document";

async function githubJSON(url: string, maximum = 2_000_000) {
  const response = await fetch(url, { credentials: "omit", redirect: "error", headers: { Accept: "application/vnd.github+json" }, signal: AbortSignal.timeout(20_000) });
  if (!response.ok) throw new Error(response.status === 403 ? "GitHub's anonymous request limit was reached. Download a Rust file and import it locally, or retry later." : `GitHub could not read this public source (${response.status}).`);
  if (!response.body) throw new Error("GitHub returned no source.");
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let total = 0;
  try {
    while (true) { const { done, value } = await reader.read(); if (done) break; total += value.length; if (total > maximum) throw new Error("This repository listing is too large. Import a smaller source folder."); chunks.push(value); }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(total); let at = 0; for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; }
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}
const decode = (value: string) => {
  if (value.length > 100_000) throw new Error("Source file exceeds 64 KiB.");
  const text = atob(value.replace(/\s/g, ""));
  return new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(text, char => char.charCodeAt(0)));
};

/** All requests go straight from the user's browser to the fixed GitHub API.
 * The Crabrix server never fetches arbitrary URLs or retains imported source. */
export async function importPublicSource(raw: string, folderInput = ""): Promise<PlaygroundDocument> {
  const url = new URL(raw.trim());
  if (url.protocol !== "https:" || url.username || url.password || url.port || !["github.com", "gist.github.com", "play.rust-lang.org"].includes(url.hostname)) throw new Error("Use a public HTTPS GitHub repository, gist or Rust Playground link.");
  const folder = folderInput.trim().replace(/^\/+|\/+$/g, "");
  if (folder.split("/").some(part => part === ".." || part === ".") || folder.includes("\\")) throw new Error("Use a repository-relative source folder.");
  const gist = url.hostname === "play.rust-lang.org" ? url.searchParams.get("gist") : url.hostname === "gist.github.com" ? url.pathname.split("/").filter(Boolean).at(-1) : null;
  if (gist) {
    if (!/^[a-f0-9]{20,64}$/i.test(gist)) throw new Error("Invalid public gist identifier.");
    const value = await githubJSON(`https://api.github.com/gists/${gist}`);
    const files: Record<string, string> = Object.create(null);
    for (const [name, item] of Object.entries(value.files ?? {}) as [string, { size: number; content: string; truncated?: boolean }][]) {
      if (!/\.(rs|toml|md|txt)$/.test(name)) continue;
      if (item.truncated || item.size > PLAYGROUND_LIMITS.fileBytes || typeof item.content !== "string") throw new Error("This gist contains a truncated or oversized file. Import a smaller source set.");
      files[name] = item.content;
    }
    const entryFile = files["main.rs"] !== undefined ? "main.rs" : Object.keys(files).find(path => path.endsWith(".rs"));
    return validatePlaygroundDocument({ schemaVersion: 1, name: "imported-gist", edition: "2024", entryFile, files, origin: { url: url.toString() } });
  }
  if (url.hostname !== "github.com") throw new Error("The Rust Playground link must contain a public gist.");
  const parts = url.pathname.split("/").filter(Boolean), owner = parts[0], repo = parts[1]?.replace(/\.git$/, "");
  if (!owner || !repo || !/^[a-z0-9_.-]+$/i.test(owner) || !/^[a-z0-9_.-]+$/i.test(repo)) throw new Error("Use a GitHub repository URL.");
  const base = `https://api.github.com/repos/${owner}/${repo}`;
  const repository = await githubJSON(base, 100_000);
  let ref = repository.default_branch;
  let subfolder = folder;
  if (parts[2] === "tree" && parts[3]) { ref = parts[3]; subfolder = folder || parts.slice(4).join("/"); }
  else if (parts.length > 2) throw new Error("Use the repository or its source-folder /tree/ link.");
  const commit = (await githubJSON(`${base}/commits/${encodeURIComponent(ref)}`, 1_000_000)).sha;
  if (!/^[a-f0-9]{40}$/.test(commit)) throw new Error("GitHub did not resolve a source revision.");
  const tree = await githubJSON(`${base}/git/trees/${commit}?recursive=1`);
  if (tree.truncated) throw new Error("GitHub truncated this repository. Import a smaller source repository.");
  const prefix = subfolder ? subfolder + "/" : "";
  const entries = (tree.tree ?? []).filter((item: { path: string; type: string }) => item.type === "blob" && item.path.startsWith(prefix))
    .map((item: { path: string; size: number; sha: string }) => ({ ...item, path: item.path.slice(prefix.length) }))
    .filter((item: { path: string }) => /\.rs$|^(Cargo\.(toml|lock)|README\.md|LICENSE|NOTICE)$/.test(item.path) && !item.path.split("/").some(part => ["target", "vendor", "node_modules", ".git", ".github", ".cargo"].includes(part)));
  if (entries.length > PLAYGROUND_LIMITS.files) throw new Error(`This source set has ${entries.length} files. Choose a smaller folder (maximum 16 files).`);
  if (entries.some((item: { size: number }) => item.size > 65536) || entries.reduce((n: number, item: { size: number }) => n + item.size, 0) > 131072) throw new Error("Choose a smaller source folder: 64 KiB per file, 128 KiB total.");
  const files: Record<string, string> = Object.create(null);
  // Four parallel requests avoid a long serial import without flooding GitHub.
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(4, entries.length) }, async () => {
    while (cursor < entries.length) { const item = entries[cursor++]; const blob = await githubJSON(`${base}/git/blobs/${item.sha}`, 100_000); if (blob.encoding !== "base64") throw new Error("GitHub did not supply UTF-8 source."); files[item.path] = decode(blob.content); }
  }));
  const entryFile = ["src/main.rs", "main.rs", "src/lib.rs", "lib.rs"].find(path => path in files) ?? Object.keys(files).find(path => path.endsWith(".rs"));
  const edition = files["Cargo.toml"]?.match(/\bedition\s*=\s*["'](2021|2024)["']/)?.[1] ?? "2024";
  return validatePlaygroundDocument({ schemaVersion: 1, name: repo, entryFile, files, edition, origin: { url: url.toString(), commit } });
}
