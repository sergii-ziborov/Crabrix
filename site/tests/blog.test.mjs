import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const posts = JSON.parse(readFileSync(new URL('../content/posts.json', import.meta.url)));
const october24Slugs = ["crabrix-offline-progress-game-center", "rust-futures-cooperative-work", "rust-generational-handles-stable-identity", "rust-dependency-graphs-deterministic-plans", "crabrix-offline-rust-web-preview"];
const earlierPosts = posts.filter(p => !october24Slugs.includes(p.slug));
test('three 10 October Rust articles meet the requested length and image count', () => {
  const images = new Set();
  for (const slug of ['rust-1-99-upgrade', 'ownership-in-a-real-program', 'result-errors-that-help']) {
    const post = posts.find(p => p.slug === slug);
    assert.ok(post);
    assert.ok(post.sections.flatMap(s => s.paragraphs).join(' ').split(/\s+/).length >= 1500, slug);
    const illustrations = post.sections.filter(s => s.image).map(s => s.image);
    assert.equal(illustrations.length, 2);
    assert.ok(illustrations.some(image => image.src.endsWith('-infographic.png')));
    for (const image of illustrations) {
      assert.ok(image.alt && image.caption);
      const bytes = readFileSync(new URL('../public' + image.src, import.meta.url));
      images.add(createHash('sha256').update(bytes).digest('hex'));
    }
  }
  assert.equal(images.size, 6);
});

const october18Slugs = ['rust-iterators-without-extra-allocations', 'rust-strings-utf8-safe-parsing', 'testing-rust-boundaries-fixtures-doctests', 'cargo-features-portable-dependencies', 'rust-enums-state-machines'];
const additions = posts.filter(post => october18Slugs.includes(post.slug));
test('October expansion preserves five originals and adds five dated, longer original guides', () => {
  assert.ok(posts.length >= 10);
  assert.equal(additions.length, 5);
  const original = earlierPosts.filter(post => post.date <= '2026-10-10');
  const words = post => post.sections.flatMap(section => section.paragraphs).join(' ').trim().split(/\s+/).length;
  const baseline = original.reduce((sum, post) => sum + words(post), 0) / original.length;
  assert.equal(new Set(additions.map(post => post.date)).size, 5);
  assert.deepEqual(posts.map(post => post.date), posts.map(post => post.date).toSorted().reverse());
  const paragraphs = new Set();
  for (const post of posts) {
    for (const paragraph of post.sections.flatMap(section => section.paragraphs)) {
      assert.ok(!paragraphs.has(paragraph), `Repeated prose: ${post.slug}`);
      paragraphs.add(paragraph);
    }
  }
  for (const post of additions) {
    assert.ok(post.date > '2026-10-10' && post.date <= '2026-10-18');
    assert.ok(words(post) >= baseline + 400 && words(post) <= baseline + 700, post.slug);
    assert.equal(post.readingMinutes, Math.ceil(words(post) / 200));
    assert.equal(new Set(post.sections.map(section => section.heading)).size, post.sections.length);
    assert.ok(post.summary.length >= 120 && post.summary.length <= 180);
    assert.equal(post.relatedSlugs.length, 3);
    assert.ok(post.relatedSlugs.every(slug => slug !== post.slug && posts.some(candidate => candidate.slug === slug)));
    assert.ok(post.sections.some(section => section.code));
    assert.ok(post.sections.flatMap(section => section.sources ?? []).every(source => source.url.startsWith('https://doc.rust-lang.org/')));
  }
});

test('each new guide ships two unique generated images, including a dimensioned infographic', () => {
  const hashes = new Set();
  const paths = new Set();
  for (const post of additions) {
    const images = post.sections.flatMap(section => section.image ? [section.image] : []);
    assert.equal(images.length, 2);
    assert.equal(images.filter(image => image.src.endsWith('-infographic.png')).length, 1);
    for (const image of images) {
      assert.ok(image.alt.length > 40 && image.caption.length > 40);
      assert.equal(image.width, 1536);
      assert.equal(image.height, 1024);
      const bytes = readFileSync(new URL('../public' + image.src, import.meta.url));
      assert.equal(bytes.subarray(1, 4).toString(), 'PNG');
      assert.equal(bytes.readUInt32BE(16), image.width);
      assert.equal(bytes.readUInt32BE(20), image.height);
      hashes.add(createHash('sha256').update(bytes).digest('hex'));
      paths.add(image.src);
    }
  }
  assert.equal(hashes.size, 10);
  assert.equal(paths.size, 10);
});

