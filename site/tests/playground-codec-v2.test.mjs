import { test } from "node:test";
import assert from "node:assert/strict";
import { Y, documentFromY, updateYDocument } from "../lib/playground-collab.ts";
import { isValidSourcePath, validatePlaygroundDocument } from "../lib/playground-document.ts";
import {
  PlanError, applyOperations, createProjectDoc, documentFromProject, fingerprint, isFileId, operationsFromChanges,
  operationsFromReplace, planOperations, projectRevision, readProject, schemaVersionOf,
} from "../lib/playground-codec-v2.ts";

const seeded = (seed = 1) => {
  const next = n => (seed = (seed * 1664525 + 1013904223) >>> 0) % n;
  return { next, random: length => Uint8Array.from({ length }, () => next(256)) };
};
const source = (files = { "main.rs": "fn main() {}\n" }, entryFile = "main.rs") => ({ schemaVersion: 1, name: "demo", entryFile, edition: "2024", files });
const project = (files, entryFile) => createProjectDoc(source(files, entryFile), seeded(Object.keys(files ?? {}).length + 3).random);
const fork = doc => { const next = new Y.Doc(); Y.applyUpdate(next, Y.encodeStateAsUpdate(doc)); return next; };
const sync = (...docs) => { for (const a of docs) for (const b of docs) if (a !== b) Y.applyUpdate(b, Y.encodeStateAsUpdate(a)); };
const idOf = (doc, path) => readProject(doc).files.find(file => file.path === path).id;
const fileOf = (doc, id) => readProject(doc).files.find(file => file.id === id);
const same = (...docs) => assert.equal(new Set(docs.map(doc => JSON.stringify(readProject(doc)))).size, 1);
// Every apply also checks that the planned result is what the document now reads.
const apply = (doc, operations, options = {}) => {
  const result = applyOperations(doc, operations, { origin: "structure", ...options });
  if (!result.alreadyApplied) assert.deepEqual(readProject(doc), result.plan.after);
  return result;
};
const refused = code => error => error instanceof PlanError && error.code === code;

test("the file fingerprint is 64-bit FNV-1a over UTF-8", () => {
  const reference = text => { let h = 0xcbf29ce484222325n; for (const byte of new TextEncoder().encode(text)) { h ^= BigInt(byte); h = BigInt.asUintN(64, h * 0x100000001b3n); } return h.toString(16).padStart(16, "0"); };
  assert.equal(fingerprint(""), "cbf29ce484222325");
  assert.equal(fingerprint("a"), "af63dc4c8601ec8c");
  for (const text of ["fn main() {}\n", "Hello, Crabrix! 🦀", "x".repeat(5000), "é́"]) assert.equal(fingerprint(text), reference(text));
});

test("a published v2 project reads back as the same runnable document, and v1 code refuses it", () => {
  const files = { "main.rs": "fn main() {}\n", "src/lib.rs": "pub fn x() {}\n", "Cargo.toml": "" }, doc = project(files);
  const state = readProject(doc);
  assert.equal(schemaVersionOf(doc), 2);
  assert.deepEqual(state.files.map(file => file.path), ["Cargo.toml", "main.rs", "src/lib.rs"]);
  assert.ok(state.files.every(file => isFileId(file.id)));
  assert.deepEqual([state.blocked, state.entryFallback, state.entryId], [[], false, idOf(doc, "main.rs")]);
  assert.deepEqual(documentFromProject(state), validatePlaygroundDocument(source(files)));
  assert.deepEqual(readProject(fork(fork(doc))), state);
  // Released web, SDK and app code all read through documentFromY and stop before writing.
  assert.throws(() => documentFromY(doc), /Invalid source project fields/);
  assert.throws(() => updateYDocument(doc, source()), /stable file IDs/);
});

