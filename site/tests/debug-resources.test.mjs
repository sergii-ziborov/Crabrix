import { test } from 'node:test';
import assert from 'node:assert/strict';
import { instrumentRust } from '../lib/rust-debug-instrumentation.ts';

test('resource macros preserve web asset text and original breakpoint coordinates', () => {
  const source = 'use std::fs;\nfn main() {\n fs::write("/sandbox/index.html",include_str!("../web/index.html")).unwrap();\n fs::write("/sandbox/styles.css",include_str!(r#"../web/styles.css"#)).unwrap();\n fs::write("/sandbox/app.js",include_bytes!("../web/app.js")).unwrap();\n}\n';
  const files = { 'src/main.rs': source, 'web/index.html': '<h1>Crab 🦀</h1>', 'web/styles.css': 'body{color:coral}', 'web/app.js': 'console.log("local")' };
  const plan = instrumentRust(files, 'src/main.rs');
  for (const path of ['web/index.html', 'web/styles.css', 'web/app.js']) assert.equal(plan.files[path], files[path]);
  assert.ok(plan.sites.some(s => s.file === 'src/main.rs' && s.line === 5));
  assert.ok(plan.files['src/main.rs'].includes('include_str!("../web/index.html")'));
  assert.equal(files['src/main.rs'], source, 'editable source is never mutated');
});

test('including instrumented Rust as data uses an original, deduplicated sidecar', () => {
  const source = 'fn main(){let a=std::include_str!(r#"main.rs"#);let b=include_bytes!("/work/main.rs");println!("{} {}",a.len(),b.len());}';
  const plan = instrumentRust({ 'main.rs': source }, 'main.rs');
  const originals = Object.entries(plan.files).filter(([path]) => path.endsWith('.txt'));
  assert.equal(originals.length, 1);
  assert.equal(originals[0][1], source);
  assert.ok(plan.files['main.rs'].includes(`std::include_str!("${originals[0][0]}")`));
  assert.ok(plan.files['main.rs'].includes(`include_bytes!("${originals[0][0]}")`));
});

test('native build scripts stay original and sidecar names never overwrite project files', () => {
  const source = 'fn main(){println!("{}",include_str!("main.rs").len());}';
  const files = { 'main.rs': source, '__crabrix_debug_original_1.txt': 'user data', 'build.rs': 'fn main(){}' };
  const plan = instrumentRust(files, 'main.rs', ['build.rs']);
  assert.equal(plan.files['build.rs'], files['build.rs']);
  assert.equal(plan.files['__crabrix_debug_original_1.txt'], 'user data');
  assert.ok(Object.values(plan.files).includes(source));
  assert.ok(!plan.sites.some(s => s.file === 'build.rs'));
});

test('Rust Unicode and hex path escapes resolve to the original source asset', () => {
  const source = String.raw`fn main(){let a=include_str!("\u{6d}\x61in.rs");println!("{}",a.len());}`;
  const plan = instrumentRust({ 'main.rs': source }, 'main.rs');
  assert.equal(Object.entries(plan.files).filter(([key]) => key.endsWith('.txt'))[0][1], source);
});
