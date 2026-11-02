import { unzipSync } from "fflate";
import { PLAYGROUND_LIMITS, validatePlaygroundDocument } from "./playground-document.ts";
import type { ImportCandidate, ImportInspection } from "./playground-import-plan.ts";

const forbidden = new Set(["node_modules", "target", ".git", ".github", ".cargo", "vendor"]);
const importable = /(?:\.rs|\.toml|\.lock|\.md|\.txt)$|^(?:.*\/)?(?:LICENSE|NOTICE)$/i;

export const ZIP_LIMITS = Object.freeze({ inputBytes: 16 * 1024 * 1024, entries: 4096, extractedBytes: 8 * 1024 * 1024, pathLength: 512, metadataBytes: 256 * 1024 });

/** The reason a path cannot enter a Playground, or undefined when it can. */
export function exclusionReason(path: string, bytes: number): string | undefined {
  const parts = path.split("/");
  if (path.length > 180 || path.startsWith("/") || path.includes("\\") || path.includes(":") || parts.some(part => !part || part === "." || part === "..")) return "Unsafe or too long path";
  if (parts.some(part => forbidden.has(part.toLowerCase())) || parts[0].toLowerCase() === ".crabrix") return "Build, vendor or private folder";
  if (!importable.test(path)) return "Not a supported text type";
  if (bytes > PLAYGROUND_LIMITS.fileBytes) return "Larger than 64 KiB";
  return undefined;
}

const utf8 = new TextDecoder("utf-8", { fatal: true });
function decodeCandidate(path: string, bytes: Uint8Array): ImportCandidate {
  const excluded = exclusionReason(path, bytes.length);
  if (excluded) return { path, bytes: bytes.length, excluded };
  if (bytes.includes(0)) return { path, bytes: bytes.length, excluded: "Binary file" };
  try { return lfsChecked({ path, bytes: bytes.length, text: utf8.decode(bytes) }); }
  catch { return { path, bytes: bytes.length, excluded: "Not valid UTF-8 text" }; }
}

const lfsChecked = (item: ImportCandidate): ImportCandidate => item.text?.startsWith("version https://git-lfs.github.com/spec/") ? { path: item.path, bytes: item.bytes, excluded: "Git LFS pointer, not the file itself" } : item;

const commonRoot = (paths: string[]) => {
  const first = paths[0]?.split("/")[0];
  return first && paths.every(path => path.startsWith(first + "/")) ? first + "/" : "";
};

/** Explicitly chosen files, or a folder, using paths relative to the chosen root. */
export function inspectLocalFiles(files: { path: string; bytes: Uint8Array }[], kind: "files" | "folder", label: string): ImportInspection {
  const root = kind === "folder" ? commonRoot(files.map(file => file.path)) : "";
  const candidates = files.map(file => decodeCandidate(file.path.slice(root.length), file.bytes));
  return { kind, label, name: kind === "folder" && root ? root.slice(0, -1) : undefined, candidates, notes: kind === "folder" ? ["Only paths inside the chosen folder are kept."] : [] };
}

export function inspectProjectJSON(text: string): ImportInspection {
  const document = validatePlaygroundDocument(JSON.parse(text));
  const encoder = new TextEncoder();
  return { kind: "json", label: "Project JSON", name: document.name, entryFile: document.entryFile, edition: document.edition, origin: document.origin, notes: [],
    candidates: Object.entries(document.files).map(([path, value]) => ({ path, text: value, bytes: encoder.encode(value).length })) };
}

/** fflate does not expose entry modes, so symbolic links are read from the central directory. */
export function zipSymlinks(bytes: Uint8Array): Set<string> {
  const links = new Set<string>(), view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let end = bytes.length - 22;
  while (end >= 0 && view.getUint32(end, true) !== 0x06054b50) end--;
  if (end < 0) return links;
  let at = view.getUint32(end + 16, true);
  const count = view.getUint16(end + 10, true), decoder = new TextDecoder();
  for (let i = 0; i < count && at + 46 <= bytes.length && view.getUint32(at, true) === 0x02014b50; i++) {
    const made = view.getUint16(at + 4, true) >> 8, nameLength = view.getUint16(at + 28, true), extra = view.getUint16(at + 30, true), comment = view.getUint16(at + 32, true);
    const mode = view.getUint32(at + 38, true) >>> 16;
    if (made === 3 && (mode & 0o170000) === 0o120000) links.add(decoder.decode(bytes.subarray(at + 46, at + 46 + nameLength)));
    at += 46 + nameLength + extra + comment;
  }
  return links;
}