test('20 October guides have distinct days, 1500 prose words, code and two original images', () => {
  const slugs = ['rust-pattern-matching-without-panics', 'rust-hashmap-entry-stable-reports', 'rust-checked-arithmetic-conversions', 'rust-traits-generics-dynamic-dispatch', 'rust-buffered-text-input-errors'];
  const batch = posts.filter(post => slugs.includes(post.slug));
  assert.equal(batch.length, 5);
  assert.equal(new Set(batch.map(post => post.date)).size, 5);
  const hashes = new Set();
  for (const post of batch) {
    assert.ok(post.date <= '2026-10-20');
    const words = post.sections.flatMap(section => section.paragraphs).join(' ').split(/\s+/).length;
    assert.ok(words >= 1500, `${post.slug}: ${words}`);
    assert.equal(post.readingMinutes, Math.ceil(words / 200));
    assert.ok(post.sections.some(section => section.code));
    const images = post.sections.flatMap(section => section.image ? [section.image] : []);
    assert.equal(images.length, 2);
    assert.equal(images.filter(image => image.src.endsWith('-analysis.png')).length, 1);
    for (const image of images) {
      const bytes = readFileSync(new URL('../public' + image.src, import.meta.url));
      assert.equal(bytes.readUInt32BE(16), image.width);
      assert.equal(bytes.readUInt32BE(20), image.height);
      hashes.add(createHash('sha256').update(bytes).digest('hex'));
      assert.ok(image.alt.length > 40 && image.caption.length > 40);
    }
  }
  assert.equal(hashes.size, 10);
});

test('every article image has complete WebP delivery copies with a smaller download budget', () => {
  const sources = new Set(posts.flatMap(post => post.sections.flatMap(section => section.image ? [section.image.src] : [])));
  let originalBytes = 0, fullBytes = 0, cardBytes = 0;
  for (const source of sources) {
    const original = readFileSync(new URL('../public' + source, import.meta.url));
    const stem = source.replace(/\.png$/, '');
    const variants = ['.webp', '-640.webp'].map(suffix => readFileSync(new URL('../public' + stem + suffix, import.meta.url)));
    for (const bytes of variants) {
      assert.equal(bytes.toString('ascii', 0, 4), 'RIFF', source);
      assert.equal(bytes.toString('ascii', 8, 12), 'WEBP', source);
      assert.equal(bytes.readUInt32LE(4) + 8, bytes.length, source);
    }
    originalBytes += original.length; fullBytes += variants[0].length; cardBytes += variants[1].length;
  }
  assert.equal(sources.size, 50);
  assert.ok(fullBytes < originalBytes * 0.15, 'full WebP copies must save at least 85%');
  assert.ok(cardBytes < originalBytes * 0.05, 'card copies must save at least 95%');
});

