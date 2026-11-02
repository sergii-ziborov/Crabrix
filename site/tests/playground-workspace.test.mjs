import { test } from "node:test";
import assert from "node:assert/strict";
import { zipSync, strToU8 } from "fflate";
import { createHash } from "node:crypto";
import { PlaygroundRooms } from "../lib/playground-rooms.ts";
import { newPlaygroundDocument } from "../lib/playground-document.ts";
import { buildImportPlan, canTransition, checkImportPlan, declaredCargoEdition, documentRevision, ImportOperations, projectReadiness } from "../lib/playground-import-plan.ts";
import { inspectProjectJSON, inspectLocalFiles, inspectPublicSource, inspectZip, loadSelectedText, parseSourceURL, ZIP_LIMITS } from "../lib/playground-import-sources.ts";
import { buildFileTree, flattenTree, fileIconKind, matchingPaths, planFileOperation, remapBreakpoints, isDestructiveInSharedRoom } from "../lib/playground-file-ops.ts";
import { readThemePreference, resolveTheme, THEME_STORAGE_KEY, LEGACY_PLAYGROUND_PREFERENCES_KEY } from "../lib/theme.ts";

const packet = byte => ({ iv: Buffer.alloc(12, byte).toString("base64url"), data: Buffer.alloc(32, byte).toString("base64url") });
const project = () => ({ schemaVersion: 1, name: "demo", entryFile: "main.rs", edition: "2024", files: { "main.rs": "fn main() {}\n", "bubble_sort.rs": "pub fn sort() {}\n" } });
const inspection = (candidates, extra = {}) => ({ kind: "files", label: "Test", candidates, notes: [], ...extra });
const choose = (paths, extra = {}) => ({ selected: new Set(paths), mode: "add", targetFolder: "", conflicts: {}, ...extra });
const file = (path, text) => ({ path, text, bytes: Buffer.byteLength(text) });
const bytes = text => new TextEncoder().encode(text);

test("T53 a stale generation is refused after a snapshot even though the sequence did not move", () => {
  const relay = new PlaygroundRooms(() => 1_000_000), created = relay.create(packet(1), 60), peer = "a".repeat(24);
  relay.subscribe(created.id, created.edit, peer, () => {});
  const before = relay.state(created.id, created.edit);
  assert.equal(before.protocol.stateGeneration, 1);
  const compacted = relay.compact(created.id, created.edit, before.sequence, packet(2));
  const after = relay.state(created.id, created.edit);
  assert.equal(after.sequence, before.sequence);
  assert.notEqual(after.generation, before.generation);
  assert.equal(compacted.generation, after.generation);
  assert.throws(() => relay.append(created.id, created.edit, peer, "b".repeat(24), packet(3), before.sequence, before.generation), error => error.status === 409);
  assert.equal(relay.state(created.id, created.edit).sequence, before.sequence, "nothing was written");
  const applied = relay.append(created.id, created.edit, peer, "c".repeat(24), packet(3), after.sequence, after.generation);
  assert.equal(applied.generation, after.generation + 1);
  assert.equal(relay.append(created.id, created.edit, peer, "c".repeat(24), packet(3), after.sequence, after.generation).sequence, applied.sequence, "a lost response can still be retried");
  assert.throws(() => relay.compact(created.id, created.edit, applied.sequence, packet(4), after.generation), error => error.status === 409);
});

test("a client that does not send a generation keeps working", () => {
  const relay = new PlaygroundRooms(() => 1_000_000), created = relay.create(packet(1), 60), peer = "a".repeat(24);
  relay.subscribe(created.id, created.edit, peer, () => {});
  assert.equal(relay.append(created.id, created.edit, peer, "b".repeat(24), packet(3), 0).sequence, 1);
  assert.equal(relay.append(created.id, created.edit, peer, "c".repeat(24), packet(3)).sequence, 2);
  assert.equal(relay.compact(created.id, created.edit, 2, packet(4)).sequence, 2);
});