const hex = (bytes: ArrayBuffer) => Array.from(new Uint8Array(bytes), value => value.toString(16).padStart(2, "0")).join("");

/** Reads a web source ZIP, a native project archive or a repository archive.
 * Limits are checked from the headers before anything is inflated, and fflate
 * inflates into a buffer of the declared size, so an entry cannot outgrow it. */
export async function inspectZip(bytes: Uint8Array, label: string): Promise<ImportInspection> {
  if (bytes.length > ZIP_LIMITS.inputBytes) throw new Error(`This archive is larger than ${ZIP_LIMITS.inputBytes / 1024 / 1024} MiB. Extract the part you need and import that folder.`);
  const links = zipSymlinks(bytes), declared = new Map<string, number>();
  let entries = 0, planned = 0;
  const extracted = (() => {
    try {
      return unzipSync(bytes, { filter: file => {
        if (++entries > ZIP_LIMITS.entries) throw new Error("archive-entries");
        if (file.name.endsWith("/")) return false;
        declared.set(file.name, file.originalSize);
        if (links.has(file.name) || file.name.length > ZIP_LIMITS.pathLength) return false;
        const metadata = file.name.split("/").at(-2) === ".crabrix" && file.name.endsWith("/project.json");
        if (metadata) { if (file.originalSize > ZIP_LIMITS.metadataBytes) return false; }
        else if (exclusionReason(file.name, file.originalSize)) return false;
        planned += file.originalSize;
        if (planned > ZIP_LIMITS.extractedBytes) throw new Error("archive-bytes");
        return true;
      } });
    } catch (error) {
      if (error instanceof Error && error.message === "archive-entries") throw new Error(`This archive has more than ${ZIP_LIMITS.entries} entries. Extract the part you need and import that folder.`);
      if (error instanceof Error && error.message === "archive-bytes") throw new Error(`The selectable text in this archive unpacks to more than ${ZIP_LIMITS.extractedBytes / 1024 / 1024} MiB. Extract the part you need and import that folder.`);
      throw new Error("This archive could not be read. No source was changed.");
    }
  })();
  const names = Array.from(declared.keys());
  const root = commonRoot(names);
  const metadataName = names.find(name => name === `${root}.crabrix/project.json`);
  const inspection: ImportInspection = { kind: metadataName ? "native-archive" : "zip", label, candidates: [], notes: [] };
  for (const name of names) {
    if (name === metadataName) continue;
    const path = name.slice(root.length), size = declared.get(name)!;
    if (links.has(name)) { inspection.candidates.push({ path, bytes: size, excluded: "Symbolic link" }); continue; }
    const data = extracted[name];
    if (data) inspection.candidates.push(decodeCandidate(path, data));
    else inspection.candidates.push({ path, bytes: size, excluded: exclusionReason(path, size) ?? "Path too long" });
  }
  if (root && !metadataName) inspection.notes.push(`Paths inside ${root} are kept relative to it.`);
  if (metadataName) await readNativeMetadata(extracted[metadataName], inspection, extracted, root);
  else if (!root) inspection.notes.push("A source ZIP does not record the entry file or edition. Confirm them below.");
  return inspection;
}