test('23 October expansion adds three sourced news analyses and two longer practical guides on free days', () => {
  const news = new Map([
    ['rustup-1-29-2-certificate-update', 'https://blog.rust-lang.org/2026/10/20/Rustup-1.29.2/'],
    ['rust-1-100-i686-windows-host-tools', 'https://blog.rust-lang.org/2026/10/02/demoting-i686-windows-targets-to-std-only/'],
    ['rust-infrastructure-q3-2026-registry-resilience', 'https://blog.rust-lang.org/inside-rust/2026/10/12/infrastructure-team-q3-recap-and-q4-plan/'],
  ]);
  const slugs = [...news.keys(), 'cargo-build-scripts-generated-code', 'rust-memoization-cache-contracts'];
  const batch = posts.filter(post => slugs.includes(post.slug));
  const previous = earlierPosts.filter(post => !slugs.includes(post.slug));
  const words = post => post.sections.flatMap(section => section.paragraphs).join(' ').trim().split(/\s+/).length;
  const longestPrevious = Math.max(...previous.map(words));
  assert.equal(earlierPosts.length, 20);
  assert.equal(previous.length, 15);
  assert.equal(batch.length, 5);
  assert.deepEqual(batch.map(post => post.date), ['2026-10-23', '2026-10-22', '2026-10-21', '2026-10-14', '2026-10-11']);
  const hashes = new Set();
  for (const post of batch) {
    assert.ok(!previous.some(old => old.date === post.date), post.date);
    assert.ok(words(post) > longestPrevious, `${post.slug}: must exceed ${longestPrevious} prose words`);
    assert.equal(post.readingMinutes, Math.ceil(words(post) / 200));
    assert.ok(post.summary.length >= 120 && post.summary.length <= 180);
    assert.ok(post.title.length <= 75);
    assert.equal(post.relatedSlugs.length, 3);
    assert.equal(new Set(post.relatedSlugs).size, 3);
    assert.ok(post.relatedSlugs.every(slug => slug !== post.slug && posts.some(p => p.slug === slug)));
    assert.ok(post.sections.some(s => s.code && s.codeLanguage === 'rust'));
    const images = post.sections.flatMap(s => s.image ? [s.image] : []);
    assert.equal(images.length, 2);
    assert.equal(images.filter(img => img.src.endsWith('-infographic.png')).length, 1);
    for (const img of images) {
      const bytes = readFileSync(new URL('../public' + img.src, import.meta.url));
      assert.equal(bytes.readUInt32BE(16), img.width);
      assert.equal(bytes.readUInt32BE(20), img.height);
      assert.ok(img.alt.length > 40 && img.caption.length > 40);
      hashes.add(createHash('sha256').update(bytes).digest('hex'));
    }
    if (news.has(post.slug)) {
      assert.ok(post.sections.flatMap(s => s.sources ?? []).some(s => s.url === news.get(post.slug)));
    }
  }
  assert.equal(hashes.size, 10);
});


test('24 October expansion preserves the catalog and adds five longer illustrated articles on free dates', () => {
  const batch = posts.filter(p => october24Slugs.includes(p.slug));
  const words = p => p.sections.flatMap(s => s.paragraphs).join(' ').trim().split(/\s+/).length;
  assert.equal(posts.length, 25);
  assert.equal(batch.length, 5);
  assert.deepEqual(batch.map(p => p.date), ['2026-10-24','2026-10-08','2026-10-07','2026-10-06','2026-10-05']);
  const longest = Math.max(...earlierPosts.map(words));
  const images = new Set();
  for (const p of batch) {
    assert.ok(words(p) >= 1500 && words(p) > longest, p.slug);
    assert.ok(!earlierPosts.some(q => q.date === p.date));
    assert.equal(p.readingMinutes, Math.ceil(words(p)/200));
    assert.ok(p.title.length <= 75 && p.summary.length >= 120 && p.summary.length <= 180);
    assert.equal(p.relatedSlugs.length, 3);
    assert.ok(p.relatedSlugs.every(slug => slug !== p.slug && posts.some(q => q.slug === slug)));
    const assets = p.sections.flatMap(s => s.image ? [s.image] : []);
    assert.equal(assets.length, 2);
    assert.equal(assets.filter(a => a.src.endsWith('-infographic.png')).length, 1);
    for(const a of assets) {
      const bytes = readFileSync(new URL('../public'+a.src, import.meta.url));
      assert.equal(bytes.readUInt32BE(16), a.width);
      assert.equal(bytes.readUInt32BE(20), a.height);
      images.add(createHash('sha256').update(bytes).digest('hex'));
    }
    assert.ok(p.sections.some(s => s.code && s.codeLanguage === 'rust'));
  }
  assert.equal(images.size, 10);
});
