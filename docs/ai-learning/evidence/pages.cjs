// Usage: node pages.cjs <origin> <outdir>
const { chromium } = require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs = require('node:fs');
(async () => {
  const [origin, out] = process.argv.slice(2);
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch();
  const result = {};
  for (const width of [390, 820, 1440]) {
    const context = await browser.newContext({ viewport: { width, height: 900 }, permissions: ['clipboard-read', 'clipboard-write'] });
    const page = await context.newPage();
    const errors = [], posts = [];
    page.on('pageerror', e => errors.push(String(e)));
    page.on('request', r => { if (r.url().includes('/api/academy/v1/events')) posts.push({ body: r.postData(), cookie: r.headers()['cookie'] ?? null }); });
    page.on('popup', p => p.close().catch(() => {}));
    const info = {};
    await page.goto(`${origin}/learn/with-ai/`, { waitUntil: 'networkidle' });
    await page.click('#agent-tab-codex');
    await page.click('#agent-panel-codex button.btn');
    info.withAiClipboard = await page.evaluate(() => navigator.clipboard.readText());
    await page.locator('.prompt-card button').nth(1).click();
    info.promptClipboard = await page.evaluate(() => navigator.clipboard.readText());
    info.continueSection = await page.locator('#continue').count();
    info.staticFeedback = await page.locator('.ai-feedback-static').count();
    info.withAiOverflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    await page.screenshot({ path: `${out}/with-ai-${width}.png`, fullPage: true });
    await page.goto(`${origin}/learn/basics/variables/?via=ai`, { waitUntil: 'networkidle' });
    info.lessonUrlAfterArrival = page.url();
    info.practiceButton = await page.locator('a', { hasText: 'Practise this code in Playground' }).count();
    await page.click('.ai-lesson summary');
    await page.click('.ai-lesson-actions button:nth-child(2)');
    info.lessonClipboard = (await page.evaluate(() => navigator.clipboard.readText())).split('\n').slice(0, 2);
    info.lessonOverflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    await page.locator('.ai-lesson').screenshot({ path: `${out}/lesson-ai-${width}.png` });
    // Pretend the first AI use was an hour ago: the prompted card appears once.
    await page.evaluate(() => localStorage.setItem('crabrix.ai.firstUse.v1', String(Date.now() - 3600_000)));
    await page.goto(`${origin}/learn/`, { waitUntil: 'networkidle' });
    info.promptedCard = await page.locator('.ai-feedback-prompted').count();
    await page.locator('.ai-feedback-prompted').screenshot({ path: `${out}/feedback-${width}.png` });
    await page.click('.ai-feedback-prompted button:has-text("Partly")');
    info.afterAnswer = await page.locator('.ai-feedback-prompted textarea').count();
    await page.click('.ai-feedback-prompted button:has-text("Done")');
    await page.reload({ waitUntil: 'networkidle' });
    info.cardAfterReload = await page.locator('.ai-feedback-prompted').count();
    info.learnOverflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    await page.goto(`${origin}/playground/?lesson=basics/variables&via=ai`, { waitUntil: 'networkidle' });
    info.playgroundUrlAfterArrival = page.url();
    info.playgroundNotice = await page.evaluate(() => document.body.innerText.match(/Practice copy[^\n]*/)?.[0] ?? null);
    if (width === 1440) {
      await page.waitForFunction(() => !document.querySelector('button.pg-primary')?.disabled, null, { timeout: 60000 });
      await page.click('button.pg-primary');
      await page.waitForSelector('.pg-build-time', { timeout: 240000 });
      info.runOutput = (await page.locator('.pg-build-time').innerText());
      await page.screenshot({ path: `${out}/playground-practice-${width}.png` });
    }
    await page.waitForTimeout(800);
    info.events = posts.map(p => p.body);
    info.eventCookies = posts.filter(p => p.cookie).length;
    info.errors = errors;
    result[width] = info;
    await context.close();
  }
  // GPC on: nothing is sent.
  const gpc = await browser.newContext();
  await gpc.addInitScript(() => Object.defineProperty(Navigator.prototype, 'globalPrivacyControl', { get: () => true }));
  const page = await gpc.newPage();
  let sent = 0;
  page.on('request', r => { if (r.url().includes('/api/academy/v1/events')) sent++; });
  await page.goto(`${origin}/learn/with-ai/`, { waitUntil: 'networkidle' });
  await page.click('#agent-tab-cursor');
  result.gpcEventsSent = sent;
  fs.writeFileSync(`${out}/result.json`, JSON.stringify(result, null, 1));
  await browser.close();
  console.log('done');
})();
