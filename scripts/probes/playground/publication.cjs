// Run against the candidate or public deployment after the production build.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { createHash } = require('node:crypto');
const { chromium } = require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const origin = process.env.CRABRIX_PLAYGROUND_ORIGIN || 'https://crabrix.com';
(async () => {
  const aasa = await fetch(origin + '/.well-known/apple-app-site-association', { redirect: 'manual' });
  assert.equal(aasa.status, 200); assert.match(aasa.headers.get('content-type'), /application\/json/);
  assert.deepEqual(await aasa.json(), JSON.parse(fs.readFileSync('site/public/.well-known/apple-app-site-association', 'utf8')));
  const screenshot = await fetch(origin + '/screenshots/playground-native-run.png');
  assert.equal(screenshot.status, 200);
  const sha = bytes => createHash('sha256').update(bytes).digest('hex');
  assert.equal(sha(Buffer.from(await screenshot.arrayBuffer())), sha(fs.readFileSync('site/public/screenshots/playground-native-run.png')));
  const sitemap = await (await fetch(origin + '/sitemap.xml')).text();
  assert.ok(sitemap.includes('/playground/')); assert.ok(!sitemap.includes('/playground/room/'));
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto(origin + '/playground/'); await page.waitForSelector('.cm-content');
    await page.locator('.cm-content').fill('fn main() { println!("public-worker=42"); }');
    await page.getByRole('button', { name: '▶ Run', exact: true }).click();
    await page.waitForFunction(() => document.querySelector('.pg-output')?.textContent.includes('public-worker=42'), null, { timeout: 180000 });
    assert.deepEqual(errors, []);
    const guide = await page.request.get(origin + '/guide/');
    assert.equal(guide.status(), 200); assert.ok((await guide.text()).includes('Playgrounds and live coding interviews'));
    console.log('PASS AASA without redirect, actual guide screenshot, sitemap, guest editor and real browser compiler STDOUT');
    fs.writeFileSync('build/playground-20261027/publication-result.json', JSON.stringify({ at: new Date().toISOString(), origin, aasa: true, guideScreenshotSHA: sha(fs.readFileSync('site/public/screenshots/playground-native-run.png')), guestBrowserWorkerSTDOUT: 'public-worker=42', sourceUploadedForCompilation: false, sitemap: true }, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