test("T01 adding keeps existing files and building a plan changes nothing", () => {
  const current = project(), frozen = JSON.stringify(current);
  const plan = buildImportPlan(current, inspection([file("example.rs", "pub fn e() {}\n")]), choose(["example.rs"]));
  assert.equal(JSON.stringify(current), frozen);
  assert.deepEqual(plan.added, ["example.rs"]);
  assert.deepEqual(Object.keys(plan.document.files).sort(), ["bubble_sort.rs", "example.rs", "main.rs"]);
  assert.equal(plan.document.entryFile, "main.rs");
});

test("T09 a conflicting path needs an explicit choice and honours it", () => {
  const source = inspection([file("main.rs", "fn main() { /* new */ }\n")]);
  const blocked = buildImportPlan(project(), source, choose(["main.rs"]));
  assert.equal(blocked.document, undefined);
  assert.match(blocked.error, /Choose what to do/);
  assert.equal(buildImportPlan(project(), source, choose(["main.rs"], { conflicts: { "main.rs": "skip" } })).document.files["main.rs"], "fn main() {}\n");
  assert.match(buildImportPlan(project(), source, choose(["main.rs"], { conflicts: { "main.rs": "replace" } })).document.files["main.rs"], /new/);
  const renamed = buildImportPlan(project(), source, choose(["main.rs"], { conflicts: { "main.rs": "rename" } }));
  assert.equal(renamed.document.files["main-imported.rs"], "fn main() { /* new */ }\n");
  assert.equal(renamed.document.files["main.rs"], "fn main() {}\n");
});

test("T02 replace lists what it removes and T14 a shared room refuses it", () => {
  const plan = buildImportPlan(project(), inspection([file("src/main.rs", "fn main() {}\n")], { name: "other", entryFile: "src/main.rs" }), choose(["src/main.rs"], { mode: "replace", edition: "2021" }));
  assert.deepEqual(plan.removed.sort(), ["bubble_sort.rs", "main.rs"]);
  assert.equal(plan.document.name, "other");
  assert.equal(checkImportPlan(plan, project(), true).status, "blocked");
  assert.equal(checkImportPlan(plan, project(), false).status, "applied");
});

test("T03 a project that changed after the preview needs a new plan", () => {
  const current = project();
  const plan = buildImportPlan(current, inspection([file("a.rs", "")]), choose(["a.rs"]));
  assert.equal(checkImportPlan(plan, current, false).status, "applied");
  assert.equal(checkImportPlan(plan, { ...current, files: { ...current.files, "main.rs": "fn main() { edited(); }\n" } }, false).status, "needs_refresh");
});

test("T04 an abandoned preparation cannot be current or reach applying", () => {
  const operations = new ImportOperations(), first = operations.begin();
  operations.cancel();
  assert.equal(first.signal.aborted, true);
  assert.equal(operations.isCurrent(first.id), false);
  const second = operations.begin(), third = operations.begin();
  assert.equal(second.signal.aborted, true);
  assert.equal(operations.isCurrent(third.id), true);
  assert.equal(canTransition("inspecting", "applying"), false);
  assert.equal(canTransition("cancelled", "applying"), false);
  assert.equal(canTransition("ready", "applying"), true);
});

test("T06 a subset of a large source fits the budget that the whole would not", () => {
  const candidates = Array.from({ length: 100 }, (_, index) => file(`src/m${index}.rs`, "pub fn x() {}\n"));
  assert.ok(buildImportPlan(project(), inspection(candidates), choose(candidates.map(item => item.path))).error);
  const plan = buildImportPlan(project(), inspection(candidates), choose(["src/m1.rs", "src/m2.rs", "src/m3.rs"]));
  assert.equal(plan.fileCount, 5);
});

test("T13 collisions and forbidden paths refuse the whole result", () => {
  assert.ok(buildImportPlan(project(), inspection([file("target/x.rs", "")]), choose(["target/x.rs"])).error);
  assert.match(buildImportPlan(project(), inspection([file("Main.rs", "")]), choose(["Main.rs"])).error, /Choose what to do/, "case-only collision is a conflict");
  assert.ok(buildImportPlan(project(), inspection([file("bubble_sort.rs/x.rs", "")]), choose(["bubble_sort.rs/x.rs"])).error, "a file cannot also be a directory");
});

