import { test } from "node:test";
import assert from "node:assert/strict";
import { runtimeSource, runtimeSourceRevision } from "../../../site/lib/playground-runtime-source";
import { newPlaygroundDocument, validatePlaygroundDocument } from "../../../site/lib/playground-document";

const source = { ...newPlaygroundDocument(), name: "Unicode 🦀", files: { "🦀.rs": 'pub const N: u8 = 1;\n', "main.rs": 'fn main() { println!("🦀"); }\n', "é.rs": "// café\n" } };
test("source identity preserves exact Unicode bytes with locale-independent path ordering", async () => {
  const value = runtimeSource(source);
  assert.deepEqual(value.paths, ["main.rs", "é.rs", "🦀.rs"]);
  assert.equal(value.canonical, '["crabrix-runtime-source-v1","Unicode 🦀","main.rs","2024",[["main.rs","fn main() { println!(\\"🦀\\"); }\\n"],["é.rs","// café\\n"],["🦀.rs","pub const N: u8 = 1;\\n"]]]');
  const reversed = { ...source, files: Object.fromEntries(Object.entries(source.files).reverse()), origin: { url: "https://github.com/example/source", commit: "a".repeat(40) } };
  assert.equal(await runtimeSourceRevision(source), await runtimeSourceRevision(reversed));
  assert.notEqual(await runtimeSourceRevision(source), await runtimeSourceRevision({ ...source, edition: "2021" }));
  assert.notEqual(await runtimeSourceRevision(source), await runtimeSourceRevision({ ...source, entryFile: "é.rs" }));
  assert.notEqual(await runtimeSourceRevision(source), await runtimeSourceRevision({ ...source, files: { ...source.files, "é.rs": "// cafe\u0301\n" } }));
});

test("native path aliases and unpaired surrogates are refused before a room merge", () => {
  for (const extra of [
    { "MAIN.rs": "case alias" }, { "e\u0301.rs": "Unicode alias" }, { "main.rs/child.rs": "file directory collision" },
    { "Folder/a.rs": "a", "folder/b.rs": "b" }, { ["🦀".repeat(70) + ".rs"]: "long component" },
    { "bad.rs": "unpaired \ud800" }, { ["bad\udfff.rs"]: "bad path" },
  ]) assert.throws(() => validatePlaygroundDocument({ ...source, files: { ...source.files, ...extra } }));
  assert.throws(() => runtimeSource({ ...source, name: "bad\ud800" }));
  assert.equal(source.files["é.rs"], "// café\n");
});