test("reading leaves the document alone: no root is created and nothing is written", () => {
  const doc = project({ "main.rs": "fn main() {}\n", "empty.md": "" }), keys = [...doc.share.keys()], vector = Y.encodeStateVector(doc);
  readProject(doc); planOperations(doc, [{ kind: "create", path: "new.rs" }]);
  assert.deepEqual([...doc.share.keys()], keys);
  assert.deepEqual(Y.encodeStateVector(doc), vector);
  // A presence cursor naming an unknown file creates an empty root on one client only.
  const before = JSON.stringify(readProject(doc));
  doc.getText("t:" + "Z".repeat(22));
  assert.equal(JSON.stringify(readProject(doc)), before);
});

test("T17/T18: a rename keeps the file ID, so a delayed edit lands in the renamed file and the old path never returns", () => {
  const a = project({ "main.rs": "fn main() {}\n", "a.rs": "base\n" }), b = fork(a), offline = fork(a), id = idOf(a, "a.rs");
  b.getText("t:" + id).insert(0, "// from B\n");
  apply(a, [{ kind: "move", file: { path: "a.rs" }, path: "src/b.rs" }]);
  offline.getText("t:" + id).insert(4, "!");
  sync(a, b);
  same(a, b);
  assert.deepEqual([fileOf(a, id).path, fileOf(a, id).text], ["src/b.rs", "// from B\nbase\n"]);
  sync(a, b, offline);
  same(a, b, offline);
  assert.deepEqual(readProject(offline).files.map(file => file.path), ["main.rs", "src/b.rs"]);
  assert.equal(fileOf(offline, id).text, "// from B\nbase!\n");
});

test("a plan writes only the fields it changes, so a concurrent rename survives whichever client wins", () => {
  for (const [first, second] of [[1, 2], [2, 1]]) {
    const a = project({ "main.rs": "fn main() {}\n", "x.rs": "x" }), b = fork(a), id = idOf(a, "x.rs");
    a.clientID = first; b.clientID = second;
    apply(a, [{ kind: "move", file: { id }, path: "src/x.rs" }]);
    const plan = apply(b, [{ kind: "write", file: { id }, text: "x2" }, { kind: "create", path: "z.rs" }, { kind: "setName", name: "renamed" }]).plan;
    assert.deepEqual(plan.changes.map(change => Object.keys(change).sort()), [["id", "record", "text"], ["id", "path", "record"]]);
    sync(a, b);
    same(a, b);
    assert.deepEqual([fileOf(a, id).path, fileOf(a, id).text, readProject(a).name], ["src/x.rs", "x2", "renamed"]);
  }
});

test("T21: a delete keeps the text, and an edit after delete or purge shows as a recovery conflict", () => {
  const a = project({ "main.rs": "fn main() {}\n", "a.rs": "base" }), b = fork(a), id = idOf(a, "a.rs");
  apply(a, [{ kind: "delete", file: { id } }]);
  assert.deepEqual(readProject(a).recovery.map(row => [row.id, row.text, row.conflict]), [[id, "base", false]]);
  b.getText("t:" + id).insert(4, " late");
  sync(a, b);
  assert.deepEqual(readProject(a).recovery.map(row => [row.text, row.conflict, row.orphan]), [["base late", true, false]]);
  apply(a, [{ kind: "restore", id }]);
  assert.deepEqual([fileOf(a, id).text, readProject(a).recovery], ["base late", []]);

  apply(a, [{ kind: "delete", file: { id } }]);
  const c = fork(a);
  apply(a, [{ kind: "purge", id }]);
  assert.deepEqual(readProject(a).recovery, []);
  c.getText("t:" + id).insert(0, "after purge ");
  sync(a, c);
  assert.deepEqual(readProject(a).recovery.map(row => [row.text, row.conflict]), [["after purge ", true]]);
  same(a, c);
});

