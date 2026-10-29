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


test('browser examples retain every character while highlighting JSON, HTML and TypeScript', () => {
  for (const [language, source] of [
    ['json', '{"private":true,"version":"1.0.0"}'],
    ['html', '<!-- offline 🦀 --><script type="module" src="/src/main.tsx"></script>'],
    ['typescript', 'import { useState } from "react"; const [n] = useState<number>(0); return <button>{n}</button>;'],
  ]) {
    const tokens = codeTokens(source, language);
    assert.equal(tokens.map(t => t.value).join(''), source);
    assert.ok(tokens.some(t => t.kind === 'string'));
    assert.ok(tokens.some(t => t.kind === (language === 'html' ? 'type' : 'keyword')));
  }
});

test('Go SDK examples preserve raw backslashes, rune strings and comments exactly', () => {
  const source = 'package main\n// crab 🦀\nfunc main() { s := `raw\\`; r := \'🦀\'; defer close(s); _ = r }';
  const tokens = codeTokens(source, 'go');
  assert.equal(tokens.map(t => t.value).join(''), source);
  assert.ok(tokens.some(t => t.value === 'func' && t.kind === 'keyword'));
  assert.ok(tokens.some(t => t.value === 'defer' && t.kind === 'keyword'));
  assert.ok(tokens.some(t => t.value === '`raw\\`' && t.kind === 'string'));
});
