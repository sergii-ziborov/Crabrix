// HTTP smoke audit for the public site. Never uses an account or opens a room.
// node scripts/audit-public-seo.mjs https://crabrix.com /tmp/seo-receipt.json
import { writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const base = new URL(process.argv[2] || 'https://crabrix.com');
const origin = 'https://crabrix.com';
const issues = [];
const decode = text => text.replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n));
const attributes = tag => Object.fromEntries([...tag.matchAll(/([\w:-]+)="([^"]*)"/g)].map(match => [match[1], decode(match[2])]));
const tags = (html, name) => [...html.matchAll(new RegExp(`<${name}\\b[^>]*>`, 'g'))].map(match => attributes(match[0]));
const at = path => new URL(path, base).href;
async function get(path, options) {
  const response = await fetch(at(path), { signal: AbortSignal.timeout(45_000), ...options });
  return { response, html: await response.text() };
}
async function bounded(items, action) {
  let cursor = 0;
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (cursor < items.length) {
      const item = items[cursor++];
      try { await action(item); } catch (error) { issues.push({ url: item, error: error.message }); }
    }
  }));
}

const { response: sitemapResponse, html: sitemap } = await get('/sitemap.xml');
assert.equal(sitemapResponse.status, 200);
const urls = [...sitemap.matchAll(/<url>\s*<loc>([^<]+)<\/loc>/g)].map(match => decode(match[1]));
assert.ok(urls.length > 0, 'Empty sitemap');
assert.equal(new Set(urls).size, urls.length, 'Duplicate sitemap URLs');
assert.ok(urls.every(url => new URL(url).origin === origin && !new URL(url).search));
const pages = new Map();
const unique = { title: new Map(), description: new Map() };
let lessons = 0, algorithmSteps = 0;
await bounded(urls, async url => {
  const path = new URL(url).pathname;
  const { response, html } = await get(path);
  assert.equal(response.status, 200);
  const meta = tags(html, 'meta'), link = tags(html, 'link');
  const canonical = link.filter(tag => tag.rel === 'canonical').map(tag => tag.href);
  assert.deepEqual(canonical, [url]);
  assert.equal((html.match(/<h1\b/g) || []).length, 1, 'Expected one H1');
  assert.ok(!/noindex/i.test(response.headers.get('x-robots-tag') || ''));
  assert.ok(!meta.some(tag => /^(robots|googlebot)$/.test(tag.name) && /noindex/.test(tag.content)));
  const title = decode(html.match(/<title>([\s\S]*?)<\/title>/)?.[1] || '');
  const descriptions = meta.filter(tag => tag.name === 'description').map(tag => tag.content);
  assert.equal(descriptions.length, 1);
  for (const [name, value] of [['title', title], ['description', descriptions[0]]]) {
    assert.ok(value?.length > 20, `Missing ${name}`);
    assert.ok(!unique[name].has(value), `Duplicate ${name}: ${unique[name].get(value)}`);
    unique[name].set(value, url);
  }
  assert.deepEqual(meta.filter(tag => tag.property === 'og:url').map(tag => tag.content), [url]);
  for (const match of html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)) JSON.parse(match[1]);
  for (const image of tags(html, 'img')) assert.ok('alt' in image && +image.width > 0 && +image.height > 0, `Image attributes: ${image.src}`);
  if (/^\/learn\/[^/]+\/[^/]+\/?$/.test(path)) {
    lessons++;
    assert.ok(html.includes('lesson-content lesson-full'), 'Complete lesson missing');
    assert.ok(!html.includes('The rest of this lesson is waiting for you.'), 'Registration gate remains');
    assert.ok(/<pre\b/.test(html), 'Public worked code missing');
    const article = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].flatMap(match => JSON.parse(match[1])['@graph'] || []).find(item => item['@type'] === 'Article');
    assert.equal(article?.isAccessibleForFree, true, 'Incorrect free-content markup');
  }
  if (path.startsWith('/learn/algorithms/algorithm.')) {
    algorithmSteps++;
    assert.ok(html.includes('Steps in this algorithm pattern'));
    assert.ok(html.includes('The pattern') && html.includes('Try it'), 'Full algorithm teaching missing');
  }
  if (path === '/learn/algorithms/') assert.equal((html.match(/class="method-guide"/g) || []).length, 20);
  pages.set(url, { ids: new Set([...html.matchAll(/\bid="([^"]+)"/g)].map(match => decode(match[1]))), links: tags(html, 'a').map(tag => tag.href).filter(Boolean) });
});
let fragments = 0;
for (const [url, page] of pages) for (const raw of page.links) {
  const target = new URL(raw, url);
  if (target.origin !== origin || !target.hash) continue;
  const fragment = decodeURIComponent(target.hash.slice(1)); target.hash = ''; target.search = '';
  const linkedPage = pages.get(target.href);
  if (linkedPage) {
    fragments++;
    if (!linkedPage.ids.has(fragment)) issues.push({ url, error: `Missing fragment: ${raw}` });
  }
}
for (const path of ['/login/', '/register/', '/recover/', '/not-a-crabrix-page-seo-check/']) {
  const { response, html } = await get(path);
  if (path.startsWith('/not-a-')) assert.equal(response.status, 404);
  assert.ok(/noindex/.test(response.headers.get('x-robots-tag') || '') || tags(html, 'meta').some(tag => tag.name === 'robots' && /noindex/.test(tag.content)));
}
for (const agent of ['Mozilla/5.0', 'Googlebot', 'Twitterbot']) {
  const { response, html } = await get('/learn/projects/serde-roundtrip-validation/', { headers: { 'user-agent': agent } });
  assert.equal(response.status, 200);
  assert.ok(html.includes('lesson-content lesson-full') && html.includes('RecordVisitor'));
  assert.ok(!html.includes('The rest of this lesson is waiting for you.'));
  const starter = await get('/playground/?lesson=projects/serde-roundtrip-validation', { headers: { 'user-agent': agent }, redirect: 'manual' });
  assert.equal(starter.response.status, 200);
  assert.ok(starter.html.includes('RecordVisitor'), 'Public validated starter missing');
}
for (const [path, status] of [['/learn-media/projects/serde-roundtrip-validation.png', 200], ['/learn-media/projects/not-a-lesson.png', 404], ['/learn-media/projects/courses.json', 404], ['/content/courses.json', 404]]) {
  assert.equal((await get(path)).response.status, status);
}
// A cache-busting RSC parameter must never noindex its normal HTML equivalent.
assert.equal((await get('/account/export/', { redirect: 'manual' })).response.status, 401);
const query = await get('/learn/algorithms/?_rsc=seo-smoke');
assert.equal(query.response.status, 200);
assert.ok(query.response.headers.get('content-type')?.includes('text/html'));
assert.ok(!/noindex/.test(query.response.headers.get('x-robots-tag') || ''));
assert.deepEqual(tags(query.html, 'link').filter(tag => tag.rel === 'canonical').map(tag => tag.href), [origin + '/learn/algorithms/']);
assert.equal((await get('/favicon.ico')).response.status, 200);

const receipt = { checkedAt: new Date().toISOString(), base: base.origin, canonicalPages: urls.length, pagesChecked: pages.size, lessons, algorithmSteps, checkedInternalFragments: fragments, publicLessonsPassed: true, privateAccountRoutesNoindex: true, htmlRscQueryIndexable: true, issues };
if (process.argv[3]) writeFileSync(process.argv[3], JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
if (issues.length) process.exitCode = 1;