test("concurrent creates that broke v1 rooms read as a conflict name, and both texts stay", () => {
  const a = project({ "main.rs": "fn main() {}\n" }), b = fork(a);
  apply(a, [{ kind: "create", path: "helper.rs", text: "// a\n" }], { random: seeded(11).random });
  apply(b, [{ kind: "create", path: "Helper.rs", text: "// b\n" }], { random: seeded(12).random });
  apply(a, [{ kind: "create", path: "same.rs", text: "// a\n" }], { random: seeded(13).random });
  apply(b, [{ kind: "create", path: "same.rs", text: "// b\n" }], { random: seeded(14).random });
  sync(a, b);
  same(a, b);
  const state = readProject(a);
  for (const requested of [["helper.rs", "Helper.rs"], ["same.rs", "same.rs"]]) {
    const pair = state.files.filter(file => requested.includes(file.requestedPath)).sort((x, y) => x.id < y.id ? -1 : 1);
    assert.equal(pair.length, 2);
    assert.equal(pair[0].path, pair[0].requestedPath);
    assert.equal(pair[1].path, `conflict-${pair[1].id.slice(0, 8)}-${pair[1].requestedPath}`);
  }
  assert.deepEqual(state.files.filter(file => file.requestedPath === "same.rs").map(file => file.text).sort(), ["// a\n", "// b\n"]);
  assert.equal(Object.keys(documentFromProject(state).files).length, 5);
  // Renaming the loser resolves the conflict; nothing is renamed by reading.
  const loser = state.files.find(file => file.path.startsWith("conflict-") && file.requestedPath === "same.rs");
  apply(a, [{ kind: "move", file: { id: loser.id }, path: "same2.rs" }]);
  assert.ok(readProject(a).files.filter(file => file.requestedPath.startsWith("same")).every(file => file.path === file.requestedPath));
});

test("any state Yjs accepts reads without throwing, including wrong types and late writes to meta", () => {
  const doc = project({ "main.rs": "fn main() {}\n", "lib.md": "" }), other = fork(doc), main = idOf(doc, "main.rs");
  other.transact(() => {
    const meta = other.getMap("meta"), entries = other.getMap("entries");
    meta.set("schemaVersion", 3); meta.set("name", 42); meta.set("edition", "2099"); meta.set("entryFileId", "missing"); meta.set("origin", { url: "https://evil.example/x" });
    entries.set("not-a-file-id", new Y.Map());
    entries.set("A".repeat(22), "not a map");
    other.getText("t:" + "A".repeat(22)).insert(0, "orphaned text");
    const bad = new Y.Map(); entries.set("C".repeat(22), bad); bad.set("path", 7);
    entries.get(main).set("path", "../escape.rs");
    other.getText("future:root").insert(0, "from a newer client");
  });
  sync(doc, other);
  const state = readProject(doc);
  assert.deepEqual([state.name, state.edition, state.origin], ["playground", "2024", undefined]);
  assert.equal(fileOf(doc, main).path, `recovered-${main.slice(0, 8)}.txt`);
  assert.deepEqual(state.recovery.map(row => [row.id, row.orphan, row.text]), [["A".repeat(22), true, "orphaned text"]]);
  assert.deepEqual(state.blocked, ["no-entry"]);
  assert.throws(() => documentFromProject(state), /Rust source entry/);
  assert.equal(schemaVersionOf(doc), 3);
  // The orphan can be restored under a path of the user's choice.
  apply(doc, [{ kind: "restore", id: "A".repeat(22), path: "notes.md" }, { kind: "move", file: { id: main }, path: "main.rs" }]);
  assert.deepEqual(readProject(doc).blocked, []);
  assert.equal(fileOf(doc, "A".repeat(22)).text, "orphaned text");
});

