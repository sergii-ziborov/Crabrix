import { test } from 'node:test';
import assert from 'node:assert/strict';
import { codeLanguage, codeTokens } from '../lib/code-highlighting.ts';

test('lesson highlighting recognizes Rust, TOML, SQL and mixed source markers without changing text', () => {
  const examples = [
    ['rust', 'fn main() { let crab = \'🦀\'; println!("{crab}"); }'],
    ['toml', '# Cargo.toml\n[dependencies]\nserde = { version = "1", features = ["derive"] }'],
    ['sql', "-- PostgreSQL\nCREATE INDEX ix ON events (tenant_id, at);\nEXPLAIN SELECT * FROM events WHERE kind = 'click';"],
    ['toml', '# my-derive/Cargo.toml\n[lib]\nproc-macro = true\n// my-derive/src/lib.rs\nuse proc_macro::TokenStream;'],
  ];
  for (const [language, source] of examples) {
    assert.equal(codeLanguage(source), language);
    assert.equal(codeTokens(source).map(t => t.value).join(''), source);
  }
  assert.ok(codeTokens(examples[0][1]).some(t => t.value === "'🦀'" && t.kind === 'string'));
  assert.ok(codeTokens(examples[1][1]).some(t => t.value === 'serde' && t.kind === 'attribute'));
  assert.ok(codeTokens(examples[2][1]).some(t => t.value === 'EXPLAIN' && t.kind === 'keyword'));
  assert.ok(codeTokens(examples[3][1]).some(t => t.value === 'use' && t.kind === 'keyword'));
});
