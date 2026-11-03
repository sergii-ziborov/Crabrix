// Runs the built Crabrix/Resources/PlaygroundCodec.js like JavaScriptCore (no browser
// globals) as several app clients in format v2 rooms. Build the bundle first:
//   node scripts/build_playground_bridge.mjs
//   node --experimental-strip-types scripts/probes/playground/native-codec-v2.mjs
import { readFileSync } from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
import * as Y from "../../../site/node_modules/yjs/dist/yjs.mjs";
import { createProjectDoc, readProject, applyOperations } from "../../../site/lib/playground-codec-v2.ts";

const bundle = readFileSync(new URL("../../../Crabrix/Resources/PlaygroundCodec.js", import.meta.url), "utf8");
function client() {
  const context = vm.createContext({ __crabrixRandom: n => Array.from({ length: n }, () => Math.floor(Math.random() * 2 ** 32)), __crabrixRuntimeCrypto: () => "{}", __crabrixSourceOrigin: () => null });
  vm.runInContext(bundle, context);
  assert.equal(vm.runInContext("typeof URL", context), "undefined");
  return request => { const value = JSON.parse(vm.runInContext("CrabrixPlaygroundCodec.call", context)(JSON.stringify(request))); if (value.error) throw new Error(value.error); return value; };
}
const b64 = bytes => Buffer.from(bytes).toString("base64");

// A v2 room snapshot, as the web publishes it. Fixed IDs so the Swift test can embed it.
let seed = 0;
const fixed = n => Uint8Array.from({ length: n }, (_, i) => (seed++ * 37 + i * 101) & 255);
const source = { schemaVersion: 1, name: "shared", entryFile: "main.rs", edition: "2024", files: { "main.rs": "mod helper;\nfn main() { helper::run(); }\n", "helper.rs": "pub fn run() {}\n" } };
const room = createProjectDoc(source, fixed);
const snapshot = b64(Y.encodeStateAsUpdate(room));

const a = client(), b = client();
const ja = a({ type: "state", snapshot, events: [], codec: 2 }), jb = b({ type: "state", snapshot, events: [], codec: 2 });
assert.deepEqual(ja.document, source); assert.deepEqual(jb.document, source);
assert.equal(ja.recovery, 0);
// A renames helper.rs in a whole-project replace; B edits helper.rs by its old path.
const renamed = { ...source, files: { "main.rs": source.files["main.rs"], "util/helper.rs": source.files["helper.rs"] } };
const ra = a({ type: "replace", document: renamed });
const rb = b({ type: "file", path: "helper.rs", text: "pub fn run() { println!(\"B\"); }\n" });
assert.ok(ra.update && rb.update);
const fa = a({ type: "update", bytes: rb.update }), fb = b({ type: "update", bytes: ra.update });
assert.deepEqual(fa.document, fb.document);
assert.deepEqual(Object.keys(fb.document.files).sort(), ["main.rs", "util/helper.rs"]);
assert.equal(fb.document.files["util/helper.rs"], "pub fn run() { println!(\"B\"); }\n");
assert.deepEqual(fb.renamed, { "helper.rs": "util/helper.rs" });
// A deletes via replace; B's late edit by old ID lands in recovery.
const deleted = { ...renamed, files: { "main.rs": renamed.files["main.rs"] } };
const da = a({ type: "replace", document: deleted });
const lb = b({ type: "file", path: "util/helper.rs", text: "late\n" });
const xa = a({ type: "update", bytes: lb.update }), xb = b({ type: "update", bytes: da.update });
assert.deepEqual(xa.document, xb.document);
assert.equal(xa.recovery, 1); assert.equal(xb.recovery, 1);
// Remote cursor positions resolve to the shown path.
const sel = b({ type: "selection", file: "main.rs", anchor: 4, head: 10 });
const seen = a({ type: "presence", bytes: sel.presence });
assert.deepEqual(seen.selections.map(s => [s.file, s.anchor, s.head]), [["main.rs", 4, 10]]);
// A blocked project returns no document: the app keeps its copy read only.
const blockedRoom = createProjectDoc(source);
// Concurrent typing can push a file over its limit; operations alone refuse to.
blockedRoom.getText("t:" + readProject(blockedRoom).files.find(file => file.path === "main.rs").id).insert(0, "x".repeat(70 * 1024));
const c = client(), jc = c({ type: "state", snapshot: b64(Y.encodeStateAsUpdate(blockedRoom)), events: [], codec: 2 });
assert.equal(jc.document, undefined); assert.deepEqual(jc.blocked, ["file-bytes"]);
assert.throws(() => c({ type: "runtime-source" }), /64 KiB/);
// The snapshot is base64 and goes through a copy; a 400 KiB one crosses the bridge.
const snap = a({ type: "snapshot" });
assert.ok(typeof snap.snapshot === "string" && Buffer.from(snap.snapshot, "base64").length > 10);
// The largest legal room: 128 KiB live, 96 KiB in recovery, then interleaved typing from two clients.
const large = createProjectDoc(source), other = new Y.Doc();
applyOperations(large, [{ kind: "create", path: "r.rs", text: "r".repeat(45 * 1024) }, { kind: "create", path: "s.rs", text: "s".repeat(45 * 1024) }], { origin: "structure" });
applyOperations(large, [{ kind: "delete", file: { path: "r.rs" } }, { kind: "delete", file: { path: "s.rs" } }], { origin: "structure" });
applyOperations(large, [{ kind: "create", path: "a.rs", text: "y".repeat(63 * 1024) }, { kind: "create", path: "b.rs", text: "z".repeat(63 * 1024) }], { origin: "structure" });
Y.applyUpdate(other, Y.encodeStateAsUpdate(large));
const target = readProject(large).files.find(file => file.path === "a.rs").id;
for (let i = 0; i < 3000; i++) {
  const doc = i % 2 ? large : other, text = doc.getText("t:" + target);
  text.delete((i * 7919) % (text.length - 1), 1); text.insert((i * 104729) % text.length, "q");
  Y.applyUpdate(i % 2 ? other : large, Y.encodeStateAsUpdate(doc, Y.encodeStateVector(i % 2 ? other : large)));
}
const largeBytes = Y.encodeStateAsUpdate(large), largeSnapshot = b64(largeBytes);
assert.ok(largeBytes.length > 256 * 1024 && largeBytes.length <= 512 * 1024, String(largeBytes.length));
const d = client(), jd = d({ type: "state", snapshot: largeSnapshot, events: [], codec: 2 });
assert.equal(jd.recovery, 2); assert.equal(jd.document.files["a.rs"].length, 63 * 1024);
assert.ok(JSON.stringify({ type: "state", snapshot: largeSnapshot, events: [] }).length < 2_000_000);
// v1 keeps working with arrays and base64, and a v1 snapshot is not compacted.
const e = client(), je = e({ type: "initialize", document: source });
assert.deepEqual(je.document, source);
const f = client();
assert.deepEqual(f({ type: "state", snapshot: e({ type: "snapshot" }).snapshot, events: [] }).document, source);
assert.deepEqual(client()({ type: "state", snapshot: Array.from(Buffer.from(e({ type: "snapshot" }).snapshot, "base64")), events: [] }).document, source);
// A v2 room whose document is v1 opens read only.
const g = client(), jg = g({ type: "state", snapshot: e({ type: "snapshot" }).snapshot, events: [], codec: 2 });
assert.equal(jg.formatMismatch, true);
assert.throws(() => g({ type: "replace", document: source }), /read only/);
console.log("native codec v2 probe ok; largest snapshot", largeSnapshot.length, "base64 characters");