test("T20: a plan is refused as a whole and leaves the document unchanged", () => {
  const doc = project({ "main.rs": "fn main() {}\n", "src/a.rs": "a", "src/b.rs": "b", "lib/b.rs": "x" }), vector = Y.encodeStateVector(doc);
  assert.throws(() => apply(doc, [{ kind: "moveFolder", from: "src", to: "lib" }]), refused("path-taken"));
  assert.throws(() => apply(doc, [{ kind: "create", path: "ok.rs" }, { kind: "create", path: "../bad.rs" }]), refused("invalid-path"));
  assert.throws(() => apply(doc, [{ kind: "move", file: { path: "src/a.rs" }, path: "LIB/c.rs" }]), refused("path-taken"));
  assert.throws(() => apply(doc, [{ kind: "delete", file: { path: "main.rs" } }, { kind: "delete", file: { path: "src/a.rs" } }, { kind: "delete", file: { path: "src/b.rs" } }, { kind: "delete", file: { path: "lib/b.rs" } }]), refused("limit"));
  assert.throws(() => apply(doc, [{ kind: "write", file: { path: "src/a.rs" }, text: "\u0000" }]), refused("invalid-operation"));
  assert.throws(() => apply(doc, [{ kind: "rename", file: { path: "src/a.rs" } }]), refused("invalid-operation"));
  assert.deepEqual(Y.encodeStateVector(doc), vector);
  const plan = apply(doc, [{ kind: "moveFolder", from: "src", to: "pkg" }, { kind: "copy", file: { path: "lib/b.rs" }, path: "pkg/c.rs" }]).plan;
  assert.deepEqual(plan.moved.map(move => [move.from, move.to]), [["src/a.rs", "pkg/a.rs"], ["src/b.rs", "pkg/b.rs"]]);
  assert.equal(plan.checkSuggested, true);
  assert.equal(fileOf(doc, plan.created[0]).text, "x");
});

test("deleting the entry picks the next Rust file on purpose; a concurrent loss of the entry falls back", () => {
  const a = project({ "main.rs": "fn main() {}\n", "other.rs": "fn main() {}\n", "notes.md": "" }), b = fork(a), other = idOf(a, "other.rs");
  apply(a, [{ kind: "delete", file: { path: "main.rs" } }]);
  assert.deepEqual([readProject(a).entryId, readProject(a).entryFallback], [other, false]);
  assert.throws(() => apply(a, [{ kind: "delete", file: { path: "other.rs" } }]), refused("limit"));
  assert.throws(() => apply(a, [{ kind: "setEntry", file: { path: "notes.md" } }]), refused("invalid-operation"));
  apply(b, [{ kind: "setEntry", file: { path: "main.rs" } }]);
  sync(a, b);
  same(a, b);
  assert.equal(readProject(a).entryId, other);
});

test("limits bind only what a plan grows, so a room pushed over a limit can still be reduced", () => {
  const files = Object.fromEntries(Array.from({ length: 14 }, (_, i) => [`f${i}.rs`, ""]));
  const a = project({ ...files, "main.rs": "fn main() {}\n" }), b = fork(a);
  apply(a, [{ kind: "create", path: "x.rs" }], { random: seeded(21).random });
  apply(b, [{ kind: "create", path: "y.rs" }], { random: seeded(22).random });
  sync(a, b);
  assert.deepEqual(readProject(a).blocked, ["files"]);
  assert.throws(() => documentFromProject(readProject(a)), /1–16 source files/);
  assert.throws(() => apply(a, [{ kind: "create", path: "z.rs" }]), refused("limit"));
  apply(a, [{ kind: "write", file: { path: "f0.rs" }, text: "// still editable\n" }]);
  apply(a, [{ kind: "delete", file: { path: "y.rs" } }]);
  assert.deepEqual(readProject(a).blocked, []);

  const big = project({ "main.rs": "fn main() {}\n", "big.rs": "" }), c = fork(big), id = idOf(big, "big.rs");
  big.getText("t:" + id).insert(0, "a".repeat(40 * 1024));
  c.getText("t:" + id).insert(0, "b".repeat(40 * 1024));
  sync(big, c);
  assert.deepEqual(readProject(big).blocked, ["file-bytes"]);
  assert.throws(() => apply(big, [{ kind: "write", file: { id }, text: fileOf(big, id).text + "x" }]), refused("limit"));
  apply(big, [{ kind: "write", file: { id }, text: fileOf(big, id).text.slice(20 * 1024) }]);
  assert.deepEqual(readProject(big).blocked, []);
});

