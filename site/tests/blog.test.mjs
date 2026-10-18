import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
const posts = JSON.parse(readFileSync(new URL('../content/posts.json', import.meta.url)));
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

const additions = posts.filter(post => post.date > '2026-10-10');
test('October expansion preserves five originals and adds five dated, longer original guides', () => {
  assert.equal(posts.length, 10);
  assert.equal(additions.length, 5);
  const original = posts.filter(post => post.date <= '2026-10-10');
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