test("T15 Cargo dependencies and library-only sources are not presented as runnable", () => {
  const base = { schemaVersion: 1, name: "x", edition: "2024" };
  assert.equal(projectReadiness({ ...base, entryFile: "src/main.rs", files: { "src/main.rs": "fn main() {}", "Cargo.toml": "[package]\nname='x'\n[dependencies]\nserde = '1'\n" } }).kind, "other-build");
  assert.equal(projectReadiness({ ...base, entryFile: "src/lib.rs", files: { "src/lib.rs": "pub fn x() {}" } }).kind, "other-build");
  assert.equal(projectReadiness({ ...base, entryFile: "src/main.rs", files: { "src/main.rs": "fn main() {}", "Cargo.toml": "[package]\nname='x'\n[dependencies]\n" } }).kind, "runner");
});

test("T58 an edition the runner does not know is shown and never replaced by 2024", () => {
  assert.deepEqual(declaredCargoEdition('[package]\nname = "x"\nedition = "2018"\n'), { kind: "unsupported", value: "2018" });
  assert.deepEqual(declaredCargoEdition('[package]\nedition.workspace = true\n'), { kind: "workspace" });
  assert.deepEqual(declaredCargoEdition('[package]\nedition = { workspace = true }\n'), { kind: "workspace" });
  assert.deepEqual(declaredCargoEdition('[package]\nedition = "2021"\n'), { kind: "supported", edition: "2021" });
  assert.deepEqual(declaredCargoEdition('[workspace.package]\nedition = "2021"\n'), { kind: "none" });
  assert.deepEqual(declaredCargoEdition('# edition = "2021"\n[package]\nname = "x"\n'), { kind: "none" });
  const manifest = file("Cargo.toml", '[package]\nname = "x"\nedition = "2018"\n');
  const plan = buildImportPlan(project(), inspection([manifest]), choose(["Cargo.toml"]));
  assert.equal(plan.needsEdition, true);
  assert.equal(plan.document, undefined);
  const chosen = buildImportPlan(project(), inspection([manifest]), choose(["Cargo.toml"], { edition: "2021" }));
  assert.equal(chosen.document.edition, "2021");
  assert.equal(chosen.document.files["Cargo.toml"], manifest.text, "the manifest is not rewritten");
});

test("T58 files from a second source drop the single origin", () => {
  const current = { ...project(), origin: { url: "https://github.com/a/one", commit: "a".repeat(40) } };
  const second = inspection([file("b.rs", "")], { kind: "github", origin: { url: "https://github.com/a/two", commit: "b".repeat(40) } });
  const plan = buildImportPlan(current, second, choose(["b.rs"]));
  assert.equal(plan.document.origin, undefined);
  assert.equal(plan.receipt.commit, "b".repeat(40));
  assert.equal(buildImportPlan(current, inspection([file("c.rs", "")], { origin: current.origin }), choose(["c.rs"])).document.origin.url, current.origin.url);
});

test("a target folder places every imported path", () => {
  const plan = buildImportPlan(project(), inspection([file("a.rs", ""), file("sub/b.rs", "")]), choose(["a.rs", "sub/b.rs"], { targetFolder: "/vendored_src/" }));
  assert.deepEqual(plan.added.sort(), ["vendored_src/a.rs", "vendored_src/sub/b.rs"]);
  assert.equal(plan.receipt.paths["sub/b.rs"], "vendored_src/sub/b.rs");
});

test("T10 multi-file and folder imports keep paths and exact text", () => {
  const crlf = "fn main() {\r\n}\r\n";
  const folder = inspectLocalFiles([{ path: "root/src/main.rs", bytes: bytes(crlf) }, { path: "root/README.md", bytes: bytes("# x") }], "folder", "root");
  assert.deepEqual(folder.candidates.map(item => item.path).sort(), ["README.md", "src/main.rs"]);
  assert.equal(folder.candidates.find(item => item.path === "src/main.rs").text, crlf);
  assert.equal(folder.name, "root");
  assert.equal(inspectLocalFiles([{ path: "a.rs", bytes: bytes("x") }], "files", "a").candidates[0].path, "a.rs");
});

