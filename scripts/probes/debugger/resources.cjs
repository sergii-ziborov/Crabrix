const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const origin = process.env.CRABRIX_PLAYGROUND_ORIGIN || 'http://127.0.0.1:3393';
const output = 'build/debugger-resources-20261028';
const resource = 'Crab 🦀 <b>local</b>';
// Text resources follow the existing guest Playground file policy. The exact
// built-in HTML/CSS/JS generator is separately exercised by the native tests.
const source = 'fn main() {\n let label=include_str!("message.txt");\n let bytes=include_bytes!("message.txt");\n let source=include_str!("main.rs");\n let source_size:usize=source.len();\n assert_eq!(label.as_bytes(),bytes);\n println!("{label}|{}|{source_size}",bytes.len());\n}\n';

(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto(origin + '/playground/'); await page.waitForSelector('.cm-content');
    page.once('dialog', d => d.accept('message.txt'));
    await page.getByRole('button', { name: 'Add source file', exact: true }).click();
    await page.locator('.cm-content').fill(resource);
    await page.locator('.pg-file').filter({ hasText: 'main.rs' }).click();
    await page.locator('.cm-content').fill(source);
    await page.getByRole('button', { name: 'Debug Rust', exact: true }).click();
    await page.getByRole('button', { name: '▶ Continue', exact: true }).waitFor({ timeout: 300000 });
    const paused = line => page.waitForFunction(line => document.querySelector('.pg-debug-location')?.textContent.includes(`main.rs:${line} · main`), line, { timeout: 45000 });
    await paused(2);
    await page.route('**/*', route => route.abort());
    await page.getByRole('button', { name: 'Add breakpoint at line 7', exact: true }).click();
    await page.getByRole('button', { name: '▶ Continue', exact: true }).click(); await paused(7);
    assert.match(await page.locator('.pg-debug-panel table').innerText(), new RegExp(`source_size\\s+usize\\s+${Buffer.byteLength(source)}`));
    await page.screenshot({ path: output + '/browser-resource-breakpoint.png' });
    await page.getByRole('button', { name: 'Step over', exact: true }).click(); await paused(8);
    await page.getByRole('button', { name: 'Remove breakpoint at line 7', exact: true }).click();
    await page.getByRole('button', { name: '▶ Continue', exact: true }).click();
    await page.getByRole('button', { name: '▶ Run', exact: true }).waitFor();
    await page.getByRole('tab', { name: 'Output', exact: true }).click();
    const expected = `${resource}|${Buffer.byteLength(resource)}|${Buffer.byteLength(source)}\n`;
    await page.waitForFunction(expected => document.querySelector('.pg-output pre')?.textContent === expected, expected);
    assert.equal((await page.locator('.cm-content').innerText()).trim(), source.trim());
    await page.getByRole('button', { name: '▶ Run', exact: true }).click();
    await page.getByRole('button', { name: '▶ Run', exact: true }).waitFor({ timeout: 60000 });
    assert.equal(await page.locator('.pg-output pre').first().textContent(), expected);
    assert.deepEqual(errors, []);
    fs.writeFileSync(output + '/browser-result.json', JSON.stringify({ at: new Date().toISOString(), origin, passed: ['included UTF8 resource', 'include_bytes equality', 'original Rust source bytes', 'real breakpoint at line 7', 'step over', 'local variable', 'normal Run parity', 'source preserved', 'network blocked after acquisition'], stdout: expected, backendExecution: false, pageErrors: errors }, null, 2));
    console.log('PASS browser included resources, actual breakpoint, source bytes and offline Run/Debug parity');
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