test("deletes stop at the recovery budget and file records stop at 64", () => {
  const files = Object.fromEntries(Array.from({ length: 15 }, (_, i) => [`f${i}.md`, "x"]));
  const doc = project({ ...files, "main.rs": "fn main() {}\n" });
  apply(doc, Object.keys(files).map(path => ({ kind: "delete", file: { path } })));
  apply(doc, [{ kind: "create", path: "g.md", text: "y" }, { kind: "create", path: "h.md", text: "y" }]);
  apply(doc, [{ kind: "delete", file: { path: "g.md" } }]);
  assert.equal(readProject(doc).recovery.length, 16);
  assert.throws(() => apply(doc, [{ kind: "delete", file: { path: "h.md" } }]), refused("recovery-budget"));
  apply(doc, [{ kind: "purge", id: readProject(doc).recovery[0].id }, { kind: "delete", file: { path: "h.md" } }]);

  const bytes = project({ "main.rs": "fn main() {}\n", "a.md": "a".repeat(60 * 1024), "b.md": "b".repeat(40 * 1024) });
  apply(bytes, [{ kind: "delete", file: { path: "a.md" } }]);
  assert.throws(() => apply(bytes, [{ kind: "delete", file: { path: "b.md" } }]), refused("recovery-budget"));

  const records = project({ "main.rs": "fn main() {}\n" });
  // An empty file leaves no recovery row, but its record stays.
  for (let i = 1; i < 64; i++) apply(records, [{ kind: "create", path: "t.md" }, { kind: "delete", file: { path: "t.md" } }]);
  assert.deepEqual([readProject(records).records, readProject(records).recovery.length], [64, 0]);
  assert.throws(() => apply(records, [{ kind: "create", path: "t.md" }]), refused("limit"));
});

test("T16/T22: agent operations need the read revision and the reviewed plan, and a retry applies once", () => {
  const a = project({ "main.rs": "fn main() {}\n" }), b = fork(a), revision = projectRevision(readProject(a));
  const operations = [{ kind: "write", file: { path: "main.rs" }, text: "fn main() { println!(\"hi\"); }\n" }];
  const plan = planOperations(a, operations);
  assert.equal(plan.revision, revision);
  b.getText("t:" + idOf(b, "main.rs")).insert(0, "// other\n");
  sync(a, b);
  assert.throws(() => apply(a, operations, { origin: "mcp", expectedRevision: revision, planHash: plan.planHash, operationId: "op_000000001" }), refused("stale"));
  const fresh = projectRevision(readProject(a));
  assert.throws(() => apply(a, operations, { origin: "mcp", expectedRevision: fresh, planHash: plan.planHash }), refused("plan-changed"));
  const replanned = planOperations(a, operations);
  assert.equal(apply(a, operations, { origin: "mcp", expectedRevision: fresh, planHash: replanned.planHash, operationId: "op_000000001", now: 1 }).alreadyApplied, false);
  const vector = Y.encodeStateVector(a);
  assert.equal(apply(a, operations, { origin: "mcp", expectedRevision: fresh, operationId: "op_000000001", now: 2 }).alreadyApplied, true);
  assert.deepEqual(Y.encodeStateVector(a), vector);
  assert.throws(() => apply(a, [{ ...operations[0], text: "other" }], { origin: "mcp", operationId: "op_000000001" }), refused("operation-conflict"));
  // The record travels with the document, so a retry through another client is recognised.
  assert.equal(apply(fork(a), operations, { origin: "mcp", operationId: "op_000000001" }).alreadyApplied, true);
  for (let i = 0; i < 70; i++) apply(a, [{ kind: "write", file: { path: "main.rs" }, text: `fn main() {} // ${i}\n` }], { origin: "mcp", operationId: `op_${String(i).padStart(9, "0")}x`, now: 100 + i });
  const records = a.getMap("ops");
  assert.equal(records.size, 64);
  assert.equal(records.has("op_000000001"), false);
  assert.ok(records.has("op_000000069x"));
  assert.throws(() => applyOperations(a, operations, { origin: null }), /origin/);
});