test("T11 malformed text, binary and LFS pointers are explained, multibyte is counted in bytes", () => {
  const { candidates } = inspectLocalFiles([
    { path: "bad.rs", bytes: new Uint8Array([0xff, 0xfe]) }, { path: "zero.txt", bytes: new Uint8Array([65, 0]) },
    { path: "big.md", bytes: bytes("version https://git-lfs.github.com/spec/v1\noid sha256:x\n") }, { path: "ok.rs", bytes: bytes("// 🦀") }, { path: "image.png", bytes: new Uint8Array([1]) },
  ], "files", "x");
  const reason = path => candidates.find(item => item.path === path).excluded;
  assert.match(reason("bad.rs"), /UTF-8/); assert.match(reason("zero.txt"), /Binary/); assert.match(reason("big.md"), /LFS/); assert.match(reason("image.png"), /supported/);
  assert.equal(candidates.find(item => item.path === "ok.rs").bytes, 7);
});

test("T10 a source ZIP round-trips paths and text and asks for entry and edition", async () => {
  const value = await inspectZip(zipSync({ "src/main.rs": strToU8("fn main() {}\n"), "README.md": strToU8("# é") }), "x.zip");
  assert.equal(value.kind, "zip");
  assert.equal(value.candidates.find(item => item.path === "README.md").text, "# é");
  assert.ok(value.notes.some(note => /entry file or edition/.test(note)));
  assert.equal(value.edition, undefined);
});

test("T12 unsafe and oversized archives are refused or listed before any change", async () => {
  await assert.rejects(inspectZip(new Uint8Array(ZIP_LIMITS.inputBytes + 1), "big.zip"), /larger than/);
  await assert.rejects(inspectZip(new Uint8Array([1, 2, 3]), "bad.zip"), /could not be read/);
  const traversal = await inspectZip(zipSync({ "../evil.rs": strToU8("x"), "ok.rs": strToU8("y") }), "t.zip");
  assert.match(traversal.candidates.find(item => item.path.endsWith("evil.rs")).excluded, /Unsafe/);
  const many = Object.fromEntries(Array.from({ length: ZIP_LIMITS.entries + 1 }, (_, i) => [`f${i}.bin`, new Uint8Array(1)]));
  await assert.rejects(inspectZip(zipSync(many), "many.zip"), /entries/);
  const bomb = Object.fromEntries(Array.from({ length: 200 }, (_, i) => [`f${i}.rs`, new Uint8Array(60 * 1024).fill(97)]));
  await assert.rejects(inspectZip(zipSync(bomb), "bomb.zip"), /unpacks to more/);
});

test("T57 a native archive keeps its metadata out of the files and checks its digests", async () => {
  const source = "fn main() {}\n", digest = createHash("sha256").update(source).digest("hex");
  const archive = metadata => zipSync({ "Demo/.crabrix/project.json": strToU8(JSON.stringify(metadata)), "Demo/src/app.rs": strToU8(source), "Demo/Cargo.toml": strToU8('[package]\nedition="2021"\n') });
  const value = await inspectZip(archive({ version: 3, projectID: "00000000-0000-0000-0000-000000000000", name: "Demo", entryFile: "src/app.rs", fileDigests: { "src/app.rs": digest } }), "demo.zip");
  assert.equal(value.kind, "native-archive");
  assert.equal(value.name, "Demo");
  assert.equal(value.entryFile, "src/app.rs");
  assert.ok(value.candidates.every(item => !item.path.includes(".crabrix")));
  assert.ok(value.notes.some(note => /not carried/.test(note)));
  await assert.rejects(inspectZip(archive({ version: 3, name: "Demo", entryFile: "src/app.rs", fileDigests: { "src/app.rs": "0".repeat(64) } }), "corrupt.zip"), /digest/);
  await assert.rejects(inspectZip(zipSync({ ".crabrix/project.json": strToU8("{nope"), "a.rs": strToU8("x") }), "m.zip"), /unreadable/);
});

test("project JSON keeps its entry and edition", () => {
  const value = inspectProjectJSON(JSON.stringify({ ...project(), edition: "2021" }));
  assert.equal(value.edition, "2021");
  assert.throws(() => inspectProjectJSON(JSON.stringify({ nope: 1 })));
});

