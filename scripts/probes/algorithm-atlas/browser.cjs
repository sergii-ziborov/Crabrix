#!/usr/bin/env node
// PLAYWRIGHT_MODULE may point to the workspace's bundled Playwright package.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const origin = process.env.ATLAS_ORIGIN || 'http://127.0.0.1:3393';
const output = process.env.ATLAS_OUTPUT || 'build/algorithm-atlas/browser';
const sessionFile = process.env.ATLAS_SESSION;
fs.mkdirSync(output, { recursive: true });
const manifest = JSON.parse(fs.readFileSync('site/content/algorithm-traces/manifest.json'));
const traceFor = id => JSON.parse(fs.readFileSync(`site/content/algorithm-traces/${manifest.lessons[id]}.json`));
const result = { origin, layouts: [], lessons: [], pageErrors: [], localPlaybackOffline: false, authGate: false };

async function screenshot(page, name) {
  const style = await page.addStyleTag({ content: '.site-header{visibility:hidden!important}nextjs-portal{display:none!important}' });
  await page.locator('.algorithm-atlas').screenshot({ path: path.join(output, `${name}.png`) });
  await style.evaluate(n => n.remove());
}

async function main() {
  const browser = await chromium.launch({ headless: true });
  try {
    for (const scheme of ['dark', 'light']) for (const width of [320, 390, 768, 1024, 1440]) {
      const context = await browser.newContext({ viewport: { width, height: 1000 }, colorScheme: scheme, reducedMotion: 'reduce' });
      const page = await context.newPage(); page.on('pageerror', e => result.pageErrors.push(String(e)));
      const response = await page.goto(`${origin}/learn/algorithms/`); assert.equal(response.status(), 200);
      const atlas = page.locator('.algorithm-atlas'); await atlas.waitFor();
      await atlas.getByRole('button', { name: 'Next →', exact: true }).click();
      const slider = atlas.getByRole('slider', { name: 'Execution step' });
      await slider.fill('4');
      const before = await atlas.locator('.atlas-state-pane').innerText();
      await atlas.getByRole('button', { name: 'Next →', exact: true }).click();
      await atlas.getByRole('button', { name: '← Back', exact: true }).click();
      assert.equal(await atlas.locator('.atlas-state-pane').innerText(), before, 'rewind restores the exact state');
      const geometry = await page.evaluate(() => {
        const a = document.querySelector('.algorithm-atlas').getBoundingClientRect();
        const active = document.querySelector('.atlas-code-line.is-executing').getBoundingClientRect();
        const pane = document.querySelector('.atlas-code-scroll').getBoundingClientRect();
        const state = document.querySelector('.atlas-state-pane').getBoundingClientRect();
        const code = document.querySelector('.atlas-code-pane').getBoundingClientRect();
        return { pageWidth: document.documentElement.scrollWidth, width: innerWidth, left: a.left, right: a.right, lineVisible: active.top >= pane.top - 1 && active.bottom <= pane.bottom + 1, stacked: code.top >= state.bottom - 1 };
      });
      assert.ok(geometry.pageWidth <= width + 1 && geometry.left >= 0 && geometry.right <= width + 1, JSON.stringify(geometry));
      assert.equal(geometry.lineVisible, true, 'code scroll stays inside its panel');
      assert.equal(geometry.stacked, width <= 700);
      await screenshot(page, `demo-${width}-${scheme}`);
      if (width === 390 && scheme === 'dark') {
        // All controls must still work after the server becomes unreachable.
        await context.setOffline(true);
        await atlas.getByLabel('Playback speed').selectOption('300');
        await atlas.getByRole('button', { name: '▶ Play', exact: true }).click();
        await page.waitForTimeout(400);
        await atlas.getByRole('button', { name: 'Ⅱ Pause', exact: true }).click();
        const stopped = await slider.inputValue(); await page.waitForTimeout(500);
        assert.equal(await slider.inputValue(), stopped, 'pause stops the timer');
        await slider.fill('10'); assert.equal(await atlas.locator('.atlas-output pre').innerText(), '3\n');
        assert.equal(await atlas.getByRole('button', { name: 'Next →', exact: true }).isDisabled(), true);
        await atlas.getByRole('button', { name: 'Restart walkthrough', exact: true }).click();
        assert.equal(await slider.inputValue(), '0');
        result.localPlaybackOffline = true;
        await context.setOffline(false);
      }
      result.layouts.push({ scheme, width, ...geometry }); await context.close();
    }
    const context = await browser.newContext({ viewport: { width: 1024, height: 1000 }, colorScheme: 'dark' });
    const page = await context.newPage(); page.on('pageerror', e => result.pageErrors.push(String(e)));
    const id = 'algorithm.dijkstra.model';
    const anonymous = await page.goto(`${origin}/learn/algorithms/${id}/`);
    const html = await anonymous.text();
    assert.equal(await page.locator('.algorithm-atlas').count(), 0);
    assert.ok(!html.includes(traceFor(id).sourceHash), 'full trace is absent from anonymous HTML/RSC');
    const privateFile = await context.request.get(`${origin}/content/algorithm-traces/${manifest.lessons[id]}.json`);
    assert.equal(privateFile.status(), 404, 'full lesson data has no public file URL');
    assert.ok(await page.getByRole('link', { name: 'Try an interactive algorithm walkthrough →' }).count());
    result.authGate = true;
    if (sessionFile) {
      const { token } = JSON.parse(fs.readFileSync(sessionFile));
      await context.addCookies([{ name: origin.startsWith('https:') ? '__Host-crabrix_session' : 'crabrix_session', value: token, url: origin, secure: origin.startsWith('https:') }]);
      for (const [pattern, variable, kind] of [
        ['insertion-sort', 'values', '.atlas-cells'],
        ['dijkstra', 'graph', '.atlas-graph'],
        ['list-reversal', 'reversed', '.atlas-tree'],
        ['longest-common-subsequence', 'dp', '.atlas-matrix'],
        ['treap', 'root', '.atlas-tree'],
        ['frequency-counting', 'counts', '.atlas-map'],
        ['hash-membership', 'seen', '.atlas-set'],
        ['xor-cancellation', 'acc', '.atlas-locals'],
      ]) {
        const lessonID = `algorithm.${pattern}.model`, trace = traceFor(lessonID);
        const candidates = trace.frames.map((f, index) => ({ f, index })).filter(({ f }) => f.locals.some(([n, ref]) => n === variable && (kind !== '.atlas-tree' || trace.values[ref].data.kind === 'named')));
        let selected = candidates[Math.min(candidates.length - 1, Math.floor(candidates.length / 2))];
        assert.ok(selected, `${pattern}: expected ${variable} in real trace`);
        const response = await page.goto(`${origin}/learn/algorithms/${lessonID}/`); assert.equal(response.status(), 200);
        const atlas = page.locator('.algorithm-atlas'); await atlas.waitFor();
        await atlas.getByRole('slider', { name: 'Execution step' }).fill(String(selected.index));
        const tab = atlas.locator('.atlas-collection-tabs').getByRole('button', { name: new RegExp(`^${variable}( •)?$`) });
        if (await tab.count()) await tab.click();
        assert.ok(await atlas.locator(kind).count(), `${pattern}: expected ${kind}`);
        if (pattern === 'dijkstra') {
          const edgeStep = trace.frames.findIndex(f => trace.sites[f.site].edge && f.locals.some(([n]) => n === 'u') && f.locals.some(([n]) => n === 'v'));
          await atlas.getByRole('slider', { name: 'Execution step' }).fill(String(edgeStep));
          assert.equal(await atlas.locator('.atlas-graph g.is-active:has(line)').count(), 1, 'active edge follows the actual loop direction');
        }
        await screenshot(page, pattern);
        await atlas.getByRole('slider', { name: 'Execution step' }).fill(String(trace.frames.length));
        assert.equal(await atlas.locator('.atlas-output pre').innerText(), trace.stdout);
        result.lessons.push({ lessonID, visualization: kind, output: trace.stdout.trim() });
      }
    }
    assert.deepEqual(result.pageErrors, []);
    await context.close();
    fs.writeFileSync(path.join(output, 'result.json'), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify({ layouts: result.layouts.length, lessons: result.lessons.length, offline: result.localPlaybackOffline, authGate: result.authGate, errors: result.pageErrors.length }));
  } finally { await browser.close(); }
}
main().catch(e => { console.error(e); process.exit(1); });