async function readNativeMetadata(data: Uint8Array | undefined, inspection: ImportInspection, extracted: Record<string, Uint8Array>, root: string) {
  if (!data) { inspection.notes.push("The Crabrix project metadata is too large to read. Only source files were imported."); return; }
  let metadata: Record<string, unknown>;
  try { metadata = JSON.parse(utf8.decode(data)); }
  catch { throw new Error("This Crabrix archive has unreadable project metadata. No source was changed."); }
  if (typeof metadata !== "object" || metadata === null || Array.isArray(metadata)) throw new Error("This Crabrix archive has unreadable project metadata. No source was changed.");
  const digests = metadata.fileDigests;
  if (digests && typeof digests === "object" && !Array.isArray(digests)) {
    for (const [path, expected] of Object.entries(digests as Record<string, unknown>)) {
      const bytes = extracted[root + path];
      if (!bytes || typeof expected !== "string") continue;
      const copy = new Uint8Array(bytes);
      if (hex(await crypto.subtle.digest("SHA-256", copy.buffer as ArrayBuffer)) !== expected.toLowerCase()) throw new Error(`The digest of ${path} does not match this archive's metadata. No source was changed.`);
    }
  }
  if (typeof metadata.name === "string") inspection.name = metadata.name;
  if (typeof metadata.entryFile === "string") inspection.entryFile = metadata.entryFile;
  inspection.notes.push("Crabrix project metadata was read for the name and entry file. Its project identity, history and provenance stay with the native project and are not carried into this Playground.");
}

export class GitHubLimitError extends Error {}
type Fetcher = typeof fetch;
type GitHubOptions = { signal?: AbortSignal; fetcher?: Fetcher; ref?: string; folder?: string };

async function githubJSON(url: string, options: GitHubOptions, maximum = 4_000_000, allow404 = false) {
  const signal = options.signal ? AbortSignal.any([options.signal, AbortSignal.timeout(20_000)]) : AbortSignal.timeout(20_000);
  const response = await (options.fetcher ?? fetch)(url, { credentials: "omit", redirect: "error", headers: { Accept: "application/vnd.github+json" }, signal });
  if (allow404 && (response.status === 404 || response.status === 422)) return null;
  if (response.status === 403 || response.status === 429) {
    const retry = Number(response.headers.get("retry-after")) * 1000 || Number(response.headers.get("x-ratelimit-reset")) * 1000 - Date.now();
    const when = retry > 0 ? ` Try again in about ${Math.ceil(retry / 60_000)} min.` : " Try again later.";
    throw new GitHubLimitError(`GitHub's anonymous request limit was reached.${when} You can also download the files and import them from this device.`);
  }
  if (!response.ok) throw new Error(response.status === 404 ? "GitHub could not find this public source. Check the link, ref and folder." : `GitHub could not read this public source (${response.status}).`);
  if (!response.body) throw new Error("GitHub returned no source.");
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let total = 0;
  try {
    while (true) { const { done, value } = await reader.read(); if (done) break; total += value.length; if (total > maximum) throw new Error("This GitHub listing is too large. Choose a narrower folder."); chunks.push(value); }
  } finally { await reader.cancel().catch(() => {}); }
  const bytes = new Uint8Array(total); let at = 0; for (const chunk of chunks) { bytes.set(chunk, at); at += chunk.length; }
  return JSON.parse(utf8.decode(bytes));
}

export type ParsedSource = { kind: "gist"; gist: string; url: string } | { kind: "repo"; owner: string; repo: string; view: "root" | "tree" | "blob"; segments: string[]; url: string };