const github = routes => async url => {
  const value = routes[url];
  if (value === undefined) return new Response("{}", { status: 404 });
  if (value instanceof Response) return value;
  return new Response(JSON.stringify(value), { status: 200 });
};
const base = "https://api.github.com/repos/o/r";
const sha = "c".repeat(40);

test("T08 refs with slashes, blob links and ambiguity", async () => {
  const routes = {
    [`${base}/commits/feature`]: undefined,
    [`${base}/commits/${encodeURIComponent("feature/parser")}`]: { sha },
    [`${base}/git/trees/${sha}`]: { tree: [{ path: "src", type: "tree", sha: "t1" }] },
    [`${base}/git/trees/t1?recursive=1`]: { tree: [{ path: "lib.rs", type: "blob", mode: "100644", size: 3, sha: "b1" }] },
    [`${base}/git/trees/t1`]: { tree: [{ path: "lib.rs", type: "blob", size: 3, sha: "b1" }] },
    [`${base}/git/blobs/b1`]: { encoding: "base64", content: Buffer.from("x;\n").toString("base64") },
  };
  const tree = await inspectPublicSource("https://github.com/o/r/tree/feature/parser/src", { fetcher: github(routes) });
  assert.equal(tree.ref, "feature/parser");
  assert.equal(tree.folder, "src");
  assert.equal(tree.origin.commit, sha);
  assert.deepEqual(tree.candidates.map(item => item.path), ["lib.rs"]);
  assert.equal(tree.candidates[0].text, undefined, "blobs wait until they are chosen");
  const loaded = await loadSelectedText(tree, new Set(["lib.rs"]), { fetcher: github(routes) });
  assert.equal(loaded.candidates[0].text, "x;\n");
  const blob = await inspectPublicSource("https://github.com/o/r/blob/feature/parser/src/lib.rs", { fetcher: github(routes) });
  assert.deepEqual(blob.candidates.map(item => item.path), ["lib.rs"]);
  await assert.rejects(inspectPublicSource("https://github.com/o/r/tree/feature/parser/src", { fetcher: github({ ...routes, [`${base}/commits/feature`]: { sha } }) }), /could mean feature or feature\/parser/);
  assert.equal((await inspectPublicSource("https://github.com/o/r/tree/ignored/path", { fetcher: github({ ...routes, [`${base}/commits/${encodeURIComponent("feature/parser")}`]: { sha } }), ref: "feature/parser", folder: "src" })).folder, "src");
});

test("T07 a small folder does not read the recursive tree of the repository", async () => {
  const asked = [];
  const routes = { [base]: { default_branch: "main" }, [`${base}/commits/main`]: { sha }, [`${base}/git/trees/${sha}`]: { tree: [{ path: "src", type: "tree", sha: "t1" }] }, [`${base}/git/trees/t1?recursive=1`]: { tree: [{ path: "a.rs", type: "blob", size: 1, sha: "b" }] } };
  const fetcher = async url => { asked.push(url); return github(routes)(url); };
  const value = await inspectPublicSource("https://github.com/o/r", { fetcher, folder: "src" });
  assert.deepEqual(value.candidates.map(item => item.path), ["a.rs"]);
  assert.ok(!asked.includes(`${base}/git/trees/${sha}?recursive=1`));
});

test("truncated trees, submodules, symlinks and oversized files are visible", async () => {
  const routes = { [base]: { default_branch: "main" }, [`${base}/commits/main`]: { sha }, [`${base}/git/trees/${sha}?recursive=1`]: { truncated: true, tree: [
    { path: "dep", type: "commit", sha: "s" }, { path: "link.rs", type: "blob", mode: "120000", size: 3, sha: "l" }, { path: "big.rs", type: "blob", mode: "100644", size: 70000, sha: "g" }, { path: "ok.toml", type: "blob", mode: "100644", size: 1, sha: "o" }, { path: "target/x.rs", type: "blob", size: 1, sha: "t" },
  ] } };
  const value = await inspectPublicSource("https://github.com/o/r", { fetcher: github(routes) });
  const reason = path => value.candidates.find(item => item.path === path).excluded;
  assert.match(reason("dep"), /submodule/); assert.match(reason("link.rs"), /Symbolic/); assert.match(reason("big.rs"), /64 KiB/); assert.match(reason("target/x.rs"), /Build/); assert.equal(reason("ok.toml"), undefined);
  assert.ok(value.notes.some(note => /only part/.test(note)));
});

