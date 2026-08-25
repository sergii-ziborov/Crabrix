import assert from "node:assert/strict";
import test from "node:test";
import { compileRust, parseRustcDiagnostics } from "../server.mjs";

test("parses only coded rustc diagnostics", () => {
  const input = [
    JSON.stringify({
      $message_type: "diagnostic",
      message: "borrow conflict",
      code: { code: "E0502" },
      level: "error",
      spans: [
        {
          file_name: "/tmp/main.rs",
          line_start: 3,
          line_end: 3,
          column_start: 5,
          column_end: 9,
          is_primary: true,
          label: "mutable borrow occurs here",
          text: [{ text: "items.push(1);" }],
        },
      ],
    }),
    JSON.stringify({ $message_type: "diagnostic", message: "aborting", code: null, spans: [] }),
  ].join("\n");

  const diagnostics = parseRustcDiagnostics(input);
  assert.equal(diagnostics.length, 1);
  assert.equal(diagnostics[0].code, "E0502");
  assert.equal(diagnostics[0].spans[0].lineStart, 3);
});

test("returns an enriched E0502 diagnostic from real rustc", async () => {
  const result = await compileRust(`fn main() {
    let mut items = vec!["crab", "rust"];
    let first = &items[0];
    items.push("compiler");
    println!("{first}");
}`);

  assert.equal(result.ok, false);
  assert.equal(result.kind, "compile");
  assert.equal(result.diagnostics[0].code, "E0502");
  assert.equal(result.diagnostics[0].learning.causalSteps.length, 4);
  assert.match(result.diagnostics[0].learning.repairCode, /println!.*\n\s*items\.push/);
});

test("compiles and runs a valid Rust program", async () => {
  const result = await compileRust('fn main() { println!("hello from rust"); }', { run: true });
  assert.equal(result.ok, true);
  assert.equal(result.kind, "run");
  assert.equal(result.stdout.trim(), "hello from rust");
});

test("terminates a program that exceeds the runtime budget", async () => {
  const result = await compileRust("fn main() { loop {} }", { run: true });
  assert.equal(result.ok, false);
  assert.equal(result.kind, "runtime-timeout");
});