/** Keeps only what identifies the source: no credentials, query or fragment. */
export function parseSourceURL(raw: string): ParsedSource {
  let url: URL;
  try { url = new URL(raw.trim()); } catch { throw new Error("Use a public HTTPS GitHub repository, gist or Rust Playground link."); }
  if (url.protocol !== "https:" || url.username || url.password || url.port || !["github.com", "gist.github.com", "play.rust-lang.org"].includes(url.hostname)) throw new Error("Use a public HTTPS GitHub repository, gist or Rust Playground link.");
  if (url.hostname !== "github.com") {
    const gist = url.hostname === "play.rust-lang.org" ? url.searchParams.get("gist") : url.pathname.split("/").filter(Boolean).at(-1);
    if (url.hostname === "play.rust-lang.org" && !gist) throw new Error("The Rust Playground link must contain a public gist.");
    if (!gist || !/^[a-f0-9]{20,64}$/i.test(gist)) throw new Error("Invalid public gist identifier.");
    const clean = url.hostname === "play.rust-lang.org" ? `https://play.rust-lang.org/?gist=${gist}` : `https://gist.github.com/${url.pathname.split("/").filter(Boolean).join("/")}`;
    return { kind: "gist", gist, url: clean };
  }
  const parts = url.pathname.split("/").filter(Boolean).map(part => decodeURIComponent(part)), owner = parts[0], repo = parts[1]?.replace(/\.git$/, "");
  if (!owner || !repo || !/^[a-z0-9_.-]+$/i.test(owner) || !/^[a-z0-9_.-]+$/i.test(repo)) throw new Error("Use a GitHub repository URL.");
  if (parts.length > 2 && parts[2] !== "tree" && parts[2] !== "blob") throw new Error("Use the repository, a /tree/ folder or a /blob/ file link.");
  if ((parts[2] === "tree" || parts[2] === "blob") && !parts[3]) throw new Error("This link has no ref. Add a branch, tag or commit.");
  const view = parts[2] === "tree" ? "tree" : parts[2] === "blob" ? "blob" : "root";
  return { kind: "repo", owner, repo, view, segments: parts.slice(3), url: `https://github.com/${owner}/${repo}${parts.length > 2 ? "/" + parts.slice(2).map(encodeURIComponent).join("/") : ""}` };
}

/** A ref may contain slashes, so `/tree/a/b/c` is ambiguous until GitHub answers. */
export async function resolveRefAndPath(base: string, segments: string[], options: GitHubOptions): Promise<{ ref: string; commit: string; path: string }> {
  const commitOf = async (ref: string) => {
    const value = await githubJSON(`${base}/commits/${encodeURIComponent(ref)}`, options, 1_000_000, true);
    if (value === null) return null;
    if (!/^[a-f0-9]{40}$/.test(value.sha)) throw new Error("GitHub did not resolve a source revision.");
    return value.sha as string;
  };
  if (options.ref) {
    const commit = await commitOf(options.ref);
    if (!commit) throw new Error(`GitHub has no ref named ${options.ref}.`);
    return { ref: options.ref, commit, path: options.folder ?? segments.join("/") };
  }
  const matches: { ref: string; commit: string; path: string }[] = [];
  for (let length = 1; length <= Math.min(segments.length, 5); length++) {
    const ref = segments.slice(0, length).join("/"), commit = await commitOf(ref);
    if (commit) matches.push({ ref, commit, path: segments.slice(length).join("/") });
    if (commit && /^[a-f0-9]{40}$/.test(ref)) break;
  }
  if (!matches.length) throw new Error("GitHub could not find this ref. Enter the ref and folder explicitly.");
  if (matches.length > 1) throw new Error(`This link could mean ${matches.map(item => item.ref).join(" or ")}. Enter the ref and folder explicitly.`);
  return options.folder ? { ...matches[0], path: options.folder } : matches[0];
}

type TreeItem = { path: string; type: string; mode?: string; size?: number; sha: string };