test("a rate limit names its cause and links keep no credentials or query", async () => {
  const limited = async () => new Response("{}", { status: 403, headers: { "retry-after": "120" } });
  await assert.rejects(inspectPublicSource("https://github.com/o/r", { fetcher: limited }), /limit was reached\. Try again in about 2 min/);
  assert.throws(() => parseSourceURL("https://user:pw@github.com/o/r"), /public HTTPS/);
  assert.throws(() => parseSourceURL("https://github.com/o/r/pulls"), /tree/);
  assert.equal(parseSourceURL("https://github.com/o/r?token=abc#frag").url, "https://github.com/o/r");
  assert.equal(parseSourceURL("https://play.rust-lang.org/?version=stable&gist=" + "a".repeat(32)).url, "https://play.rust-lang.org/?gist=" + "a".repeat(32));
});

test("the tree lists folders first in a stable order", () => {
  const tree = buildFileTree(["main.rs", "src/b.rs", "src/a/c.rs", "Cargo.toml", "src/a.rs"]);
  assert.deepEqual(tree.map(node => node.name), ["src", "Cargo.toml", "main.rs"]);
  assert.deepEqual(tree[0].children.map(node => node.name), ["a", "a.rs", "b.rs"]);
  assert.deepEqual(flattenTree(tree, new Set()).map(item => item.node.path), ["src", "Cargo.toml", "main.rs"]);
  assert.deepEqual(flattenTree(tree, new Set(["src", "src/a"])).map(item => [item.node.path, item.depth]).slice(0, 3), [["src", 0], ["src/a", 1], ["src/a/c.rs", 2]]);
  assert.deepEqual(matchingPaths(["src/Parser.rs", "main.rs"], "parser"), ["src/Parser.rs"]);
});

test("file icons follow the type and a lock file is only a lock file", () => {
  assert.deepEqual(["a.rs", "Cargo.toml", "Cargo.lock", "a.md", "a.txt", "LICENSE", "NOTICE", "x/other"].map(fileIconKind), ["rust", "config", "lock", "markdown", "text", "license", "notice", "generic"]);
});

test("T20 moving a folder updates the entry atomically and one collision moves nothing", () => {
  const source = { ...project(), entryFile: "src/main.rs", files: { "src/main.rs": "fn main() {}\n", "src/a.rs": "", "lib/a.rs": "" } };
  const plan = planFileOperation(source, { kind: "rename-folder", from: "src", to: "app" });
  assert.equal(plan.document.entryFile, "app/main.rs");
  assert.equal(plan.moved["src/a.rs"], "app/a.rs");
  assert.throws(() => planFileOperation(source, { kind: "rename-folder", from: "src", to: "lib" }), /already exists/);
  assert.throws(() => planFileOperation(source, { kind: "rename-folder", from: "src", to: "src/inner" }), /inside itself/);
  assert.equal(source.entryFile, "src/main.rs");
});

test("deleting the folder that holds the entry needs a new entry that stays", () => {
  const source = { ...project(), entryFile: "src/main.rs", files: { "src/main.rs": "fn main() {}\n", "other.rs": "fn main() {}\n" } };
  assert.throws(() => planFileOperation(source, { kind: "delete-folder", path: "src" }), /new entry/);
  assert.throws(() => planFileOperation(source, { kind: "delete-folder", path: "src", entryFile: "src/main.rs" }), /new entry/);
  assert.equal(planFileOperation(source, { kind: "delete-folder", path: "src", entryFile: "other.rs" }).document.entryFile, "other.rs");
});

