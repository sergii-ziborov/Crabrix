const assert = require('node:assert/strict');
const fs = require('node:fs');
const { chromium } = require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const origin = process.env.CRABRIX_PLAYGROUND_ORIGIN || 'http://127.0.0.1:3393';
const output = 'build/debugger-20261027';
const source = 'fn add(a: i32, b: i32) -> i32 {\n let c = a + b;\n c\n}\nfn main() {\n let mut total = 0;\n for i in 0..3 {\n total += add(i,1);\n }\n println!("total={total}");\n}\n';
(async () => {
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.goto(origin + '/playground/'); await page.waitForSelector('.cm-content');
    assert.equal(await page.evaluate(() => crossOriginIsolated && typeof SharedArrayBuffer !== 'undefined'), true);
    await page.getByRole('button', { name: 'Share Playground', exact: true }).click();
    assert.equal(await page.getByRole('button', { name: '1 hour', exact: true }).getAttribute('aria-pressed'), 'true');
    await page.screenshot({ path: output + '/share-hour-desktop.png' });
    await page.keyboard.press('Escape');
    await page.locator('.cm-content').fill(source);
    const paused = async (file, line, name) => {
      try { await page.waitForFunction(({file,line,name}) => document.querySelector('.pg-debug-location')?.textContent.includes(`${file}:${line} · ${name}`), {file,line,name}, {timeout:45000}); }
      catch(error) { console.log('DEBUG STATE',await page.locator('body').innerText()); throw error; }
    };
    await page.getByRole('button', { name: 'Debug Rust', exact: true }).click();
    // Acquisition measures download inactivity separately from execution. A
    // public first transfer may take longer than a local 45-second compile.
    await page.getByRole('button', { name: '▶ Continue', exact: true }).waitFor({ timeout: 300000 });
    await paused('main.rs', 6, 'main'); console.log('PASS actual Rust stops at entry');
    // No HTTP path can provide compilation, stepping, execution or state after
    // acquisition. All subsequent Debug and Run builds use the local Worker.
    await page.route('**/*', route => route.abort());
    await page.getByRole('button', { name: 'Add breakpoint at line 8', exact: true }).click();
    console.log('SET breakpoint');
    await page.getByRole('button', { name: 'Step over', exact: true }).click(); await paused('main.rs', 7, 'main');
    assert.match(await page.locator('.pg-debug-panel table').innerText(), /total\s+i32\s+0/);
    await page.getByRole('button', { name: '▶ Continue', exact: true }).click(); await paused('main.rs', 8, 'main');
    assert.match(await page.locator('.pg-debug-panel table').innerText(), /i\s+i32\s+0/);
    console.log('PASS breakpoint and loop locals');
    await page.getByRole('button', { name: 'Step into', exact: true }).click(); await paused('main.rs', 2, 'add');
    assert.equal(await page.locator('.pg-frame').count(), 2);
    assert.match(await page.locator('.pg-debug-panel table').innerText(), /b\s+i32\s+1/);
    await page.getByRole('button', { name: 'Step over', exact: true }).click(); await paused('main.rs', 3, 'add');
    assert.match(await page.locator('.pg-debug-panel table').innerText(), /c\s+i32\s+1/);
    await page.screenshot({ path: output + '/browser-debug-locals.png' });
    await page.getByRole('button', { name: 'Step out', exact: true }).click(); await paused('main.rs', 9, 'main');
    assert.match(await page.locator('.pg-debug-panel table').innerText(), /total\s+i32\s+1/);
    console.log('PASS step into, over, out and live call stack');
    await page.getByRole('button', { name: 'Remove breakpoint at line 8', exact: true }).click();
    await page.getByRole('button', { name: '▶ Continue', exact: true }).click();
    await page.getByRole('button', { name: '▶ Run', exact: true }).waitFor();
    await page.getByRole('tab', { name: 'Output', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.pg-output pre')?.textContent === 'total=6\n');
    assert.equal((await page.locator('.cm-content').innerText()).trim(), source.trim());
    // Compile again with all HTTP blocked, and exercise Stop in a running loop.
    await page.locator('.cm-content').fill('fn main() { let mut n = 0u32; loop { n = n.wrapping_add(1); std::hint::black_box(n); } }');
    await page.getByRole('button', { name: 'Debug Rust', exact: true }).click();
    await page.getByRole('button', { name: '▶ Continue', exact: true }).waitFor();
    await page.getByRole('button', { name: '▶ Continue', exact: true }).click();
    await page.waitForTimeout(150);
    await page.getByRole('button', { name: '■ Stop', exact: true }).click();
    await page.getByRole('button', { name: '▶ Run', exact: true }).waitFor();
    console.log('PASS offline Debug compilation and responsive Stop');
    assert.deepEqual(errors, []);
    fs.writeFileSync(output + '/browser-debug-result.json', JSON.stringify({at:new Date().toISOString(),origin,passed:['entry pause','breakpoint','loop locals','step into','step over','step out','call stack','actual stdout','source preserved','offline compilation','responsive Stop'],backendExecution:false},null,2));
  } finally { await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