test("Undo and cursors follow the file through rename, delete and restore", () => {
  const a = project({ "main.rs": "fn main() {}\n" }), b = fork(a), id = idOf(a, "main.rs"), text = a.getText("t:" + id);
  const undo = new Y.UndoManager(text, { trackedOrigins: new Set(["typing"]), captureTimeout: 0 });
  const cursor = Y.relativePositionToJSON(Y.createRelativePositionFromTypeIndex(text, 3));
  a.transact(() => text.insert(0, "// typed\n"), "typing");
  apply(a, [{ kind: "create", path: "lib.rs" }, { kind: "move", file: { id }, path: "src/main.rs" }]);
  apply(a, [{ kind: "write", file: { id }, text: "// typed\nfn main() { }\n" }]);
  apply(a, [{ kind: "delete", file: { id } }, { kind: "create", path: "keep.rs", text: "fn main() {}\n" }]);
  apply(a, [{ kind: "restore", id }]);
  undo.undo();
  assert.deepEqual([fileOf(a, id).path, fileOf(a, id).text], ["src/main.rs", "fn main() { }\n"]);
  sync(a, b);
  // Presence resolves a cursor only for a known file, after the text type exists locally.
  const shared = b.getText("t:" + id), position = Y.createAbsolutePositionFromRelativePosition(Y.createRelativePositionFromJSON(cursor), b);
  assert.ok(position.type === shared);
  assert.equal(position.index, 3);
});

test("the app's whole-project replace maps to operations by its acknowledged path -> ID baseline", () => {
  const a = project({ "main.rs": "fn main() {}\n", "util.rs": "pub fn u() {}\n" }), app = fork(a);
  const baseline = () => Object.fromEntries(readProject(app).files.map(file => [file.path, file.id]));
  const known = baseline(), util = known["util.rs"];
  apply(a, [{ kind: "move", file: { id: util }, path: "src/util.rs" }]);
  sync(a, app);
  // The app had not seen the rename and edits util.rs by its old path.
  const edited = source({ "main.rs": "fn main() {}\n", "util.rs": "pub fn u() { /* app */ }\n" });
  const writes = operationsFromReplace(readProject(app), known, edited);
  assert.deepEqual(writes.map(operation => operation.kind), ["write"]);
  apply(app, writes, { collisions: "allow" });
  assert.deepEqual([fileOf(app, util).path, fileOf(app, util).text], ["src/util.rs", "pub fn u() { /* app */ }\n"]);

  const renamed = source({ "bin.rs": "fn main() {}\n", "src/util.rs": "pub fn u() { /* app */ }\n", "new.rs": "" }, "bin.rs");
  const moves = operationsFromReplace(readProject(app), baseline(), renamed);
  assert.deepEqual(moves.map(operation => operation.kind), ["move", "create"]);
  apply(app, moves, { collisions: "allow" });
  assert.equal(fileOf(app, known["main.rs"]).path, "bin.rs");

  // Another participant deletes the file the app is still typing into: the text goes to recovery.
  const acknowledged = baseline();
  apply(a, [{ kind: "create", path: "X.rs", text: "// a\n" }], { random: seeded(31).random });
  sync(a, app);
  apply(a, [{ kind: "delete", file: { id: util } }]);
  sync(a, app);
  const late = source({ "bin.rs": "fn main() {}\n", "src/util.rs": "pub fn u() { /* late */ }\n", "new.rs": "", "x.rs": "// app\n" }, "bin.rs");
  const result = apply(app, operationsFromReplace(readProject(app), acknowledged, late), { collisions: "allow", random: seeded(32).random }).plan;
  assert.deepEqual(readProject(app).recovery.map(row => [row.id, row.text, row.conflict]), [[util, "pub fn u() { /* late */ }\n", true]]);
  assert.equal(result.conflicts.length, 1);
  assert.equal(readProject(app).files.filter(file => file.path !== file.requestedPath).length, 1);
  assert.deepEqual(readProject(app).blocked, []);
});

