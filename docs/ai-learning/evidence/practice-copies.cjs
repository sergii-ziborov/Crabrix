// Usage: node practice-copies.cjs <origin> <starters.json|examples.json> <out.json>
// Opens every qualified practice copy in the real browser Playground and runs ✓ Check
// (the same wasm32-wasip1 rustc the learner uses). Records accepted / diagnostics per lesson.
const { chromium } = require('/Users/serhiirihgt/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs = require('node:fs');
(async () => {
  const [origin, startersPath, out] = process.argv.slice(2);
  const source = JSON.parse(fs.readFileSync(startersPath, 'utf8'));
  // Examples (academy-examples.json) open with ?example=<id>; lessons with ?lesson=<course>/<lesson>.
  const starters = source.starters ?? source.examples.map(example => ({ example: example.id, check: 'compiles', wrap: null }));
  const context = await chromium.launchPersistentContext('/tmp/crabrix-ai-e2e/chromium-profile', { viewport: { width: 1280, height: 900 } });
  const page = context.pages()[0] ?? await context.newPage();
  const results = [];
  for (const starter of starters) {
    const path = starter.example ? `example=${starter.example}` : `lesson=${starter.courseId}/${starter.lessonId}`;
    const started = Date.now();
    try {
      const response = await page.goto(`${origin}/playground/?${path}`, { waitUntil: 'domcontentloaded' });
      await page.locator('button.pg-check').waitFor({ state: 'visible', timeout: 60000 });
      await page.waitForFunction(() => !document.querySelector('button.pg-check')?.disabled, null, { timeout: 60000 });
      const notice = await page.evaluate(() => document.body.innerText.match(/(Practice|Example) copy[^\n]*/)?.[0] ?? null);
      await page.click('button.pg-check');
      const outcome = await page.waitForFunction(() => {
        const text = document.body.innerText;
        if (text.includes('Rust accepted the current build snapshot.')) return 'accepted';
        if (document.querySelector('.pg-diagnostic')) return 'diagnostics';
        return false;
      }, null, { timeout: 240000, polling: 500 }).then(handle => handle.jsonValue());
      const levels = outcome === 'diagnostics' ? await page.locator('.pg-diagnostic strong').allInnerTexts() : [];
      const errors = levels.filter(text => /^error/.test(text));
      const verdict = outcome === 'accepted' ? 'accepted' : errors.length ? 'errors' : 'accepted-with-warnings';
      results.push({ path, status: response.status(), check: starter.check, wrap: starter.wrap, outcome: verdict, first: errors[0] ?? levels[0] ?? null, notice, ms: Date.now() - started });
    } catch (error) {
      results.push({ path, check: starter.check, wrap: starter.wrap, outcome: 'error', error: String(error).slice(0, 300), ms: Date.now() - started });
    }
    fs.writeFileSync(out, JSON.stringify(results, null, 1));
  }
  const summary = results.reduce((acc, item) => { const key = `${item.check}:${item.outcome}`; acc[key] = (acc[key] ?? 0) + 1; return acc; }, {});
  fs.writeFileSync(out, JSON.stringify({ summary, results }, null, 1));
  console.log(JSON.stringify(summary));
  await context.close();
})();