export async function inspectPublicSource(raw: string, options: GitHubOptions = {}): Promise<ImportInspection> {
  const parsed = parseSourceURL(raw);
  const folderInput = (options.folder ?? "").trim().replace(/^\/+|\/+$/g, "");
  if (folderInput.split("/").some(part => part === ".." || part === ".") || folderInput.includes("\\")) throw new Error("Use a repository-relative source folder.");
  options = { ...options, folder: folderInput || undefined, ref: options.ref?.trim() || undefined };

  if (parsed.kind === "gist") {
    const value = await githubJSON(`https://api.github.com/gists/${parsed.gist}`, options);
    const candidates: ImportCandidate[] = Object.entries(value.files ?? {}).map(([path, item]) => {
      const file = item as { size: number; content: string; truncated?: boolean };
      const excluded = exclusionReason(path, file.size) ?? (file.truncated || typeof file.content !== "string" ? "GitHub truncated this file" : undefined);
      return excluded ? { path, bytes: file.size, excluded } : { path, bytes: file.size, text: file.content };
    });
    return { kind: "gist", label: "Public gist", name: "imported-gist", origin: { url: parsed.url }, candidates, notes: [] };
  }

  const base = `https://api.github.com/repos/${parsed.owner}/${parsed.repo}`;
  const defaults = parsed.view === "root" && !options.ref ? (await githubJSON(base, options, 100_000)).default_branch as string : null;
  const located = defaults
    ? { ...await resolveRefAndPath(base, [], { ...options, ref: defaults, folder: folderInput }), path: folderInput }
    : await resolveRefAndPath(base, parsed.segments, options);
  const { ref, commit, path } = located;
  const notes: string[] = [];
  const origin = { url: parsed.url, commit };
  const label = `${parsed.owner}/${parsed.repo}`;

  // Walking down avoids asking for the recursive tree of a very large repository.
  let treeSha = commit, itemName: string | null = null;
  const parts = path ? path.split("/") : [];
  for (let i = 0; i < parts.length; i++) {
    const level = await githubJSON(`${base}/git/trees/${treeSha}`, options);
    const match = (level.tree as TreeItem[]).find(item => item.path === parts[i]);
    if (!match) throw new Error(`GitHub has no ${parts.slice(0, i + 1).join("/")} at ${ref}.`);
    if (match.type === "blob" && i === parts.length - 1) { itemName = parts[i]; treeSha = match.sha; break; }
    if (match.type !== "tree") throw new Error(`${parts.slice(0, i + 1).join("/")} is not a folder.`);
    treeSha = match.sha;
  }
  if (itemName) {
    return { kind: "github", label, name: parsed.repo, origin, ref, folder: path, notes, candidates: [{ path: itemName, bytes: 0, blobSha: treeSha }] };
  }
  const tree = await githubJSON(`${base}/git/trees/${treeSha}?recursive=1`, options);
  if (tree.truncated) notes.push("GitHub returned only part of this folder. Files may be missing from the list; enter a narrower folder to see them.");
  const candidates: ImportCandidate[] = [];
  for (const item of tree.tree as TreeItem[]) {
    if (item.type === "commit") { candidates.push({ path: item.path, bytes: 0, excluded: "Git submodule" }); continue; }
    if (item.type !== "blob") continue;
    if (item.mode === "120000") { candidates.push({ path: item.path, bytes: item.size ?? 0, excluded: "Symbolic link" }); continue; }
    const excluded = exclusionReason(item.path, item.size ?? 0);
    candidates.push(excluded ? { path: item.path, bytes: item.size ?? 0, excluded } : { path: item.path, bytes: item.size ?? 0, blobSha: item.sha });
  }
  return { kind: "github", label, name: parsed.repo, origin, ref, folder: path, candidates, notes };
}

/** Reads the chosen blobs with a small number of parallel requests. Every file comes from the pinned tree. */
export async function loadSelectedText(inspection: ImportInspection, selected: ReadonlySet<string>, options: GitHubOptions = {}): Promise<ImportInspection> {
  if (inspection.kind !== "github") return inspection;
  const parsed = parseSourceURL(inspection.origin!.url);
  if (parsed.kind !== "repo") return inspection;
  const base = `https://api.github.com/repos/${parsed.owner}/${parsed.repo}`;
  const pending = inspection.candidates.filter(item => selected.has(item.path) && !item.excluded && item.text === undefined && item.blobSha);
  const loaded = new Map<string, ImportCandidate>();
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(4, pending.length) }, async () => {
    while (cursor < pending.length) {
      const item = pending[cursor++];
      const blob = await githubJSON(`${base}/git/blobs/${item.blobSha}`, options, 200_000);
      if (blob.encoding !== "base64" || typeof blob.content !== "string") { loaded.set(item.path, { path: item.path, bytes: item.bytes, excluded: "Not available as text" }); continue; }
      const text = atob(blob.content.replace(/\s/g, ""));
      loaded.set(item.path, { ...decodeCandidate(item.path, Uint8Array.from(text, char => char.charCodeAt(0))), blobSha: item.blobSha });
    }
  }));
  return { ...inspection, candidates: inspection.candidates.map(item => loaded.get(item.path) ?? item) };
}