test("crabrix_apply_changes maps paths to writes, creates and deletes", () => {
  const doc = project({ "main.rs": "fn main() {}\n", "old.rs": "" }), state = readProject(doc);
  assert.deepEqual(operationsFromChanges(state, [{ path: "main.rs", text: "x" }, { path: "new.rs", text: "y" }, { path: "old.rs", text: null }]), [
    { kind: "write", file: { id: idOf(doc, "main.rs") }, text: "x" }, { kind: "create", path: "new.rs", text: "y" }, { kind: "delete", file: { path: "old.rs" } },
  ]);
});

test("random concurrency keeps every invariant of the projection", () => {
  const { next, random } = seeded(20261102), pool = ["a.rs", "A.rs", "b.rs", "src/a.rs", "Src/b.rs", "src/c.rs", "LICENSE", "notes.md", "a.rs/x.rs", "main.rs", "lib/d.rs"];
  let runs = 0, conflicts = 0, recoveries = 0;
  for (let run = 0; run < 120; run++) {
    const docs = [createProjectDoc(source({ "main.rs": "fn main() {}\n", "a.rs": "" }), random)];
    for (let i = 1; i < 4; i++) docs.push(fork(docs[0]));
    const marks = [];
    for (let step = 0; step < 40; step++) {
      const doc = docs[next(4)], state = readProject(doc), files = state.files, kind = next(12);
      const anyFile = files[next(Math.max(files.length, 1))], row = state.recovery[next(Math.max(state.recovery.length, 1))];
      try {
        if (kind < 4) {
          const id = kind === 3 && row ? row.id : anyFile?.id;
          if (!id) continue;
          const text = doc.getText("t:" + id), mark = `<${run}.${step}>`;
          doc.transact(() => text.insert(next(2) ? 0 : text.length, mark), "typing");
          marks.push(mark);
        } else if (kind === 4 && anyFile) apply(doc, [{ kind: "move", file: { id: anyFile.id }, path: pool[next(pool.length)] }], { random });
        else if (kind === 5) apply(doc, [{ kind: "create", path: pool[next(pool.length)] }], { random });
        else if (kind === 6 && anyFile) apply(doc, [{ kind: "delete", file: { id: anyFile.id } }], { random });
        else if (kind === 7 && row) apply(doc, [{ kind: "restore", id: row.id, ...(next(2) ? { path: pool[next(pool.length)] } : {}) }], { random });
        else if (kind === 8) apply(doc, [{ kind: "moveFolder", from: next(2) ? "src" : "lib", to: next(2) ? "lib" : "pkg" }], { random });
        else if (kind === 9 && anyFile) doc.getMap("entries").get(anyFile.id).set("path", pool[next(pool.length)]); // a stale client
        else if (kind === 10 && anyFile) apply(doc, [{ kind: "setEntry", file: { id: anyFile.id } }], { random });
        else if (kind === 11) { const other = docs[next(4)]; if (other !== doc) Y.applyUpdate(other, Y.encodeStateAsUpdate(doc)); }
      } catch (error) { if (!(error instanceof PlanError)) throw error; }
    }
    sync(...docs);
    same(...docs);
    const state = readProject(docs[0]), everything = [...state.files, ...state.recovery].map(item => item.text).join("");
    for (const mark of marks) assert.ok(everything.includes(mark), `run ${run} lost ${mark}`);
    const keys = state.files.map(file => file.path.normalize("NFC").toLowerCase());
    assert.equal(new Set(keys).size, keys.length);
    assert.ok(state.files.every(file => isValidSourcePath(file.path)));
    if (!state.blocked.length) assert.doesNotThrow(() => documentFromProject(state));
    assert.deepEqual(readProject(fork(docs[0])), state);
    runs++; conflicts += state.files.filter(file => file.path !== file.requestedPath).length; recoveries += state.recovery.length;
  }
  assert.equal(runs, 120);
  assert.ok(conflicts > 0 && recoveries > 0, "the random runs should reach conflicts and recovery rows");
});