test("file operations share document validation and remap breakpoints", () => {
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "../x.rs" }), /Unsupported/);
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "MAIN.rs" }), /already exists/);
  assert.throws(() => planFileOperation(project(), { kind: "create", path: "main.rs/x.rs" }));
  const plan = planFileOperation(project(), { kind: "rename", from: "bubble_sort.rs", to: "sort/bubble.rs" });
  assert.equal(plan.movesRustSource, true);
  assert.deepEqual(remapBreakpoints({ "bubble_sort.rs": [2], "main.rs": [1] }, plan), { "sort/bubble.rs": [2], "main.rs": [1] });
  assert.equal(planFileOperation(project(), { kind: "duplicate", from: "main.rs", to: "copy.rs" }).document.files["copy.rs"], "fn main() {}\n");
});

test("T19 only additive operations stay open in a shared v1 room", () => {
  assert.equal(isDestructiveInSharedRoom({ kind: "create", path: "a.rs" }), false);
  assert.equal(isDestructiveInSharedRoom({ kind: "duplicate", from: "a", to: "b" }), false);
  for (const operation of [{ kind: "rename", from: "a", to: "b" }, { kind: "rename-folder", from: "a", to: "b" }, { kind: "delete-file", path: "a" }, { kind: "delete-folder", path: "a" }]) assert.equal(isDestructiveInSharedRoom(operation), true);
});

const storage = initial => { const values = new Map(Object.entries(initial)); return { getItem: key => values.has(key) ? values.get(key) : null, setItem: (key, value) => values.set(key, value), values }; };

test("T27 the old theme moves once and never overwrites a newer choice", () => {
  const old = storage({ [LEGACY_PLAYGROUND_PREFERENCES_KEY]: JSON.stringify({ theme: "cyberpunk", fontSize: 15 }) });
  assert.equal(readThemePreference(old), "cyberpunk");
  assert.equal(old.values.get(THEME_STORAGE_KEY), "cyberpunk");
  const newer = storage({ [THEME_STORAGE_KEY]: "amber", [LEGACY_PLAYGROUND_PREFERENCES_KEY]: JSON.stringify({ theme: "cyberpunk" }) });
  assert.equal(readThemePreference(newer), "amber");
  assert.equal(readThemePreference(storage({ [LEGACY_PLAYGROUND_PREFERENCES_KEY]: "{broken" })), "system");
  assert.equal(readThemePreference(storage({ [THEME_STORAGE_KEY]: "nonsense" })), "system");
  assert.equal(resolveTheme("system", true), "light");
  assert.equal(resolveTheme("system", false), "dark");
  assert.equal(resolveTheme("amber", true), "amber");
});

test("a revision covers the name, entry, edition, origin and every file", () => {
  const base = newPlaygroundDocument(), revision = documentRevision(base);
  assert.equal(documentRevision({ ...base, files: { ...base.files } }), revision);
  for (const changed of [{ ...base, name: "other" }, { ...base, edition: "2021" }, { ...base, files: { "main.rs": "x" } }]) assert.notEqual(documentRevision(changed), revision);
});

test("T48 the public descriptor carries no room secrets and one source of versions", async () => {
  const { aiBootstrap } = await import("../lib/ai-bootstrap.ts");
  const { default: download } = await import("../lib/mcp-download.json", { with: { type: "json" } });
  const text = JSON.stringify(aiBootstrap);
  assert.equal(aiBootstrap.distribution.npm.version, download.version);
  assert.deepEqual(aiBootstrap.mcp.config.args, ["-y", `crabrix@${download.version}`]);
  assert.equal(aiBootstrap.document.limits.maxFiles, 16);
  assert.equal(aiBootstrap.execution.automatic, false);
  assert.doesNotMatch(text, /#key=|access=|\/playground\/room\//);
  const page = (await import("node:fs")).readFileSync(new URL("../app/ai/page.tsx", import.meta.url), "utf8");
  assert.doesNotMatch(page, /0\.3\.\d/, "versions on the page come from the release data");
  assert.doesNotMatch(page, /npm install -g crabrix/, "installing must not require a global package and a plugin");
});

test("the handoff keeps its existing schema and the task stays separate", async () => {
  // The dialog module is a client component, so this reads the format it must keep.
  const source = (await import("node:fs")).readFileSync(new URL("../components/playground/connect-ai-dialog.tsx", import.meta.url), "utf8");
  assert.match(source, /schema: "crabrix-handoff-v1"/);
  assert.doesNotMatch(source, /\?format=json/);
});
